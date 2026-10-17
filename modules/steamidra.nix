# SteaMidra (SFF) feature. Unit shape: flake.nix takes `.module` (home module)
# and `.mkSteamidra` (packages.steamidra) — same launcher both places.
{ steamidra }:
rec {
  # Newest tag from the pinned /tags JSON (GitHub lists tags newest-first).
  # Re-lock with `nix flake update` to track a new release. Strip a leading
  # "v" with builtins (no pkgs.lib needed).
  steamidraVersion =
    let
      name = (builtins.head (builtins.fromJSON (builtins.readFile steamidra))).name;
    in
    if builtins.substring 0 1 name == "v" then
      builtins.substring 1 (builtins.stringLength name) name
    else
      name;

  # The 520 MiB AppImage is NOT fetched by Nix: SFF has no versionless asset
  # URL, so a Nix fetch would need a hand-bumped SRI hash for every release.
  # The launcher downloads exactly the locked version on first run. Uses $HOME
  # so the package works imperatively; the home module's desktop entry points
  # its Icon= at the absolute path from config.home.homeDirectory.
  mkSteamidra =
    pkgs:
    let
      dataDir = "$HOME/.local/share/SteaMidra";
    in
    pkgs.writeShellScriptBin "steamidra" ''
      set -euo pipefail
      app="${dataDir}/SteaMidra.AppImage"

      if [ "$(cat "${dataDir}/.version" 2>/dev/null || true)" != "${steamidraVersion}" ]; then
        ${pkgs.libnotify}/bin/notify-send -a SteaMidra \
          "Downloading SteaMidra ${steamidraVersion}" "About 520 MiB, this takes a while." || true
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        ${pkgs.curl}/bin/curl -fL --progress-bar -o "$tmp/sff.zip" \
          "https://github.com/Midrags/SFF/releases/download/v${steamidraVersion}/SteaMidra-${steamidraVersion}-linux.zip"
        ${pkgs.unzip}/bin/unzip -qo "$tmp/sff.zip" "SteaMidra*.AppImage" "*.png" -d "$tmp"
        mkdir -p "${dataDir}"
        mv "$tmp"/SteaMidra*.AppImage "$app"
        chmod +x "$app"
        mv "$tmp"/*.png "${dataDir}/steamidra.png"
        echo "${steamidraVersion}" > "${dataDir}/.version"
        ${pkgs.libnotify}/bin/notify-send -a SteaMidra "SteaMidra ${steamidraVersion} ready" || true
      fi

      export APPIMAGE="$app"
      export QTWEBENGINE_DISABLE_SANDBOX=1
      exec ${pkgs.appimage-run}/bin/appimage-run "$app" "$@"
    '';

  module =
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

      steamidraLauncher = mkSteamidra pkgs;

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
    };
}
