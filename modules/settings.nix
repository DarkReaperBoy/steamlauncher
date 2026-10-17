# SLSsteam configuration as typed Nix options.
#
# Every key here is documented upstream — either on the SLSsteam wiki's
# Configuration page (https://github.com/AceSLS/SLSsteam/wiki/Configuration)
# or in the fork's res/config.yaml (upstream SLSsteam: res/config.yaml,
# slsteam-moon: res/config.yaml). The YAML file IS the options file: each
# option maps 1:1 to a config.yaml key, with the wiki's type and meaning.
#
# Design rules:
#   - Every option defaults to `null` = "not written". The generated
#     config.yaml is the active fork's own default config with the user's
#     non-null options merged over it, so an unset option keeps its
#     documented default (and the fork's comment) instead of us hardcoding
#     a value. Nothing here is opinionated.
#   - The merge guarantees every key the fork's C++ reads exists in the
#     file, so SLSsteam never complains about "Config loading issues".
#   - `extraSettings` is the escape hatch for keys this module doesn't
#     declare yet (future upstream additions): freeform YAML attrset,
#     merged over everything else.
{ lib, ... }:
let
  inherit (lib) mkOption types;

  # The options are only meaningful when Nix manages the file; the module in
  # home.nix asserts manageConfig when anything below is non-null.
  maybe =
    type:
    mkOption {
      type = types.nullOr type;
      default = null;
    };

  listOfInt = types.listOf types.int;
  # maps keyed by AppId/DepotId as the wiki describes ("Map of positive number : ...")
  attrsInt = types.attrsOf types.int;
  attrsStr = types.attrsOf types.str;
