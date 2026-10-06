{
  description = "nix-crab (updated): SLSsteam, CloudRedirect, Millennium and LuaTools as NixOS and home-manager modules, plus dev shells";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # SLSsteam upstream — the .so packages AND res/config.yaml, whose defaults
    # are merged under programs.nix-crab.slssteam.settings (see modules/home.nix).
    sls-steam = {
      url = "github:AceSLS/SLSsteam";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # slsteam-moon: SLSsteam fork with a native Lua manifest importer (the
    # maintained path for the LuaTools workflow). No flake, so it is built from
    # source in modules/slssteam.nix instead of imported as a package set.
    # Its res/config.yaml is the merge base when slssteam-moon is enabled.
    slsteam-moon = {
      url = "github:swwayps/slsteam-moon";
      flake = false;
    };

    # Lumen (static Lua backend) + the LuaTools plugin port, both from the
    # slsteam-moon maintainer. Pinned by git rev, not versionless release URLs
    # (those change content every release and break the lock's narHash).
    lumen = {
      url = "github:swwayps/lumen";
      flake = false;
    };
    luatools-moon = {
      url = "github:swwayps/luatools-moon";
      flake = false;
    };

    # Upstream CloudRedirect hook — the default. Reads the game list from
    # config.yaml's AdditionalApps.
    cloudredirect = {
      type = "file";
      url = "https://github.com/Selectively11/CloudRedirect/releases/latest/download/cloud_redirect.so";
      flake = false;
    };
    # Optional hook for the LuaTools stack, opt-in via
    # programs.nix-crab.cloudredirect.moon. Additionally scans stplug-in +
    # luaappids.yaml; the .so is committed at the repo root.
    cloudredirect-moon = {
      url = "github:swwayps/cloudredirect-moon";
      flake = false;
    };
    cloudredirect-cli = {
      type = "file";
      url = "https://github.com/Selectively11/h3adcr-b/releases/download/linux-test/cloud_redirect_cli";
      flake = false;
    };

    # netsock (steamnetsock-patch) — per-game LD_AUDIT multiplayer fix.
    steamnetsock = {
      type = "file";
      url = "https://github.com/yesyes0649/steamnetsock-patch/releases/latest/download/fix.so";
      flake = false;
    };

    # SteaMidra (SFF). Tag list, not releases/latest: that JSON embeds
    # per-asset download counters, so its narHash changes within the hour and
    # every eval after the tarball TTL dies with a narHash mismatch. /tags only
    # changes when a new tag is pushed; `nix flake update` follows releases.
    steamidra = {
      type = "file";
      url = "https://api.github.com/repos/Midrags/SFF/tags";
      flake = false;
    };

    millennium.url = "github:SteamClientHomebrew/Millennium?dir=packages/nix";
    millennium.inputs.nixpkgs.follows = "nixpkgs";

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    # ACCELA (Enter The Wired bundle) — AppImage packaged as a proper
    # appimageTools FHS wrapper. Also used by the devShell/packages outputs.
    enter-the-wired = {
      url = "github:ciscosweater/enter-the-wired";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      sls-steam,
      slsteam-moon,
      lumen,
      luatools-moon,
      cloudredirect,
      cloudredirect-moon,
      cloudredirect-cli,
      steamnetsock,
      steamidra,
      millennium,
      nix-flatpak,
      enter-the-wired,
    }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # ACCELA's AppImage bundles its own Qt (PyQt6 + Qt 6.11.0). When launched
      # from a KDE/Qt session, QT_PLUGIN_PATH leaks nixpkgs Qt plugin dirs into
      # the bwrap sandbox; Qt then loads version-mismatched plugins
      # (private-ABI symbol errors) and dies. Fix: clean Qt env at launch.
      mkAccela =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          accela = enter-the-wired.packages.${system}.default;
        in
        pkgs.runCommand "accela" {
          nativeBuildInputs = [ pkgs.makeWrapper ];
        } ''
          mkdir -p $out/bin
          makeWrapper ${accela}/bin/accela $out/bin/accela \
            --unset QT_PLUGIN_PATH \
            --unset QT_QPA_PLATFORM_PLUGIN_PATH \
            --unset QTWEBKIT_PLUGIN_PATH \
            --unset QML2_IMPORT_PATH
        '';

      # Standalone steam with SLSsteam LD_AUDIT for imperative/dev use —
      # the same injection modules/slssteam.nix wires into programs.steam.
      mkSteamSLS =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate =
              pkg:
              builtins.elem (nixpkgs.lib.getName pkg) [
                "steam"
                "steam-unwrapped"
              ];
          };
          slsSo = sls-steam.packages.${system}.sls-steam;
          steamSLS = pkgs.steam.override {
            extraEnv = {
              LD_AUDIT = "${slsSo}/library-inject.so:${slsSo}/SLSsteam.so";
            };
          };
        in
        # single package providing both command names
        pkgs.runCommand "SLSsteam" { } ''
          mkdir -p $out/bin
          ln -s ${steamSLS}/bin/steam $out/bin/SLSsteam
          ln -s ${steamSLS}/bin/steam $out/bin/steam
        '';
    in
    {
      nixosModules.default = {
        imports = [
          (import ./modules/millennium.nix { inherit millennium; })
          (import ./modules/cloudredirect.nix { inherit cloudredirect cloudredirect-moon; })
          (import ./modules/slssteam.nix {
            inherit
              sls-steam
              slsteam-moon
            ;
          })
          ./modules/downgrade.nix
        ];
      };

      homeModules.default = {
        imports = [
          (import ./modules/home.nix {
            inherit
              sls-steam
              slsteam-moon
              nix-flatpak
              steamnetsock
              cloudredirect
              cloudredirect-moon
              cloudredirect-cli
              ;
          })
          ./modules/millennium-addons.nix
          (import ./modules/luatools-moon.nix { inherit lumen luatools-moon; })
          (import ./modules/steamidra.nix { inherit steamidra; })
          (import ./modules/accela.nix { inherit enter-the-wired; })
        ];
      };

      # Imperative/dev outputs (the original steam-launcher flake's shell).
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate =
              pkg:
              builtins.elem (nixpkgs.lib.getName pkg) [
                "steam"
                "steam-unwrapped"
              ];
          };
          sls = sls-steam.packages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              (mkAccela system) # ACCELA (enter-the-wired), clean-Qt-env launcher
              (mkSteamSLS system) # steam with SLSsteam LD_AUDIT
              sls.sls-steam # SLSsteam.so / library-inject.so
              sls.ticket-grabber
              sls.schema-grabber
            ];

            shellHook = ''
              # keep Qt-session plugin pollution out of the sandboxed AppImage
              unset QT_PLUGIN_PATH QT_QPA_PLATFORM_PLUGIN_PATH QTWEBKIT_PLUGIN_PATH QML2_IMPORT_PATH

              echo "--- steam-launcher / nix-crab shell ---"
              echo "  accela         : ACCELA (enter-the-wired)"
              echo "  steam/SLSsteam : Steam client with SLSsteam injection"
              echo "  ticket-grabber : SLSsteam ticket grabber"
              echo "  schema-grabber : SLSsteam schema grabber"
            '';
          };
        }
      );

      # standalone packages, for `nix build .#accela` etc.
      packages = forAllSystems (
        system: rec {
          accela = mkAccela system;
          SLSsteam = mkSteamSLS system;
          default = accela;
        }
      );
    };
}
