# netsock.games -> steam-config-nix launch options.
#
# Imported on BOTH module paths (nixosModules.default and homeModules.default),
# because that is exactly where steam-config-nix lives on each side. It is
# deliberately NOT part of the home config modules the NixOS path forwards
# into home-manager.users.<user>: steam-config-nix must run once, on the side
# that owns it, or the patcher service and the wrapper links would exist
# twice.
{ config, lib, ... }:
let
  cfg = config.programs.nix-crab;
in
{
  config = lib.mkIf (cfg.netsock.games != [ ]) {
    assertions = [
      {
        assertion = cfg.netsock.enable;
        message = ''
          programs.nix-crab.netsock.games needs programs.nix-crab.netsock.enable = true,
          otherwise there is no netsock.so for the launch option to point at.
        '';
      }
      {
        assertion = cfg.steam.config.enable or false;
        message = ''
          programs.nix-crab.netsock.games is written through steam-config-nix:
          set programs.nix-crab.steam.config.enable = true (Steam itself is
          enabled by programs.nix-crab.slssteam.enable), or declare the launch
          option yourself under programs.nix-crab.steam.config.apps.<id>.
        '';
      }
    ];

    programs.steam.config.apps = lib.genAttrs (map toString cfg.netsock.games) (_: {
      env.LD_AUDIT = "$HOME/.config/SLSsteam/tools/netsock/netsock.so";
    });
  };
}
