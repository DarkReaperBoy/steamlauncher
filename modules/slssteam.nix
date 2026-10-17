# SLSsteam feature: upstream injection + the slsteam-moon fork, plus the
# SLSsteam tool binaries. Unit shape: `{ inputs }: rec { builders; module; }` —
# flake.nix instantiates this once and takes `.module` (NixOS module output)
# and `.mk*` (packages.* outputs), so a package and the option that installs
# it are always the same derivation.
{ sls-steam, mkSlsteamMoon }:
rec {
  # Upstream SLSsteam artefacts (SLSsteam.so + library-inject.so), same as the
  # official wiki's NixOS instructions use.
  mkSlsSteam = pkgs: sls-steam.packages.${pkgs.stdenv.hostPlatform.system}.sls-steam;
  mkTicketGrabber = pkgs: sls-steam.packages.${pkgs.stdenv.hostPlatform.system}.ticket-grabber;
  mkSchemaGrabber = pkgs: sls-steam.packages.${pkgs.stdenv.hostPlatform.system}.schema-grabber;

  # slsteam-moon: fork with a native Lua manifest importer. Its own GitHub
  # release ships the two injected objects, so this is a fetch of that archive
  # (see modules/upstream-binaries.nix) — no 32-bit compile, no toolchain, and
  # the version tracks upstream's releases instead of a pinned git rev.

  module =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nix-crab;

      upstream = mkSlsSteam pkgs;

      # Both forks ship the same two artefacts under the same names (SLSsteam.so +
      # library-inject.so), so the choice is one store path, not two branches of
      # wiring. slsteam-moon is built from source — see mkSlsteamMoon above for
      # the toolchain and the GCC <cstdint> workaround.
      sls = if cfg.slssteam-moon.enable then mkSlsteamMoon pkgs else upstream;

      injectionEnabled = cfg.slssteam.enable || cfg.slssteam-moon.enable;

      # Base package the LD_AUDIT wrapper is built from. An explicit
      # programs.nix-crab.steam.package wins; with Millennium enabled its
      # overlay provides millennium-steam — a `steam.override` of its own
      # steam.nix — so re-overriding here re-enters *that* function and its
      # `extraEnv // millenniumEnv` merge keeps MILLENNIUM_RUNTIME_PATH alongside
      # LD_AUDIT. (Remapping pkgs.steam to millennium-steam instead would recurse
      # now that Millennium's overlay resolves its `steam` argument from the final
      # package set.)
      steamBase =
        if cfg.steam.package != null then
          cfg.steam.package
        else if cfg.millennium.enable then
          pkgs.millennium-steam
        else
          pkgs.steam;

      # Features that cannot do anything without the Steam client.
      steamNeeded = injectionEnabled || cfg.millennium.enable || (cfg.steam.config.enable or false);

      # `null` (default) = let the features decide; true/false force it.
      steamOn = if cfg.steam.enable == null then steamNeeded else cfg.steam.enable;
    in
    {
      # steam-config-nix under the nix-crab umbrella (programs.steam.config is
      # its own namespace; this only forwards it).
      imports = [
        ./steam-config.nix
      ];

      options.programs.nix-crab = {
        steam.enable = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = ''
            Whether the Steam client is enabled. Leave unset (null) and it
            turns on by itself as soon as a nix-crab feature needs it
            (slssteam, slsteam-moon, millennium or steam.config); set true to
            install Steam without any of them, false to force it off (features
            that need it then fail evaluation instead of silently doing
            nothing).
          '';
        };

        steam.package = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = null;
          example = "pkgs.steam-small";
          description = ''
            The Steam package everything is built on. null (default) picks
            pkgs.steam — or Millennium's `millennium-steam` when
            programs.nix-crab.millennium.enable is set, which is what keeps
            MILLENNIUM_RUNTIME_PATH alongside the SLSsteam LD_AUDIT. Injection
            is applied on top of whatever is set here.
          '';
        };

        steam.extraCompatPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          example = "lib.singleton pkgs.proton-ge-custom";
          description = ''
            Compatibility tools made available to Steam
            (programs.steam.extraCompatPackages). steam-config-nix's own
            `compatTool = <package>` entries land here too, through
            programs.steam.config.
          '';
        };

        slssteam.enable = lib.mkEnableOption "SLSsteam (upstream) injection into Steam";

        slssteam.extraEnv = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Additional environment variables injected into Steam";
        };

        slssteam-moon.enable = lib.mkEnableOption ''
          slsteam-moon (SLSsteam fork with a Lua manifest importer) instead of
          upstream SLSsteam. Takes precedence over slssteam.enable; required by
          the luatools option. Built from source (32-bit compile).
        '';
      };

      config = {
        assertions = [
          {
            # Both want Steam's CEF debugging endpoint (Millennium takes it via
            # --remote-debugging-pipe, LuaTools needs the TCP port) — same
            # mutual exclusion upstream documents between Millennium and LuaTools.
            assertion = !(cfg.millennium.enable && cfg.slssteam-moon.enable);
            message = ''
              programs.nix-crab.millennium.enable and programs.nix-crab.slssteam-moon.enable
              are mutually exclusive: both want Steam's CEF debugging endpoint.
              Pick Millennium (themes/plugins) or slsteam-moon + luatools (LuaTools).
            '';
          }
          {
            # Every feature here needs the client. Turning Steam off — through
            # either knob — while one of them is on is always a mistake.
            assertion = !(steamNeeded && !config.programs.steam.enable);
            message = ''
              A nix-crab feature needs the Steam client, but Steam is disabled:
              programs.nix-crab.steam.enable / programs.steam.enable must not be
              false while slssteam, slssteam-moon, millennium or steam.config is
              in use.
            '';
          }
        ];

        programs.steam = lib.mkMerge [
          (lib.mkIf steamOn {
            enable = lib.mkDefault true;
            extraCompatPackages = cfg.steam.extraCompatPackages;
          })
          (lib.mkIf (injectionEnabled || cfg.steam.package != null) {
            package =
              if injectionEnabled then
                steamBase.override {
                  extraEnv =
                    lib.optionalAttrs injectionEnabled {
                      LD_AUDIT = "${sls}/library-inject.so:${sls}/SLSsteam.so";
                    }
                    // cfg.slssteam.extraEnv;
                }
              else
                cfg.steam.package;
          })
        ];
      };
    };
}
