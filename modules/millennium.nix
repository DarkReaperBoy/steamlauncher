{ millennium, mkMillennium }:
{
  config,
  lib,
  ...
}:
{
  options.programs.nix-crab.millennium.enable = lib.mkEnableOption "Enable millennium";

  config = lib.mkIf config.programs.nix-crab.millennium.enable {
    # Two overlays, in order:
    #   1. Millennium's own — it defines `millennium` and `millennium-steam`
    #      against the final package set and wires programs.steam itself (env,
    #      libraries, the bootstrap libXtst symlinks). We deliberately do NOT
    #      remap pkgs.steam = millennium-steam here (the previous approach) —
    #      Millennium's overlay resolves steam.nix's `steam` argument from the
    #      final set, so remapping would recurse. slssteam.nix picks
    #      millennium-steam as the override base when this option is on.
    #   2. ours — the same overlay, with `millennium` replaced by the project's
    #      own release binaries. `millennium-steam` is defined in terms of
    #      `final.millennium`, so it picks the swap up automatically and every
    #      bit of upstream's wiring stays untouched. This turns a ~7 minute
    #      cmake/bun/TypeScript build into a download.
    nixpkgs.overlays = [
      millennium.overlays.default
      (final: _prev: {
        millennium = mkMillennium final;
      })
    ];
  };
}
