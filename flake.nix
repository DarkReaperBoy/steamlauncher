{
  description = "Steam tools for NixOS as packages + opt-in modules: SLSsteam, CloudRedirect, Millennium, LuaTools, ACCELA, SteaMidra (updated continuation of nix-crab)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # SLSsteam upstream — the .so packages AND res/config.yaml, whose keys are
    # mirrored as typed options in modules/settings.nix.
    # Tracks upstream HEAD on `nix flake update`.
    sls-steam = {
      url = "github:AceSLS/SLSsteam";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # slsteam-moon: SLSsteam fork with a native Lua manifest importer (the
    # maintained path for the LuaTools workflow). No flake, so it is built from
    # source in lib.nix instead of imported as a package set. Its
    # res/config.yaml is the merge base when slssteam-moon is enabled.
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

    # Upstream CloudRedirect hook — the default. `releases/latest/download`
    # means `nix flake update` always picks the newest release (currently
    # v2.6.6). Reads the game list from config.yaml's AdditionalApps.
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
    # `releases/latest/download` tracks upstream automatically.
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
    # appimageTools FHS wrapper with the Qt deps ACCELA needs.
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

      # One shared builder set: every package output and every module option
      # resolves to the same derivations through this.
      crabLib = import ./lib.nix {
        inherit
          sls-steam
          slsteam-moon
          enter-the-wired
          cloudredirect
          cloudredirect-moon
          cloudredirect-cli
          steamnetsock
          steamidra
          lumen
          luatools-moon
          ;
      };

      # Steam is unfree; only the packages that actually need it pay for it.
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate =
            pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [
              "steam"
              "steam-unwrapped"
            ];
        };
    in
    {
      # ------------------------------------------------------------------
      # Packages: everything this flake can install, buildable with
      # `nix build .#<name>` / `nix profile install .#<name>` and (for the
      # command ones) runnable with `nix run .#<name>`. Nothing here is
      # installed unless you ask for it.
      # ------------------------------------------------------------------
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        rec {
          # software
          accela = crabLib.mkAccela pkgs; # ACCELA depot downloader (clean-Qt launcher)
          SLSsteam = crabLib.mkSteamSLS pkgs; # steam with SLSsteam LD_AUDIT built in
          sls-steam = crabLib.mkSlsSteam pkgs; # SLSsteam.so + library-inject.so (upstream)
          slsteam-moon = crabLib.mkSlsteamMoon pkgs; # the LuaTools fork, built from source
          cloudredirect = crabLib.mkCloudredirect pkgs; # upstream cloud_redirect.so
          cloudredirect-moon = crabLib.mkCloudredirectMoon pkgs; # LuaTools hook
          cloudredirect-cli = crabLib.mkCloudredirectCli pkgs; # cloud_redirect_cli
          netsock = crabLib.mkNetsock pkgs; # multiplayer-fix .so (per-game LD_AUDIT)
          steamidra = crabLib.mkSteamidra pkgs; # SteaMidra (SFF) launcher
          lumen = crabLib.mkLumen pkgs; # LuaTools backend dist
          luatools = crabLib.mkLuatools pkgs; # LuaTools plugin dist
          ticket-grabber = crabLib.mkTicketGrabber pkgs; # SLSsteam tool
          schema-grabber = crabLib.mkSchemaGrabber pkgs; # SLSsteam tool

          # this flake's own commands
          nix-crab-status = crabLib.mkStatus pkgs; # diagnostics, --json for machines
          nix-crab-update = crabLib.mkUpdate pkgs; # flake update + rebuild + status
          nix-crab-downgrade = crabLib.mkDowngrade pkgs; # pin the Steam client

          default = accela;
        }
      );

      # ------------------------------------------------------------------
      # Modules: opt-in, everything defaults to off. Import the module, then
      # flip programs.nix-crab.*.enable for the software you want.
      # ------------------------------------------------------------------
      nixosModules.default = {
        imports = [
          (import ./modules/millennium.nix { inherit millennium; })
          (import ./modules/cloudredirect.nix { inherit cloudredirect cloudredirect-moon; })
          (import ./modules/slssteam.nix { inherit crabLib; })
          (import ./modules/downgrade.nix { inherit crabLib; })
        ];
      };

      homeModules.default = {
        imports = [
          (import ./modules/home.nix {
            inherit
              crabLib
              nix-flatpak
              steamnetsock
              cloudredirect
              cloudredirect-moon
              sls-steam
              slsteam-moon
              ;
          })
          ./modules/millennium-addons.nix
          (import ./modules/luatools-moon.nix { inherit crabLib; })
          (import ./modules/steamidra.nix { inherit crabLib; })
          (import ./modules/accela.nix { inherit crabLib; })
        ];
      };

      # `nix fmt`
      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);
    };
}