in
{
  options.programs.nix-crab.slssteam.settings = {
    # ---- keys upstream SLSsteam reads (wiki Configuration) ----
    DisableFamilyShareLock = maybe types.bool // {
      description = ''
        Disable bi-directional shared-license locking: others cannot lock
        licenses on your client, nor you on theirs. Respects UseWhitelist &
        AppIds when disabling it for others.
      '';
    };

    UseWhitelist = maybe types.bool // {
      description = "Turn AppIds into a whitelist instead of the default blacklist.";
    };

    AppIds = maybe listOfInt // {
      description = ''
        AppIds to ex-/include. Adding a game's AppId includes all its child
        AppIds (its DLC) too. Positive numbers.
      '';
    };

    AdditionalApps = maybe listOfInt // {
      description = ''
        Extra AppIds to inject that override black-/whitelist and OwnerIds.
        Best used only for games not in your library. (slsteam-moon reads its
        game list from stplug-in/luaappids.yaml instead; this stays for
        backward compatibility.)
      '';
    };

    DlcData = maybe (types.attrsOf (types.attrsOf types.str)) // {
      description = ''
        Only needed for games with more than 64 DLC that ship no internal DLC
        list: a map of parent AppId to a map of DLC AppId -> name.
      '';
    };

    AppTokens = maybe attrsInt // {
      description = "Per-AppId product-info tokens; fixes \"invalid configuration\" errors.";
    };

    CDKeys = maybe attrsStr // {
      description = ''
        Legacy CD keys per AppId. If unset SLSsteam generates a random
        A-Z/0-9 key seeded from accountId + appId.
      '';
    };

    FakeOffline = maybe listOfInt // {
      description = "AppIds that think Steam has no connection (Denuvo re-auth games).";
    };

    FakeAppIds = maybe attrsInt // {
      description = ''
        Map of real AppId -> fake AppId, for online play in some games.
        Never run two apps with the same FakeAppId.

        The LuaTools plugin can also add entries from its UI; those are kept
        across switches while you leave this option unset, and reset to what
        you write once you set it.
      '';
    };

    ManifestIds = maybe attrsInt // {
      description = "Map of DepotId -> ManifestId: download/lock older game versions.";
    };

    DepotBlacklist = maybe listOfInt // {
      description = "Depot ids Steam should never download.";
    };

    IdleStatus =
      maybe (
        types.submodule {
          options = {
            AppId = mkOption {
              type = types.int;
              default = 0;
              description = "AppId to show as playing; 0 disables.";
            };
            Title = mkOption {
              type = types.str;
              default = "";
              description = "Custom status title.";
            };
          };
        }
      )
      // {
        description = "Show your account as playing a game when nothing else runs.";
      };

    GameTitles = maybe attrsStr // {
      description = "Override owned game titles (AppId -> title).";
    };

    SubscriptionTimestamps = maybe attrsInt // {
      description = "Override purchase timestamps per AppId (probably purely cosmetic).";
    };

    DenuvoGames = maybe (types.attrsOf listOfInt) // {
      description = "Map of SteamId64 -> list of AppIds to block from unlocking on other accounts.";
    };

    SteamIdOverride = maybe attrsInt // {
      description = ''
        Map of AppId -> SteamId64 (or 0): overrides the SteamId an app sees
        when automatic spoofing fails, or to work around locked saves.
      '';
    };

    SmartTickets = maybe types.int // {
      description = ''
        Bitwise flags making steamId spoofing for tickets smarter by analysing
        processes that connect to the Steamclient: SteamDRM = 0x1 (1),
        Denuvo = 0x2 (2), both = 3. Same format as LogLevels.
      '';
    };

    MaxSchemaTries = maybe types.int // {
      description = "How many achievement-schema fetch attempts before falling back to the on-disk cache.";
    };

    LaunchOptions = maybe attrsStr // {
      description = ''
        Override what Steam launches per AppId. Special keys:
        4294967294 = all unowned apps, 4294967295 = all apps.
        %command% expands to Steam's original launch command.
      '';
    };

    SafeMode = maybe types.bool // {
      description = ''
        Disable SLSsteam when steamclient.so is not a known-good hash.
        Recommended on SteamOS/Deck gamemode to avoid crash loops; the wiki
        calls it the protection against soft-bricking after client updates.
      '';
    };

    Notifications = maybe types.bool // {
      description = "Toggle notify-send notifications from SLSsteam.";
    };

    WarnHashMissmatch = maybe types.bool // {
      description = "Notify when steamclient.so's hash differs from the known-safe hash (development aid).";
    };

    NotifyInit = maybe types.bool // {
      description = "Notify when SLSsteam finished initializing.";
    };

    API = maybe types.bool // {
      description = ''
        Allow sending commands to SLSsteam via /tmp/SLSsteam.API.
        See https://github.com/AceSLS/SLSsteam/blob/dev/docs/API/README.md
      '';
    };

    Plugins = maybe types.bool // {
      description = "Load Lua plugins from the plugins subdirectory (they can run arbitrary code).";
    };

    DisableCloud = maybe types.bool // {
      description = ''
        Turn off Steam Cloud for unlocked games (Valve rejects uploads to
        unowned AppIds, so leaving it on just produces a cloud-sync error per
        game). No cloud-save hook ships with this flake any more, so the flake
        writes `true` for you unless you set this yourself; only turn it off if
        you install a cloud-save tool on your own.
      '';
    };

    DisableUpdates = maybe types.bool // {
      description = "Keep managed (AdditionalApps) games on their installed build instead of auto-updating.";
    };

    FakeName = maybe types.str // {
      description = "Change your persona name clientsidedly.";
    };

    FakeEmail = maybe types.str // {
      description = "Change your account's e-mail clientsidedly (empty = off).";
    };

    FakeWalletBalance = maybe types.int // {
      description = "Change the wallet balance shown clientsidedly (0 = off).";
    };

    LogLevels = maybe types.int // {
      description = ''
        Bitwise log-level flags: Trace 0x1, Once 0x2, Debug 0x4, Warn 0x8,
        Error 0x10, Info 0x20, NotifyShort 0x40, NotifyLong 0x80.
        Default 0xff = everything (Trace/Debug stripped from release builds).
        Example: 0x90 (144) = long notifications + errors only.
      '';
    };

    DumpClientInterfaces = maybe types.bool // {
      description = "Dump all used IClientInterfaceMaps (debugging).";
    };

    ExtendedLogging = maybe types.bool // {
      description = "Log all calls to Steamworks (makes the logfile huge).";
    };

    # ---- keys only slsteam-moon reads (res/config.yaml) ----
    # Setting these while running upstream SLSsteam is harmless (unknown keys
    # are ignored); they exist so the LuaTools fork's config is fully typed.

    DisableParentalRestrictions = maybe types.bool // {
      description = "Locally unlock Steam areas restricted by parental controls (slsteam-moon).";
    };

    AutoFilterList = maybe types.bool // {
      description = "Automatically filter Apps in CheckAppOwnership to games/applications (slsteam-moon).";
    };

    PlayNotOwnedGames = maybe types.bool // {
      description = ''
        Play games not in your library. Kept for compatibility; slsteam-moon
        prefers adding games via stplug-in/luaappids.yaml (AdditionalApps),
        and upstream SLSsteam removed this key entirely.
      '';
    };

    LogLevel = maybe types.int // {
      description = ''
        slsteam-moon's own log level (0=Once, 1=Debug, 2=Info, 3=NotifyShort,
        4=NotifyLong, 5=Warn, 6=None) — distinct from upstream's bitwise
        LogLevels.
      '';
    };

    AutoUpdateApps = maybe types.bool // {
      description = "Keep managed games on the latest build (slsteam-moon's counterpart to DisableUpdates, default yes).";
    };

    InjectAllAdvertisedDlc = maybe types.bool // {
      description = "Inject every storefront-advertised DLC into package 0 (slsteam-moon).";
    };

    Achievements = maybe types.bool // {
      description = "Show achievements for unowned games by spoofing the schema source (slsteam-moon).";
    };

    AchievementOwnerId = maybe types.int // {
      description = "Fallback SteamId64 whose public achievement schemas are read (slsteam-moon).";
    };

    AchievementOwners = maybe attrsInt // {
      description = "Per-AppId override of the achievement-schema source account (slsteam-moon).";
    };

    PatternCache = maybe types.bool // {
      description = "Local pattern cache keyed by build-id/size/mtime (slsteam-moon).";
    };

    AsyncProvision = maybe types.bool // {
      description = "Refresh appinfo buffers from the PICS worker after Steam starts (slsteam-moon).";
    };

    MaxManagedApps = maybe types.int // {
      description = "Safety valve: max scripts activated per session from stplug-in (slsteam-moon; 0 = no limit).";
    };

    Donate =
      maybe (
        types.submodule {
          options = {
            Enabled = mkOption {
              type = types.bool;
              default = true;
              description = "Share short-lived manifest request codes for owned depots.";
            };
            Url = mkOption {
              type = types.str;
              default = "https://manifest.luastools.xyz";
              description = "Manifest-donation archive base URL.";
            };
            IntervalSecs = mkOption {
              type = types.int;
              default = 30;
              description = "Donation cycle interval (30-86400).";
            };
            WantedRefreshSecs = mkOption {
              type = types.int;
              default = 300;
              description = "Wanted-list refresh interval (30-86400).";
            };
            MaxMintsPerCycle = mkOption {
              type = types.int;
              default = 25;
              description = "Max mints per cycle (1-500).";
            };
            MinMintIntervalMs = mkOption {
              type = types.int;
              default = 2000;
              description = "Minimum interval between mints in ms (0-60000).";
            };
            MaxMintsPerSession = mkOption {
              type = types.int;
              default = 0;
              description = "Cap per session; 0 = unlimited (slsteam-moon).";
            };
          };
        }
      )
      // {
        description = "slsteam-moon's manifest-sharing (donation) block.";
      };

    ManifestPins =
      maybe (
        types.attrsOf (
          types.submodule {
            options = {
              locked = mkOption {
                type = types.bool;
                default = false;
                description = "Keep the app on its pinned manifests instead of updating it.";
              };

              build_id = mkOption {
                type = types.ints.unsigned;
                default = 0;
                description = "Build the pins belong to; 0 when unknown.";
              };

              depots = mkOption {
                type = types.attrsOf types.str;
                default = { };
                description = ''
                  DepotId -> manifest gid, as a string (uint64 does not fit a
                  YAML int safely).
                '';
              };
            };
          }
        )
      )
      // {
        description = ''
          slsteam-moon's per-depot manifest pins (appid -> {locked, build_id,
          depots}). Read by the C++ but absent from the default config.yaml — the
          block is created on demand.

          The LuaTools plugin writes it itself whenever you add or remove a game,
          so leave this unset while luatools.enable is on: the managed file then
          carries the plugin's own pins over on every activation. Declaring it
          here makes Nix the owner — the next switch resets it to what you wrote.
        '';
      };

    extraSettings = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      example = {
        SomeFutureKey = true;
      };
      description = ''
        Freeform YAML merged over everything else — the escape hatch for keys
        this module does not declare yet (e.g. a brand-new upstream option
        before we type it). Same rules: unset keys keep the fork's default.
      '';
    };
  };
}
