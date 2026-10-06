{ crabLib }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  # Absolute, not $HOME: this also lands in the .desktop Icon= path, which is
  # not shell-expanded. (The launcher itself uses $HOME so the package output
  # works imperatively too.)
  dataDir = "${config.home.homeDirectory}/.local/share/SteaMidra";

  steamidraLauncher = crabLib.mkSteamidra pkgs;

  desktopItem = pkgs.makeDesktopItem {
    name = "steamidra";
    desktopName = "SteaMidra";
    comment = "Steam game setup and manifest tool";
    exec = "${steamidraLauncher}/bin/steamidra";
    # Unpacked from the zip on first run, so missing until then.
    icon = "${dataDir}/steamidra.png";
    categories = [ "Utility" ];
    startupNotify = false;
  };
in
{
  options.programs.nix-crab.steamidra.enable = lib.mkEnableOption "SteaMidra (SFF) game downloader";

  config = lib.mkIf config.programs.nix-crab.steamidra.enable {
    home.packages = [
      pkgs.dotnetCorePackages.runtime_9_0
      steamidraLauncher
    ];

    # Not xdg.desktopEntries: that lands in the profile, and SteaMidra writes
    # its own ~/.local/share/applications/steamidra.desktop on startup with
    # Exec pointing at the raw AppImage — which cannot run on NixOS (no
    # libfuse2). XDG_DATA_HOME is searched before the profile, so that broken
    # entry would shadow ours. Own the path and force it back on every switch.
    home.file.".local/share/applications/steamidra.desktop" = {
      source = "${desktopItem}/share/applications/steamidra.desktop";
      force = true;
    };
  };
}
