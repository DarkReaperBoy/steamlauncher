# SLSsteam feature: upstream injection + the slsteam-moon fork, plus the
# SLSsteam tool binaries. Unit shape: `{ inputs }: rec { builders; module; }` —
# flake.nix instantiates this once and takes `.module` (NixOS module output)
# and `.mk*` (packages.* outputs), so a package and the option that installs
# it are always the same derivation.
#
# This module also owns `programs.nix-crab.steam` — the single Steam knob.
# Everything Steam goes through it: enable/package/extraPkgs/extraCompat-
# Packages/config are typed here, every other upstream `programs.steam`
# option (remotePlay, protontricks, gamescopeSession, ...) is passed through
# freeform and type-checked upstream, and `steam = true` is sugar for
# `steam.enable = true`. Features enable Steam themselves when they need it
# (steamNeeded below), so slssteam.enable = true alone turns on Steam WITH
# the injected package — no second switch, no raw programs.steam.
{ mkSlsSteam, mkSlsteamMoon }:
rec {
  module =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        mkOption
        mkEnableOption
        types
        ;
      cfg = config.programs.nix-crab;
      steamCfg = cfg.steam;

      # One source of truth for the steam submodule defaults: the submodule
      # options below read these, and the `steam = true` apply-branch re-uses
      # them, so bool sugar still carries every key readers touch.
      steamDefaults = {
        enable = null;
        package = null;
        extraPkgs = [ ];
        extraCompatPackages = [ ];
        config = { };
      };

      upstream = mkSlsSteam pkgs;

      # Both forks ship the same two artefacts under the same names (SLSsteam.so +
      # library-inject.so), so the choice is one store path, not two branches of
      # wiring — both are release binaries from modules/upstream-binaries.nix.
      sls = if cfg.slssteam-moon.enable then mkSlsteamMoon pkgs else upstream;

      injectionEnabled = cfg.slssteam.enable || cfg.slssteam-moon.enable;

      # Base package the LD_AUDIT wrapper is built from. An explicit
      # programs.nix-crab.steam.package wins; with Millennium enabled its
      # overlay provides millennium-steam — a `steam.override` of its own
      # steam.nix — so re-overriding here re-enters *that* function and its
      # `extraEnv // millenniumEnv` merge keeps MILLENNIUM_RUNTIME_PATH alongside
      # LD_AUDIT.
      steamBase =
        if steamCfg.package != null then
          steamCfg.package
        else if cfg.millennium.enable then
          pkgs.millennium-steam
        else
          pkgs.steam;

      # Features that cannot do anything without the Steam client.
      steamNeeded = injectionEnabled || cfg.millennium.enable || (steamCfg.config.enable or false);

      # enable = null (default) = let the features decide; true/false force it.
      steamOn = if steamCfg.enable == null then steamNeeded else steamCfg.enable;

      # extraPkgs: a plain list, or a function `p: [...]` applied inside the
      # Steam FHS environment (nixpkgs' own extraPkgs contract). Either way it
      # is fed into the ONE override below — the old "put extraPkgs on
      # pkgs.steam via an overlay because programs.steam.package rejects two
      # definitions" workaround is gone; this option is the override.
      #
      # lib.isFunction, NOT builtins.isFunction: the functionTo option type
      # merges a function value into a functor set ({ __functor; __functionArgs; })
      # that is callable but fails the builtin check — builtins.isFunction would
      # take the list branch and feed the set to `++` inside nixpkgs' steam.
      extraPkgsFn =
        if lib.isFunction steamCfg.extraPkgs then steamCfg.extraPkgs else (_: steamCfg.extraPkgs);

      # Injection env: LD_AUDIT from the active fork + the user's extras.
      injectEnv =
        lib.optionalAttrs injectionEnabled {
          LD_AUDIT = "${sls}/library-inject.so:${sls}/SLSsteam.so";
        }
        // cfg.slssteam.extraEnv;

      # Everything under `steam` that is not one of our typed keys is an
      # upstream programs.steam option (remotePlay.openFirewall,
      # protontricks.enable, dedicatedServer, extest, ...) and is forwarded
      # verbatim — upstream's types and docs stay authoritative.
      passthrough = removeAttrs steamCfg [
        "enable"
        "package"
        "extraPkgs"
        "extraCompatPackages"
        "config"
      ];

      needsOverride = injectionEnabled || steamCfg.package != null || steamCfg.extraPkgs != [ ];
    in
    {
      # steam-config-nix under the nix-crab umbrella (programs.steam.config is
      # its own namespace; this only forwards it).
      imports = [
        ./steam-config.nix
      ];

      options.programs.nix-crab = {
        steam = mkOption {
          # `either` + `apply`: `steam = true` is sugar for
          # `steam = { enable = true; }`, and every reader below sees the
          # attrset form.
          type = types.either types.bool (
            types.submodule {
              freeformType = types.attrsOf types.anything;
              options = {
                enable = mkOption {
                  type = types.nullOr types.bool;
                  default = steamDefaults.enable;
                  description = ''
                    Whether the Steam client is enabled. Leave unset (null) and it
                    turns on by itself as soon as a nix-crab feature needs it
                    (slssteam, slsteam-moon, millennium or steam.config); set true
                    to install Steam without any of them, false to force it off
                    (features that need it then fail evaluation instead of
                    silently doing nothing). `steam = true` is short for
                    `steam.enable = true`.
                  '';
                };

                package = mkOption {
                  type = types.nullOr types.package;
                  default = steamDefaults.package;
                  example = "pkgs.steam-small";
                  description = ''
                    The Steam package everything is built on. null (default) picks
                    pkgs.steam — or Millennium's `millennium-steam` when
                    programs.nix-crab.millennium.enable is set, which is what keeps
                    MILLENNIUM_RUNTIME_PATH alongside the SLSsteam LD_AUDIT.
                    Injection and extraPkgs are applied on top of whatever is set
                    here.
                  '';
                };

                extraPkgs = mkOption {
                  type = types.either (types.listOf types.package) (types.functionTo (types.listOf types.package));
                  default = steamDefaults.extraPkgs;
                  example = "p: with p; [ libXcursor libXi ]";
                  description = ''
                    Extra libraries for the Steam FHS environment, fed into the
                    single `steam.override` this module performs — write overlay-
                    style package lists here instead of touching
                    `nixpkgs.overlays` or `programs.steam.package`. A plain list
                    is used as-is; a function `p: [...]` is applied inside the
                    Steam FHS environment, exactly like nixpkgs' own extraPkgs
                    argument. (A list written with your own `pkgs` also works —
                    the FHS environment splices store paths.)
                  '';
                };

                extraCompatPackages = mkOption {
                  type = types.listOf types.package;
                  default = steamDefaults.extraCompatPackages;
                  example = "lib.singleton pkgs.proton-ge-custom";
                  description = ''
                    Compatibility tools made available to Steam
                    (programs.steam.extraCompatPackages). steam-config-nix's own
                    `compatTool = <package>` entries land here too, through
                    steam.config.
                  '';
                };

                config = mkOption {
                  type = types.attrsOf types.anything;
                  default = steamDefaults.config;
                  example = {
                    enable = true;
                    apps."438100" = {
                      name = "VRChat";
                      args = [ "--fps=60" ];
                    };
                  };
                  description = ''
                    Alias of {option}`programs.steam.config` (steam-config-nix).
                    Anything written here is forwarded to it, so the whole
                    per-game configuration surface — launch options, compat
                    tools, prefixes, game files, artwork, non-Steam apps — is
                    reachable from one namespace. Upstream docs apply 1:1.
                  '';
                };
              };
            }
          );
          default = { };
          # `steam = true` bypasses the submodule (a bool carries no inner
          # defaults), so build the attrset from the same defaults the submodule
          # options use — one source, both branches identical to read from.
          apply = v: if builtins.isBool v then steamDefaults // { enable = v; } else v;
          description = ''
            The Steam client, unified: enable/package/extraPkgs/
            extraCompatPackages/config are typed here, every other
            programs.steam option (remotePlay.openFirewall,
            protontricks.enable, gamescopeSession, ...) is passed through
            freeform and type-checked by NixOS itself. `steam = true` is sugar
            for `steam.enable = true`. Features turn Steam on automatically
            when they need it.
          '';
        };

        slssteam.enable = mkEnableOption "SLSsteam (upstream) injection into Steam";

        slssteam.extraEnv = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = "Additional environment variables injected into Steam";
        };

        slssteam-moon.enable = mkEnableOption ''
          slsteam-moon (SLSsteam fork with a Lua manifest importer) instead of
          upstream SLSsteam. Takes precedence over slssteam.enable; required by
          the luatools option.
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
              false while slssteam, slsteam-moon, millennium or steam.config is
              in use.
            '';
          }
        ];

        programs.steam = lib.mkMerge [
          (lib.mkIf steamOn {
            enable = lib.mkDefault true;
            extraCompatPackages = steamCfg.extraCompatPackages;
          })
          # Freeform passthrough of every other upstream option (firewalls,
          # protontricks, dedicatedServer, ...). mkIf so an absent key never
          # injects a default definition upstream would have to merge with.
          (lib.mkIf (passthrough != { }) passthrough)
          (lib.mkIf needsOverride {
            # One override carries injection env and extraPkgs together; with
            # only steam.package set (no injection, no extraPkgs) the explicit
            # package is used verbatim.
            package =
              if injectionEnabled || steamCfg.extraPkgs != [ ] then
                steamBase.override (
                  {
                    extraPkgs = extraPkgsFn;
                  }
                  // lib.optionalAttrs (injectEnv != { }) { extraEnv = injectEnv; }
                )
              else
                steamCfg.package;
          })
        ];
      };
    };
}
