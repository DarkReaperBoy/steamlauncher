{ crabLib }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nix-crab;

  upstream = crabLib.mkSlsSteam pkgs;

  # Both forks ship the same two artefacts under the same names (SLSsteam.so +
  # library-inject.so), so the choice is one store path, not two branches of
  # wiring. slsteam-moon is built from source — see lib.nix for the toolchain
  # and the GCC <cstdint> workaround.
  sls = if cfg.slssteam-moon.enable then crabLib.mkSlsteamMoon pkgs else upstream;

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
}
