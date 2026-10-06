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
    # source in modules/slssteam.nix instead of imported as a package set. Its
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

      # Feature units: each modules/<feature>.nix returns
      # `{ module, mk* }` — instantiate ONCE here, then take `.module` for the
      # module outputs and `.mk*` for packages.*. One definition per
      # derivation, so a package and the option that installs it are always
      # bit-identical. (Files that own no derivations — settings.nix,
      # millennium*.nix — are plain modules, imported where used.)
      slssteamUnit = import ./modules/slssteam.nix { inherit sls-steam slsteam-moon; };
      cloudredirectUnit = import ./modules/cloudredirect.nix {
        inherit
          cloudredirect
          cloudredirect-moon
          cloudredirect-cli
          ;
      };
      downgradeUnit = import ./modules/downgrade.nix { };
      accelaUnit = import ./modules/accela.nix { inherit enter-the-wired; };
      steamidraUnit = import ./modules/steamidra.nix { inherit steamidra; };
      luatoolsUnit = import ./modules/luatools-moon.nix { inherit lumen luatools-moon; };
      toolsUnit = import ./modules/tools.nix { inherit cloudredirect cloudredirect-moon; };
      homeUnit = import ./modules/home.nix {
        inherit
          nix-flatpak
          steamnetsock
          cloudredirect
          cloudredirect-moon
          cloudredirect-cli
          sls-steam
          slsteam-moon
          ;
      };

      # No package output is unfree — the old SLSsteam steam-wrapper was the
      # only unfree one and is gone (injection happens via the module option
      # on the consumer's own pkgs, where steam's unfree license is handled).
      pkgsFor = system: import nixpkgs { inherit system; };
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
          accela = accelaUnit.mkAccela pkgs; # ACCELA depot downloader (clean-Qt launcher)
          sls-steam = slssteamUnit.mkSlsSteam pkgs; # SLSsteam.so + library-inject.so (upstream)
          slsteam-moon = slssteamUnit.mkSlsteamMoon pkgs; # the LuaTools fork, built from source
          cloudredirect = cloudredirectUnit.mkCloudredirect pkgs; # upstream cloud_redirect.so
          cloudredirect-moon = cloudredirectUnit.mkCloudredirectMoon pkgs; # LuaTools hook
          cloudredirect-cli = cloudredirectUnit.mkCloudredirectCli pkgs; # cloud_redirect_cli
          netsock = homeUnit.mkNetsock pkgs; # multiplayer-fix .so (per-game LD_AUDIT)
          steamidra = steamidraUnit.mkSteamidra pkgs; # SteaMidra (SFF) launcher
          lumen = luatoolsUnit.mkLumen pkgs; # LuaTools backend dist
          luatools = luatoolsUnit.mkLuatools pkgs; # LuaTools plugin dist
          ticket-grabber = slssteamUnit.mkTicketGrabber pkgs; # SLSsteam tool
          schema-grabber = slssteamUnit.mkSchemaGrabber pkgs; # SLSsteam tool

          # this flake's own commands
          nix-crab-status = toolsUnit.mkStatus pkgs; # diagnostics, --json for machines
          nix-crab-update = toolsUnit.mkUpdate pkgs; # flake update + rebuild + status
          nix-crab-downgrade = downgradeUnit.mkDowngrade pkgs; # pin the Steam client

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
          cloudredirectUnit.module
          slssteamUnit.module
          downgradeUnit.module
        ];
      };

      homeModules.default = {
        imports = [
          homeUnit.module
          ./modules/millennium-addons.nix
          toolsUnit.module
          luatoolsUnit.module
          steamidraUnit.module
          accelaUnit.module
        ];
      };

      # `nix fmt`
      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);
    };
}
