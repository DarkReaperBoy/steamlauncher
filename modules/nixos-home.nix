# Plain-NixOS home configuration: the home-side options (home-options.nix) are
# declared at the NixOS level and forwarded into home-manager.users.<user>,
# which this flake wires up itself. `home-manager` therefore becomes an
# implementation detail — the user's config stays 100% NixOS, and one
# `nixos-rebuild switch` applies everything.
#
# `homeConfigModules` is the list of home-side config modules from flake.nix:
# the same list homeModules.default uses, minus the option declarations (which
# both sides take from home-options.nix) and minus anything that belongs to the
# side owning steam-config-nix (see netsock-bridge.nix).
{ homeConfigModules }:
{
  config,
  lib,
  options,
  ...
}:
let
  cfg = config.programs.nix-crab;

  # ---- which user? --------------------------------------------------------
  # Auto-detect when the system has exactly one normal user; otherwise the
  # choice has to be explicit.
  normalUsers = lib.attrNames (lib.filterAttrs (_: u: u.isNormalUser or false) config.users.users);
  detected = if lib.length normalUsers == 1 then lib.head normalUsers else null;
  targetUser = if cfg.user != null then cfg.user else detected;

  # ---- does anything need a home at all? ----------------------------------
  # Gated so that importing this flake changes nothing for a system that has no
  # nix-crab home option set — Home Manager only ever takes over the target
  # user's directory when it is actually asked to manage something.
  # Every typed settings option defaults to null ("not written"), extraSettings
  # to {}, so anything non-null means the user asked for a managed config.
  settingsChanged =
    cfg.slssteam.settings.extraSettings != { }
    || lib.any (v: v != null) (lib.attrValues (removeAttrs cfg.slssteam.settings [ "extraSettings" ]));
  needsHome =
    cfg.slssteam.manageConfig
    || cfg.slssteam.moon.enable
    || settingsChanged
    || cfg.netsock.enable
    || cfg.netsock.games != [ ]
    || cfg.tools.enable
    || cfg.luatools.enable
    || cfg.luatools.lumenService
    || cfg.millennium.plugins != [ ]
    || cfg.millennium.themes != [ ]
    || cfg.accela.enable
    || cfg.steamidra.enable;

  # ---- classification guard ----------------------------------------------
  # Every feature under programs.nix-crab has to say where it is applied, so a
  # new option can never be silently dropped by the forwarding below.
  homeSide = [
    "netsock"
    "tools"
    "luatools"
    "accela"
    "steamidra"
  ];
  systemSide = [
    "user"
    "steam"
    "slssteam-moon"
    "downgrade"
  ];
  # declared on both sides, and forwarded per key
  split = [
    "slssteam"
    "millennium"
  ];
  known = homeSide ++ systemSide ++ split;
  unclassified = lib.filter (n: !(lib.elem n known)) (lib.attrNames config.programs.nix-crab);

  # ---- what is forwarded --------------------------------------------------
  # The whole home-side surface, minus the keys the NixOS module owns itself.
  forward = {
    slssteam = removeAttrs cfg.slssteam [
      "enable"
      "extraEnv"
    ];
    millennium = {
      inherit (cfg.millennium) plugins themes;
    };
  }
  // lib.getAttrs homeSide cfg;
in
{
  options.programs.nix-crab.user = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "alice";
    description = ''
      The user the home-side options (config.yaml, netsock, LuaTools, ACCELA,
      SteaMidra, Millennium add-ons, the nix-crab commands) are configured for.
      Leave unset when the system has exactly one normal user — that one is
      used. With zero or several normal users, set it explicitly.
    '';
  };

  config = {
    # One nixpkgs for the system and the homes it configures: the packages HM
    # installs come from the pkgs the system already resolved (free licenses
    # and all), and HM does not evaluate a second nixpkgs.
    home-manager.useGlobalPkgs = lib.mkDefault true;
    # NOT useUserPackages: it writes users.users.<name>.packages from
    # home-manager.users, and auto-detecting the user reads users.users — the
    # two together are an infinite recursion (home-manager#594). Packages land
    # in ~/.nix-profile instead, which NixOS puts on PATH anyway. Setting this
    # to true yourself is fine as long as programs.nix-crab.user is set
    # explicitly (the read is then never forced).
    home-manager.useUserPackages = lib.mkDefault false;

    assertions = [
      {
        assertion = cfg.user == null || config.users.users ? ${cfg.user};
        message = ''
          programs.nix-crab.user is set to "${toString cfg.user}", but users.users.${toString cfg.user}
          does not exist. Declare the user first (users.users.<name>.isNormalUser = true).
        '';
      }
      {
        assertion = !needsHome || targetUser != null;
        message = ''
          programs.nix-crab: a home-side option is set, but this system has
          ${toString (lib.length normalUsers)} normal user(s), so the target user
          cannot be guessed. Set programs.nix-crab.user = "<name>";.
        '';
      }
      {
        assertion = unclassified == [ ];
        message = ''
          programs.nix-crab: unclassified option(s): ${
            lib.concatMapStringsSep ", " (n: "'" + n + "'") unclassified
          }.
          Every feature under programs.nix-crab has to be listed in
          modules/nixos-home.nix as home-side, system-side or split, so the
          NixOS -> home-manager forwarding cannot silently ignore it.
        '';
      }
    ];

    home-manager.users = lib.mkIf (needsHome && targetUser != null) {
      ${targetUser} = {
        imports = [ ./home-options.nix ] ++ homeConfigModules;
        programs.nix-crab = forward;
        # The user does not manage Home Manager, so this flake has to give it
        # the one thing HM refuses to run without. A real Home Manager setup
        # can still override it.
        home.stateVersion = lib.mkDefault "25.05";
      };
    };
  };
}
