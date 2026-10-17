# steam-config-nix under the nix-crab umbrella.
#
# Upstream's option surface is `programs.steam.config.*` (it targets both
# NixOS and Home Manager, and this flake re-exports its modules unchanged) —
# this module only forwards the same path under programs.nix-crab so that
# everything a user touches in this flake lives in one namespace. Definitions
# here are forwarded verbatim; the real value — and upstream's type checking —
# stays at programs.steam.config, so upstream docs apply 1:1.
{ lib, config, ... }:
{
  options.programs.nix-crab.steam.config = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = { };
    example = {
      enable = true;
      apps."438100" = {
        name = "VRChat";
        args = [ "--fps=60" ];
      };
    };
    description = ''
      Alias of {option}`programs.steam.config` (steam-config-nix). Anything
      written here is forwarded to it, so the whole per-game configuration
      surface — launch options, compat tools, prefixes, game files, artwork,
      non-Steam apps — is reachable from one namespace.
    '';
  };

  config = lib.mkIf (config.programs.nix-crab.steam.config != { }) {
    programs.steam.config = config.programs.nix-crab.steam.config;
  };
}
