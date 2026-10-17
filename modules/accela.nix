# ACCELA feature (Enter The Wired depot downloader). Unit shape: flake.nix
# takes `.module` (home module) and `.mkAccela` (packages.accela) — the same
# derivation both places.
{ enter-the-wired }:
rec {
  accelaPkg = pkgs: enter-the-wired.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # ACCELA's AppImage bundles its own Qt (PyQt6 + Qt 6.11.0). When launched
  # from a KDE/Qt session, QT_PLUGIN_PATH leaks nixpkgs Qt plugin dirs into
  # the bwrap sandbox; Qt then loads version-mismatched plugins
  # (private-ABI symbol errors) and dies. Fix: clean Qt env at launch.
  # zstd/icu/xcb-util-cursor are already in enter-the-wired's extraPkgs.
  mkAccela =
    pkgs:
    let
      accela = accelaPkg pkgs;
    in
    pkgs.runCommand "accela"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
        mkdir -p $out/bin
        makeWrapper ${accela}/bin/accela $out/bin/accela \
          --unset QT_PLUGIN_PATH \
          --unset QT_QPA_PLATFORM_PLUGIN_PATH \
          --unset QTWEBKIT_PLUGIN_PATH \
          --unset QML2_IMPORT_PATH
      '';

  module =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      # The Qt-clean wrapper (same bits as `nix build .#accela`).
      launcher = mkAccela pkgs;

      desktopItem = pkgs.makeDesktopItem {
        name = "accela";
        desktopName = "ACCELA";
        comment = "ＧｏＤ_Ｉｓ_ｉＮ_ｔＨｅ_ＷｉＲｅＤ";
        exec = "${launcher}/bin/accela %u";
        icon = "accela";
        categories = [ "Utility" ];
        # Declared, not registered as default: that would mean owning
        # ~/.config/mimeapps.list via xdg.mimeApps and every other default with it.
        mimeTypes = [ "x-scheme-handler/accela" ];
        startupNotify = false;
      };

      # The [General] keys enter-the-wired's own `accela` script forces — what makes
      # ACCELA defer to SLSsteam instead of managing games itself. Exposed as
      # options because upstream documents them as ACCELA.conf settings; the seed
      # only ever writes them when the file does not exist yet.
      seedConf = pkgs.writeText "ACCELA.conf" ''
        [General]
        auto_skip_single_choice=${lib.boolToString cfg.accela.config.auto_skip_single_choice}
        library_mode=${lib.boolToString cfg.accela.config.library_mode}
        max_downloads=${toString cfg.accela.config.max_downloads}
        sls_config_management=${lib.boolToString cfg.accela.config.sls_config_management}
        slssteam_mode=${lib.boolToString cfg.accela.config.slssteam_mode}
        use_steamless=${lib.boolToString cfg.accela.config.use_steamless}
      '';

      cfg = config.programs.nix-crab;
    in
    {
      config = lib.mkIf cfg.accela.enable {
        home.packages = [ launcher ];

        home.file.".local/share/icons/hicolor/256x256/apps/accela.png".source =
          "${accelaPkg pkgs}/share/pixmaps/accela.png";

        # Not xdg.desktopEntries: XDG_DATA_HOME is searched before the profile, so
        # the entry ACCELAINSTALL writes would shadow ours. Same as steamidra.
        home.file.".local/share/applications/accela.desktop" = {
          source = "${desktopItem}/share/applications/accela.desktop";
          force = true;
        };

        # Seeded, not managed: QSettings rewrites this file, so a store symlink
        # breaks it. Same reason slssteam.manageConfig defaults to false.
        # Seeds only when absent; upstream awk-merges into an existing section.
        home.activation.accelaSeedConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          accelaConf="${config.xdg.configHome}/Tachibana Labs/ACCELA.conf"
          if [ ! -e "$accelaConf" ]; then
            run mkdir -p "$(dirname "$accelaConf")"
            run install -m 644 ${seedConf} "$accelaConf"
          fi
        '';
      };
    };
}
