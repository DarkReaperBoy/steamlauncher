# steam-config-nix under the nix-crab umbrella.
#
# The option itself lives in slssteam.nix's `programs.nix-crab.steam`
# submodule (`steam.config`, typed attrsOf anything); this module only
# forwards it to upstream's real namespace. The value — and the type checking
# — stays at programs.steam.config, so upstream docs apply 1:1.
{ lib, config, ... }:
{
  config = lib.mkIf (config.programs.nix-crab.steam.config != { }) {
    programs.steam.config = config.programs.nix-crab.steam.config;
  };
}
