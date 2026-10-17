{
  description = "Declarative Steam tooling for NixOS: SLSsteam injection, Millennium, LuaTools, steam-config-nix, ACCELA, SteaMidra (nix-crab, updated continuation)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # SLSsteam itself comes from upstream's OWN flake, pinned to a rev —
    # their nix-modules/default.nix builds it with pkgsi686Linux
    # {openssl, curl, luajit}, so the .so carries a RUNPATH into the store
    # and its dependencies resolve without relying on the host Steam env
    # (that is the dependency resolution upstream designed for NixOS; their
    # wiki's NixOS snippet consumes exactly this package output).
    #
    # Pinned, not tracking: the GitHub release asset (and current main)
    # crashes this client — SIGSEGV in SLSsteam's hkCMInterface_RecvPkt →
    # getProtoBufTypeName hook ~10s after launch, reproducibly, with or
    # without Millennium — while this rev runs stably (verified by repeated
    # live launches). A fixed rev also keeps the narHash immutable.
    sls-steam = {
      url = "github:AceSLS/SLSsteam/9c829a7ddae52b6fdeee37933a83e8d6f4b9f1c6";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Millennium, slsteam-moon, Lumen and LuaTools are consumed as their own
    # GitHub release binaries — versions and hashes live in upstream.lock.json,
    # refreshed by ci/update-binaries.sh. Nothing here is compiled (the pinned
    # sls-steam input above is upstream's prebuilt output, not a local build).

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
      sls-steam,
      steamnetsock,
      steamidra,
      millennium,
      steam-config-nix,
      enter-the-wired,
    }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # Upstream's own package of the pinned rev (their flake output — RUNPATH
      # resolves libssl/libcrypto/libcurl from the store, no host dependency),
      # plus res/config.yaml from the SAME source tree: the managed config's
      # merge base must be the config the shipped .so was built against, so
      # binary and base always come from one rev.
      mkSlsSteam =
        pkgs:
        let
          up = sls-steam.packages.${pkgs.stdenv.hostPlatform.system}.sls-steam;
        in
        pkgs.runCommand up.name { } ''
          mkdir -p "$out"
          cp -a ${up}/. "$out"/
          chmod -R u+w "$out"
          mkdir -p "$out/res"
          cp ${sls-steam.outPath}/res/config.yaml "$out/res/"
        '';

      # Feature units: each modules/<feature>.nix returns
      # `{ inputs }: { module, mk* }` — instantiate ONCE here, then take
      # `.module` for the module outputs and `.mk*` for packages.*. One
      # definition per derivation, so a package and the option that installs it
      # are always bit-identical. (Files that own no derivations —
      # settings.nix, millennium*.nix — are plain modules, imported where
      # used.)
      slssteamUnit = import ./modules/slssteam.nix {
        inherit mkSlsSteam;
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
        inherit steamnetsock mkSlsSteam;
        inherit (upstreamBinaries) mkSlsteamMoon;
      };

      # Upstream release binaries (Millennium, slsteam-moon, Lumen, LuaTools
      # and SLSsteam's two .NET tools): fetched from each project's own GitHub
      # Releases, versioned by upstream.lock.json — a generated file, refreshed
      # daily by ci/update-binaries.sh. The injected SLSsteam.so is NOT one of
      # them (see the sls-steam input above).
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
          sls-steam = mkSlsSteam pkgs; # SLSsteam.so + library-inject.so (upstream's own flake build of the pinned rev)
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
