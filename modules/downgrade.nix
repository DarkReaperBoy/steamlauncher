{ crabLib }:
{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.programs.nix-crab.downgrade = {
    enable = lib.mkEnableOption "nix-crab client downgrade";
    package = lib.mkOption {
      type = lib.types.package;
      default = crabLib.mkDowngrade pkgs;
      description = "The nix-crab-downgrade wrapper script";
    };
  };

  config = lib.mkIf config.programs.nix-crab.downgrade.enable {
    environment.systemPackages = [ config.programs.nix-crab.downgrade.package ];
  };
}
