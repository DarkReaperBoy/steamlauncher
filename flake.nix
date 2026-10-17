{
  description = "Declarative Steam tooling for NixOS: SLSsteam injection, Millennium, LuaTools, steam-config-nix, ACCELA, SteaMidra (nix-crab, updated continuation)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # SLSsteam upstream, slsteam-moon, Lumen, LuaTools and Millennium are all
    # consumed as their own GitHub release binaries — versions and hashes live
    # in upstream.lock.json, refreshed by ci/update-binaries.sh. Nothing is
    # compiled from source.

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

    # steam-config-nix — declarative Steam configuration (launch options,
    # compat tools, game files, non-Steam apps, ...). Its NixOS module is
    # re-exported by nixosModules.default below, so the whole surface is
    # reachable as programs.nix-crab.steam.config.* (forwards verbatim to
    # programs.steam.config), gated on its own `programs.steam.config.enable`
    # (default off, like everything else here).
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
      steamnetsock,
      steamidra,
      millennium,
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
        inherit (upstreamBinaries) mkSlsSteam mkSlsteamMoon;
      };
      downgradeUnit = import ./modules/downgrade.nix { };
      accelaUnit = import ./modules/accela.nix { inherit enter-the-wired; };
      steamidraUnit = import ./modules/steamidra.nix { inherit steamidra; };
      luatoolsUnit = import ./modules/luatools-moon.nix {
        inherit (upstreamBinaries) mkLumen mkLuatools;
      };
      toolsUnit = import ./modules/tools.nix { };
      homeUnit = import ./modules/home.nix {
        inherit steamnetsock;
        inherit (upstreamBinaries) mkSlsSteam mkSlsteamMoon;
      };

      # Upstream release binaries (SLSsteam, Millennium, slsteam-moon, Lumen,
      # LuaTools): fetched from each project's own GitHub Releases, versioned by
      # upstream.lock.json — a generated file, refreshed daily by
      # ci/update-binaries.sh. Nothing here is compiled.
      upstreamBinaries = import ./modules/upstream-binaries.nix { };

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
          sls-steam = upstreamBinaries.mkSlsSteam pkgs; # SLSsteam.so + library-inject.so (upstream's own release)
          slsteam-moon = upstreamBinaries.mkSlsteamMoon pkgs; # the LuaTools fork (its own release)
          netsock = homeUnit.mkNetsock pkgs; # multiplayer-fix .so (per-game LD_AUDIT)
          steamidra = steamidraUnit.mkSteamidra pkgs; # SteaMidra (SFF) launcher
          lumen = upstreamBinaries.mkLumen pkgs; # LuaTools backend dist
          luatools = upstreamBinaries.mkLuatools pkgs; # LuaTools plugin dist
          millennium = upstreamBinaries.mkMillennium pkgs; # Millennium hook (its own release)
          ticket-grabber = upstreamBinaries.mkTicketGrabber pkgs; # SLSsteam tool
          schema-grabber = upstreamBinaries.mkSchemaGrabber pkgs; # SLSsteam tool
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
      # flip programs.nix-crab.*.enable for the software you want. ONE module
      # set, NixOS only: user-scoped features are applied by activation
      # snippets and users.users.<user>.packages — home-manager is not an
      # input, not a requirement, not referenced anywhere in this flake. The
      # steam-config-nix module is re-exported here (its own gate is
      # programs.steam.config.enable, also off by default) so one import gets
      # the whole surface.
      # ------------------------------------------------------------------
      nixosModules.default = {
        imports = [
          steam-config-nix.nixosModules.default
          ./modules/options.nix
          ./modules/user.nix
          ./modules/netsock-bridge.nix
          (import ./modules/millennium.nix {
            inherit millennium;
            inherit (upstreamBinaries) mkMillennium;
          })
          slssteamUnit.module
          downgradeUnit.module
          homeUnit.module
          toolsUnit.module
          luatoolsUnit.module
          steamidraUnit.module
          accelaUnit.module
          ./modules/millennium-addons.nix
        ];
      };

      # `nix fmt`
      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);
    };
}
