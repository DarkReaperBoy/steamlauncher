{
  description = "Out-of-repo test harness for the steamlauncher (nix-crab) flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    crab = {
      url = "path:.."; # the repo under test (this flake lives in tests/)
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      crab,
    }:
    let
      system = "x86_64-linux";

      freePkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      testerUser = {
        users.users.tester = {
          isNormalUser = true;
          home = "/home/tester";
        };
      };

      mkOs' =
        users: modules:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = modules ++ [
            crab.nixosModules.default
            {
              nixpkgs.config.allowUnfree = true;
              boot.loader.grub.enable = false;
              fileSystems."/" = {
                device = "/dev/sda1";
                fsType = "ext4";
              };
              system.stateVersion = "25.05";
            }
            users
          ];
        };

      mkOs = mkOs' testerUser;

      twoUsers = {
        users.users.tester = {
          isNormalUser = true;
          home = "/home/tester";
        };
        users.users.bob = {
          isNormalUser = true;
          home = "/home/bob";
        };
      };
    in
    {
      nixosConfigurations = {
        # everything off: no Steam, no Home Manager wiring, nothing installed
        bare = mkOs [ ];

        # the whole surface, written as plain NixOS config
        full = mkOs [
          {
            programs.nix-crab = {
              steam = {
                enable = true;
                extraCompatPackages = [ ];
                config = {
                  enable = true;
                  apps."440" = {
                    name = "Team Fortress 2";
                    env.TZ = "UTC";
                    args = [ "--novid" ];
                  };
                };
              };
              slssteam.enable = true;
              millennium.enable = true;
              millennium.plugins = [ "3dc714a7c1b1" ];
              downgrade.enable = true;
            };
            programs.nix-crab.slssteam = {
              manageConfig = true;
              settings = {
                AppIds = [
                  440
                  730
                ];
                FakeName = "tester";
                extraSettings.MaxSchemaTries = 3;
              };
            };
            programs.nix-crab.netsock = {
              enable = true;
              games = [ 1966720 ];
            };
            programs.nix-crab.tools.enable = true;
            programs.nix-crab.accela.enable = true;
            programs.nix-crab.steamidra.enable = true;
          }
        ];

        # the LuaTools stack, as plain NixOS config
        moon = mkOs [
          {
            programs.nix-crab.slssteam-moon.enable = true;
            programs.nix-crab.slssteam.moon.enable = true;
            programs.nix-crab.luatools.enable = true;
            programs.nix-crab.luatools.lumenService = true;
          }
        ];

        # Steam without any feature: just the client, unified knob
        steamOnly = mkOs [
          {
            programs.nix-crab.steam.enable = true;
          }
        ];

        # a different Steam package, through the nix-crab knob
        steamPkg = mkOs [
          (
            { pkgs, ... }:
            {
              programs.nix-crab.steam = {
                enable = true;
                # a visibly different derivation than plain pkgs.steam
                package = pkgs.steam.override { extraEnv.NIX_CRAB_TEST = "1"; };
              };
            }
          )
        ];

        # the whole LuaTools stack as plain NixOS config, activated for real
        # against /tmp/hm-nixos
        smokeNixos =
          mkOs'
            {
              users.users.nako = {
                isNormalUser = true;
                home = "/tmp/hm-nixos";
              };
            }
            [
              {
                programs.nix-crab = {
                  slssteam-moon.enable = true;
                  tools.enable = true;
                  steam.config.enable = true;
                };
                programs.nix-crab.slssteam = {
                  manageConfig = true;
                  moon.enable = true;
                  settings.AppIds = [ 440 ];
                };
                programs.nix-crab.netsock = {
                  enable = true;
                  games = [ 1966720 ];
                };
                programs.nix-crab.luatools.enable = true;
                programs.nix-crab.luatools.lumenService = true;
              }
            ];

        # two normal users + a home-side option: must FAIL, ask for the user
        ambiguousUser = mkOs [
          twoUsers
          {
            programs.nix-crab.tools.enable = true;
          }
        ];

        # two normal users + explicit user: works, for that user (netsock makes
        # an activation snippet, so the target user is observable)
        explicitUser = mkOs [
          twoUsers
          {
            programs.nix-crab.user = "bob";
            programs.nix-crab.tools.enable = true;
            programs.nix-crab.netsock.enable = true;
          }
        ];

        # must FAIL: Millennium and slsteam-moon both want the CEF endpoint
        badCombo = mkOs [
          {
            programs.nix-crab.millennium.enable = true;
            programs.nix-crab.slssteam-moon.enable = true;
          }
        ];

        # must FAIL: forcing Steam off while a feature needs it
        badSteamOff = mkOs [
          {
            programs.nix-crab.steam.enable = false;
            programs.nix-crab.slssteam.enable = true;
          }
        ];

        # `steam = true` sugar (bool shorthand for steam.enable)
        steamSugar = mkOs [
          {
            programs.nix-crab.steam = true;
          }
        ];

        # freeform passthrough: an upstream programs.steam option written
        # under nix-crab.steam lands in programs.steam untouched
        steamPassthrough = mkOs [
          {
            programs.nix-crab.steam = {
              enable = true;
              remotePlay.openFirewall = true;
              protontricks.enable = true;
              # function form: applied inside the Steam FHS environment
              # `hello` is distinctive: steam's own FHS env never contains it
              extraPkgs = p: with p; [ hello ];
            };
          }
        ];

        # the config-writer scenarios, as plain NixOS config against
        # /tmp/hm-test (test-writer.sh extracts and runs the activation text)
        writerSmoke =
          mkOs'
            {
              users.users.nako = {
                isNormalUser = true;
                home = "/tmp/hm-test";
              };
            }
            [
              {
                programs.nix-crab = {
                  slssteam = {
                    manageConfig = true;
                    moon.enable = true;
                    settings.AppIds = [ 440 ];
                  };
                  netsock = {
                    enable = true;
                    games = [ 1966720 ];
                  };
                  tools.enable = true;
                  luatools = {
                    enable = true;
                    lumenService = true;
                  };
                  steam.config.enable = true;
                };
              }
            ];

        # minimal variant: the user declares FakeAppIds, so Nix owns it
        writerFake =
          mkOs'
            {
              users.users.nako = {
                isNormalUser = true;
                home = "/tmp/hm-test2";
              };
            }
            [
              {
                programs.nix-crab.slssteam = {
                  manageConfig = true;
                  moon.enable = true;
                  settings.FakeAppIds = {
                    "440" = 480;
                  };
                };
              }
            ];

        # must FAIL: settings without manageConfig
        badSettings = mkOs [
          {
            programs.nix-crab.slssteam.settings.AppIds = [ 440 ];
          }
        ];

        # must FAIL: netsock.games without steam-config-nix
        badNetsock = mkOs [
          {
            programs.nix-crab.netsock = {
              enable = true;
              games = [ 1966720 ];
            };
          }
        ];
      };

    };
}
