# SLSsteam feature: upstream injection + the slsteam-moon fork, plus the
# SLSsteam tool binaries. Unit shape: `{ inputs }: rec { builders; module; }` —
# flake.nix instantiates this once and takes `.module` (NixOS module output)
# and `.mk*` (packages.* outputs), so a package and the option that installs
# it are always the same derivation.
{ sls-steam, slsteam-moon }:
rec {
  # Upstream SLSsteam artefacts (SLSsteam.so + library-inject.so), same as the
  # official wiki's NixOS instructions use.
  mkSlsSteam = pkgs: sls-steam.packages.${pkgs.stdenv.hostPlatform.system}.sls-steam;
  mkTicketGrabber = pkgs: sls-steam.packages.${pkgs.stdenv.hostPlatform.system}.ticket-grabber;
  mkSchemaGrabber = pkgs: sls-steam.packages.${pkgs.stdenv.hostPlatform.system}.schema-grabber;

  # slsteam-moon: fork with a native Lua manifest importer. No flake, so it is
  # built from source with the same 32-bit toolchain upstream uses in its own
  # nix-modules/default.nix.
  mkSlsteamMoon =
    pkgs:
    pkgs.pkgsi686Linux.stdenv.mkDerivation {
      pname = "slsteam-moon";
      version = "0.0.0";
      src = slsteam-moon;
      nativeBuildInputs = with pkgs; [ pkg-config ];
      buildInputs = with pkgs.pkgsi686Linux; [
        openssl
        curl
      ];
      # slsteam-moon's headers (utils.hpp, patterns.hpp, memhlp.hpp, hooks.hpp)
      # use uint*_t without including <cstdint>, relying on transitive includes
      # that GCC 14+ removed. Force-include it for every TU instead of patching
      # each header — also covers any future missing-include rot.
      env.NIX_CFLAGS_COMPILE = "-include cstdint";
      # pattern-refresh is a native host helper we don't need; only the two
      # Steam-loaded i386 objects are injected.
      buildPhase = "make bin/SLSsteam.so bin/library-inject.so";
      # -O3 -flto over ~100 translation units; the Makefile only marks `clean`
      # and `rebuild` as .NOTPARALLEL, so the object targets take -j fine.
      enableParallelBuilding = true;
      # embed-version.sh / embed-config.sh are invoked by the Makefile and
      # carry a #!/bin/bash shebang that doesn't exist in the sandbox.
      postPatch = ''
        patchShebangs embed-version.sh embed-config.sh
      '';
      installPhase = ''
        mkdir -p "$out"
        cp bin/SLSsteam.so "$out/"
        cp bin/library-inject.so "$out/"
      '';
      meta = {
        description = "SLSsteam fork with a Lua manifest importer (slsteam-moon)";
        homepage = "https://github.com/swwayps/slsteam-moon";
        license = pkgs.lib.licenses.agpl3Only;
        platforms = pkgs.lib.platforms.linux;
      };
    };

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

      # Base package the LD_AUDIT wrapper is built from. With Millennium enabled
      # its overlay provides millennium-steam — a `steam.override` of its own
      # steam.nix — so re-overriding here re-enters *that* function and its
      # `extraEnv // millenniumEnv` merge keeps MILLENNIUM_RUNTIME_PATH alongside
      # LD_AUDIT. (Remapping pkgs.steam to millennium-steam instead would recurse
      # now that Millennium's overlay resolves its `steam` argument from the final
      # package set.)
      steamBase = if cfg.millennium.enable then pkgs.millennium-steam else pkgs.steam;
    in
    {
      options.programs.nix-crab = {
        slssteam.enable = lib.mkEnableOption "SLSsteam (upstream) injection into Steam";

        slssteam.extraEnv = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Additional environment variables injected into Steam";
        };

        slssteam-moon.enable = lib.mkEnableOption ''
          slsteam-moon (SLSsteam fork with a Lua manifest importer) instead of
          upstream SLSsteam. Takes precedence over slssteam.enable; required by
          the home module's luatools option. Built from source (32-bit compile).
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
            # LD_PRELOAD only lands in the steam override when one of the three
            # base-package options below is on; otherwise CloudRedirect would
            # enable its Flatpak and do nothing.
            assertion = !cfg.cloudredirect.enable || (injectionEnabled || cfg.millennium.enable);
            message = ''
              programs.nix-crab.cloudredirect.enable needs an injection to attach to:
              enable slssteam, slssteam-moon or millennium as well.
            '';
          }
        ];

        programs.steam = lib.mkIf (injectionEnabled || cfg.millennium.enable) {
          enable = true;
          package = steamBase.override {
            extraEnv =
              lib.optionalAttrs injectionEnabled {
                LD_AUDIT = "${sls}/library-inject.so:${sls}/SLSsteam.so";
              }
              // cfg.slssteam.extraEnv;
          };
        };
      };
    };
}
