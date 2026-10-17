{
  description = "Declarative Steam tooling for NixOS: SLSsteam injection, Millennium, LuaTools, steam-config-nix, ACCELA, SteaMidra (nix-crab, updated continuation)";

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
    # maintained path for the LuaTools workflow). Its GitHub release ships the
    # injected objects, so it is fetched, not built — see
    # modules/upstream-binaries.nix and upstream.lock.json.

    # Lumen (static Lua backend) + the LuaTools plugin port, both from the
    # slsteam-moon maintainer. Also release binaries, same mechanism.

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

    # Home Manager — an implementation detail, not something the user manages.
    # The NixOS module imports it and drives home-manager.users.<user> from
    # plain programs.nix-crab.* options, so everything applies in one
    # `nixos-rebuild switch`.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # steam-config-nix — declarative Steam configuration (launch options,
    # compat tools, game files, non-Steam apps, ...). Its modules are
    # re-exported by nixosModules.default / homeModules.default below, so the
    # whole surface is `programs.steam.config.*`, gated on its own
    # `programs.steam.config.enable` (default off, like everything else here).
    steam-config-nix = {
      url = "github:different-name/steam-config-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
      steamnetsock,
      steamidra,
      millennium,
      home-manager,
      steam-config-nix,
      enter-the-wired,
    }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # Feature units: each modules/<feature>.nix returns
      # `{ inputs }: { module, mk* }` — instantiate ONCE here, then take
      # `.module` for the module outputs and `.mk*` for packages.*. One
      # definition per derivation, so a package and the option that installs it
      # are always bit-identical. (Files that own no derivations —
      # settings.nix, millennium*.nix — are plain modules, imported where
      # used.)
      slssteamUnit = import ./modules/slssteam.nix {
        inherit sls-steam;
        inherit (upstreamBinaries) mkSlsteamMoon;
      };
      downgradeUnit = import ./modules/downgrade.nix { };
      accelaUnit = import ./modules/accela.nix { inherit enter-the-wired; };
      steamidraUnit = import ./modules/steamidra.nix { inherit steamidra; };
      luatoolsUnit = import ./modules/luatools-moon.nix {
        inherit (upstreamBinaries) mkLumen mkLuatools;
      };
      toolsUnit = import ./modules/tools.nix { };
      homeUnit = import ./modules/home.nix {
        inherit steamnetsock sls-steam;
        inherit (upstreamBinaries) mkSlsteamMoon;
      };

      # Upstream release binaries (Millennium, slsteam-moon, Lumen, LuaTools):
      # fetched from each project's own GitHub Releases, versioned by
      # upstream.lock.json — a generated file, refreshed daily by
      # ci/update-binaries.sh. Nothing here is compiled.
      upstreamBinaries = import ./modules/upstream-binaries.nix { };

      # The home-side config modules, in one place: homeModules.default imports
      # them for standalone Home Manager, nixosModules.default forwards them
      # into home-manager.users.<user>. Options are declared once, in
      # home-options.nix, and imported on both sides separately.
      homeConfigModules = [
        homeUnit.module
        ./modules/millennium-addons.nix
        toolsUnit.module
        luatoolsUnit.module
        steamidraUnit.module
        accelaUnit.module
      ];

      # No package output is unfree — SLSsteam is AGPL-3.0 and injection happens
      # through the module option on the consumer's own pkgs, where Steam's
      # unfree license is handled.
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
          slsteam-moon = upstreamBinaries.mkSlsteamMoon pkgs; # the LuaTools fork (its own release)
          netsock = homeUnit.mkNetsock pkgs; # multiplayer-fix .so (per-game LD_AUDIT)
          steamidra = steamidraUnit.mkSteamidra pkgs; # SteaMidra (SFF) launcher
          lumen = upstreamBinaries.mkLumen pkgs; # LuaTools backend dist
          luatools = upstreamBinaries.mkLuatools pkgs; # LuaTools plugin dist
          millennium = upstreamBinaries.mkMillennium pkgs; # Millennium hook (its own release)
          ticket-grabber = slssteamUnit.mkTicketGrabber pkgs; # SLSsteam tool
          schema-grabber = slssteamUnit.mkSchemaGrabber pkgs; # SLSsteam tool
          steam-config-patcher = steam-config-nix.packages.${system}.steam-config-patcher; # steam-config-nix's patcher

          # this flake's own commands
          nix-crab-status = toolsUnit.mkStatus pkgs; # diagnostics, --json for machines
          nix-crab-update = toolsUnit.mkUpdate pkgs; # flake update + rebuild + status
          nix-crab-downgrade = downgradeUnit.mkDowngrade pkgs; # pin the Steam client

          default = accela;
        }
      );

      # ------------------------------------------------------------------
      # Modules: opt-in, everything defaults to off. Import the module, then
      # flip programs.nix-crab.*.enable for the software you want. The
      # steam-config-nix modules are re-exported here (their own gate is
      # programs.steam.config.enable, also off by default) so one import gets
      # the whole surface.
      # ------------------------------------------------------------------
      nixosModules.default = {
        imports = [
          steam-config-nix.nixosModules.default
          home-manager.nixosModules.home-manager
          ./modules/home-options.nix
          ./modules/netsock-bridge.nix
          (import ./modules/nixos-home.nix { inherit homeConfigModules; })
          (import ./modules/millennium.nix {
            inherit millennium;
            inherit (upstreamBinaries) mkMillennium;
          })
          slssteamUnit.module
          downgradeUnit.module
        ];
      };

      homeModules.default = {
        imports = [
          steam-config-nix.homeModules.default
          ./modules/home-options.nix
          ./modules/steam-config.nix
          ./modules/netsock-bridge.nix
        ]
        ++ homeConfigModules;
      };

      # `nix fmt`
      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);
    };
}
