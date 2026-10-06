{ millennium }:
{
  config,
  lib,
  ...
}:
{
  options.programs.nix-crab.millennium.enable = lib.mkEnableOption "Enable millennium";

  config = lib.mkIf config.programs.nix-crab.millennium.enable {
    # Only Millennium's own overlay: it defines `millennium` and
    # `millennium-steam` against the final package set. We deliberately do NOT
    # remap pkgs.steam = millennium-steam here (the previous approach) —
    # Millennium's overlay now resolves steam.nix's `steam` argument from the
    # final set, so remapping would recurse. slssteam.nix picks
    # millennium-steam as the override base when this option is on.
    nixpkgs.overlays = [ millennium.overlays.default ];
  };
}
