{
  enter-the-wired,
}: {
  pkgs,
  lib,
  config,
  ...
}: let
  system = pkgs.stdenv.hostPlatform.system;

  accelaPkg = enter-the-wired.packages.${system}.default;

  # ACCELA's AppImage bundles its own Qt (PyQt6 + Qt 6.11.0). When launched
  # from a KDE/Qt session, QT_PLUGIN_PATH leaks nixpkgs Qt plugin dirs into
  # the bwrap sandbox; Qt then loads version-mismatched plugins
  # (private-ABI symbol errors) and dies. Fix: run accela with a clean Qt
  # environment. zstd/icu are already in the package's extraPkgs.
  launcher = pkgs.runCommand "accela" {
    nativeBuildInputs = [pkgs.makeWrapper];
  } ''
    mkdir -p $out/bin
    makeWrapper ${accelaPkg}/bin/accela $out/bin/accela \
      --unset QT_PLUGIN_PATH \
      --unset QT_QPA_PLATFORM_PLUGIN_PATH \
      --unset QTWEBKIT_PLUGIN_PATH \
      --unset QML2_IMPORT_PATH
  '';

  desktopItem = pkgs.makeDesktopItem {
    name = "accela";
    desktopName = "ACCELA";
    comment = "ＧｏＤ_Ｉｓ_ｉＮ_ｔＨｅ_ＷｉＲｅＤ";
    exec = "${launcher}/bin/accela %u";
    icon = "accela";
    categories = ["Utility"];
    # Declared, not registered as default: that would mean owning
    # ~/.config/mimeapps.list via xdg.mimeApps and every other default with it.
    mimeTypes = ["x-scheme-handler/accela"];
    startupNotify = false;
  };

  # The [General] keys enter-the-wired's own `accela` script forces — what makes
  # ACCELA defer to SLSsteam instead of managing games itself.
  seedConf = pkgs.writeText "ACCELA.conf" ''
    [General]
    auto_skip_single_choice=true
    library_mode=true
    max_downloads=16
    sls_config_management=true
    slssteam_mode=true
    use_steamless=true
  '';
in {
  options.programs.nix-crab.accela.enable =
    lib.mkEnableOption "ACCELA (Steam depot downloader, Enter The Wired)";

  config = lib.mkIf config.programs.nix-crab.accela.enable {
    home.packages = [launcher];

    home.file.".local/share/icons/hicolor/256x256/apps/accela.png".source =
      "${accelaPkg}/share/pixmaps/accela.png";

    # Not xdg.desktopEntries: XDG_DATA_HOME is searched before the profile, so
    # the entry ACCELAINSTALL writes would shadow ours. Same as steamidra.
    home.file.".local/share/applications/accela.desktop" = {
      source = "${desktopItem}/share/applications/accela.desktop";
      force = true;
    };

    # Seeded, not managed: QSettings rewrites this file, so a store symlink
    # breaks it. Same reason slssteam.manageConfig defaults to false.
    # Seeds only when absent; upstream awk-merges into an existing section.
    home.activation.accelaSeedConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      accelaConf="${config.xdg.configHome}/Tachibana Labs/ACCELA.conf"
      if [ ! -e "$accelaConf" ]; then
        run mkdir -p "$(dirname "$accelaConf")"
        run install -m 644 ${seedConf} "$accelaConf"
      fi
    '';
  };
}
