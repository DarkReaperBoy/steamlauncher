# The complete nix-crab option surface (settings, netsock, tools, luatools,
# millennium add-ons, accela, steamidra), declared once for the ONE module
# set: nixosModules.default. There is no home-manager module output and no HM
# anywhere behind this — user-scoped files are written by activation snippets
# (modules/activate.nix) on every `nixos-rebuild switch`.
#
# This file declares options ONLY — no config. Every definition that needs a
# home directory lives in the per-feature modules next to it.
{ lib, ... }:
{
  imports = [
    ./settings.nix
  ];

  options.programs.nix-crab = {
    slssteam.manageConfig = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether Nix manages ~/.config/SLSsteam/config.yaml. Disabled by
        default so tools like SteaMidra can edit the file without it being
        reset on the next switch. When enabled, the file is the active fork's
        default config merged with `settings` — written as a real file (not a
        store symlink) so SLSsteam and the LuaTools plugin can keep writing to
        it, with the runtime-owned keys (ManifestPins, FakeAppIds) carried over
        on every activation.
      '';
    };

    slssteam.moon.enable = lib.mkEnableOption ''
      slsteam-moon as the config merge base (programs.nix-crab.slssteam.
      settings is applied over slsteam-moon's default config instead of
      upstream SLSsteam's). Set this together with
      programs.nix-crab.slssteam-moon.enable.
    '';

    netsock.enable = lib.mkEnableOption ''
      installing netsock (steamnetsock-patch) to
      ~/.config/SLSsteam/tools/netsock/netsock.so. The file is only ever
      used per game — see netsock.games below, or set the launch option by
      hand.
    '';

    netsock.games = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      default = [ ];
      example = [ 1966720 ];
      description = ''
        AppIds to launch with netsock. Each one is written as a steam-config-nix
        app (`programs.nix-crab.steam.config.apps.<id>`) whose launch
        environment carries

          LD_AUDIT=$HOME/.config/SLSsteam/tools/netsock/netsock.so

        which is exactly the per-game launch option steamnetsock-patch
        documents. Needs netsock.enable (for the .so) and
        programs.nix-crab.steam.config.enable — both are asserted.

        Never list a game with anti-cheat: netsock scans and modifies game
        memory. Name the entry or add other options yourself under
        programs.nix-crab.steam.config.apps.<id> if you want more than LD_AUDIT.
      '';
    };

    tools.enable = lib.mkEnableOption ''
      nix-crab's maintenance command (nix-crab-update: flake update + rebuild
      + status). nix-crab-status does NOT need this: it installs automatically
      with the first programs.nix-crab feature that is enabled.
    '';

    luatools.enable = lib.mkEnableOption ''
      the LuaTools stack for slsteam-moon: Lumen (backend) and the LuaTools
      plugin, placed under ~/.local/share/Lumen. Requires
      programs.nix-crab.slssteam-moon.enable on the system side (that also
      brings steam-run, which the `lumen` wrapper needs).
    '';

    luatools.lumenService = lib.mkEnableOption ''
      a systemd user service for Lumen instead of the steam-wrapper sidecar.
      With this enabled Lumen starts at login (unit nix-crab-lumen,
      Restart=on-failure) and the `steam` command is no longer shadowed, so
      Steam launches plain — Lumen attaches on its own once the CEF port
      appears. Default keeps the wrapper behaviour.
    '';

    millennium.plugins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "3dc714a7c1b1" ];
      description = ''
        Millennium plugin IDs from https://steambrew.app/plugins — the `id` in
        a plugin's store URL (https://steambrew.app/plugin/<id>). Each one is
        unpacked into ~/.local/share/millennium/plugins on activation unless it
        is already installed.
      '';
    };

    millennium.themes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "1wwKwvHrFuzMs7Kb1Uzu"
        "Adwaita"
      ];
      description = ''
        Millennium theme IDs from https://steambrew.app/themes — the `id` in a
        theme's store URL (https://steambrew.app/theme/<id>), or the theme's
        display name or GitHub repo name, whichever is at hand. Each one is
        unpacked into ~/.steam/steam/millennium/themes on activation
        unless it is already installed. Pick the active theme in Millennium's UI
        afterwards.
      '';
    };

    accela.enable = lib.mkEnableOption "ACCELA (Steam depot downloader, Enter The Wired)";

    accela.config = {
      auto_skip_single_choice = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Skip dialogs that only offer one choice.";
      };
      library_mode = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Work against the Steam library instead of managing games itself.";
      };
      max_downloads = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 16;
        description = "Parallel depot downloads.";
      };
      sls_config_management = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Hand config management to SLSsteam.";
      };
      slssteam_mode = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Hand games to SLSsteam instead of installing them standalone.";
      };
      use_steamless = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Steamless (no-Steam) mode.";
      };
    };

    steamidra.enable = lib.mkEnableOption "SteaMidra (SFF) game downloader";
  };
}
