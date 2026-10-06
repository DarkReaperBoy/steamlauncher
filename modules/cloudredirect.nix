{
  cloudredirect,
  cloudredirect-moon,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.programs.nix-crab.cloudredirect = {
    enable = lib.mkEnableOption "Enable CloudRedirect";

    moon.enable = lib.mkEnableOption ''
      the cloudredirect-moon hook instead of upstream CloudRedirect. The moon
      fork scans <Steam>/config/stplug-in/*.lua and luaappids.yaml, so it
      recognises games added by the LuaTools stack. Only enable for LuaTools;
      upstream CloudRedirect is the default.
    '';
  };

  config = lib.mkIf config.programs.nix-crab.cloudredirect.enable {
    services.flatpak.enable = true;
    # NixOS's native flatpak module asserts xdg.portal.enable == true, and
    # portal-enable itself asserts a backend exists in extraPortals — without
    # this pair a plain system fails the build with "To use Flatpak you must
    # enable XDG Desktop Portals". All mkDefault: any definition in the
    # user's own config (e.g. the KDE/GNOME portal) takes precedence — for
    # extraPortals a non-default definition replaces ours entirely.
    # config.common.default = "*" is what xdg-desktop-portal >= 1.17 asks for
    # (evaluation warning): pick the first backend lexicographically, which is
    # the pre-1.17 behaviour every desktop config relied on.
    xdg.portal = {
      enable = lib.mkDefault true;
      extraPortals = lib.mkDefault [ pkgs.xdg-desktop-portal-gtk ];
      config.common.default = lib.mkDefault "*";
    };
    programs.nix-crab.slssteam.extraEnv.LD_PRELOAD =
      if config.programs.nix-crab.cloudredirect.moon.enable then
        "${cloudredirect-moon}/cloud_redirect.so"
      else
        "${cloudredirect}";
  };
}
