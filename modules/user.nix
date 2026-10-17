# programs.nix-crab.user + the cross-feature assertions that depend on it.
# This replaced the old nixos-home.nix with the home-manager forwarding
# removed: user-scoped features are applied by each feature's own activation
# snippet (modules/activate.nix) and users.users.<user>.packages —
# home-manager is not involved anywhere in this flake.
{
  lib,
  config,
  ...
}:
let
  t = import ./target.nix { inherit config lib; };
  cfg = config.programs.nix-crab;

  # ---- does anything need a user home at all? -----------------------------
  # Every typed settings option defaults to null ("not written"), extraSettings
  # to {}, so anything non-null means the user asked for a managed config.
  settingsChanged =
    cfg.slssteam.settings.extraSettings != { }
    || lib.any (v: v != null) (lib.attrValues (removeAttrs cfg.slssteam.settings [ "extraSettings" ]));
  needsUserFiles =
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
in
{
  options.programs.nix-crab.user = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "alice";
    description = ''
      The user the scoped features (config.yaml, netsock, LuaTools, ACCELA,
      SteaMidra, Millennium add-ons, the nix-crab commands) are configured for.
      Leave unset when the system has exactly one normal user — that one is
      used. With zero or several normal users, set it explicitly.
    '';
  };

  config.assertions = [
    {
      assertion = cfg.user == null || config.users.users ? ${cfg.user};
      message = ''
        programs.nix-crab.user is set to "${toString cfg.user}", but users.users.${toString cfg.user}
        does not exist. Declare the user first (users.users.<name>.isNormalUser = true).
      '';
    }
    {
      assertion = !needsUserFiles || t.user != null;
      message = ''
        programs.nix-crab: a user-scoped option is set, but this system has
        ${toString (lib.length t.normalUsers)} normal user(s), so the target user
        cannot be guessed. Set programs.nix-crab.user = "<name>";.
      '';
    }
  ];
}
