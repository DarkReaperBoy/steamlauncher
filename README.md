# nix-crab

[![ci](https://github.com/DarkReaperBoy/steamlauncher/actions/workflows/ci.yml/badge.svg)](https://github.com/DarkReaperBoy/steamlauncher/actions/workflows/ci.yml)

Declarative Steam for NixOS — SLSsteam injection, Millennium *or* LuaTools, per-game Steam
configuration, ACCELA, SteaMidra, netsock and a client-downgrade tool — written as **one flat
`programs.nix-crab.*` block in your NixOS config**. An updated continuation of
[ItszFinn/nix-crab](https://github.com/ItszFinn/nix-crab).

- **One namespace.** Every knob lives under `programs.nix-crab.*`, including Steam itself and the
  whole per-game configuration surface. No `programs.steam` vs. `programs.nix-crab` split, no
  conflicts between the official Steam module and the patched one.
- **One switch, zero Home Manager.** Home-directory files (SLSsteam config, netsock, Lumen,
  desktop entries, user services) are written by activation snippets during `nixos-rebuild switch`.
  This flake has no home-manager input, no `homeModules` output, no second config language — one
  flat NixOS block does everything.
- **One default: off.** Import the module, flip what you want. Nothing installs itself, and every
  artefact is pinned — flake inputs, or `upstream.lock.json` for the release binaries.

```nix
programs.nix-crab = {
  slssteam.enable = true;                              # SLSsteam injected via LD_AUDIT
  steam.config = {                                     # per-game config (steam-config-nix)
    enable = true;
    apps."438100" = {
      name = "VRChat";
      args = [ "--fps=60" ];
      env.MANGOHUD = "1";
    };
  };
  tools.enable = true;                                 # nix-crab-status / nix-crab-update
};
```

---

## Installation

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-crab.url = "github:DarkReaperBoy/steamlauncher";
  };
}
```

```nix
# configuration.nix
modules = [ inputs.nix-crab.nixosModules.default ];

programs.nix-crab = {
  slssteam.enable = true;          # upstream SLSsteam — or slssteam-moon.enable for LuaTools
  # millennium.enable = true;      # themes & plugins (not with slssteam-moon)
  # downgrade.enable = true;       # nix-crab-downgrade on PATH
};
```

That is the whole integration. Steam is enabled, injected and configured; the home directory is
managed by activation snippets; no second module, no `home-manager` import, no `home.stateVersion`
to pick — home-manager is not part of this flake in any way. (Steam is
unfree, so your usual `nixpkgs.config.allowUnfree = true` — or an `allowUnfreePredicate` covering
`steam` — still applies; it is evaluated against *your* nixpkgs config, never this flake's.)

### Which user?

Everything that touches a home directory is applied to **one** user. With a single normal user on
the system it is picked automatically. If there are none — or several — say so explicitly:

```nix
programs.nix-crab.user = "alice";
```

Nothing is guessed on a multi-user machine, and nothing is configured for a user who was not
chosen. Systems with no user-scoped option set at all are left completely untouched: not a single
nix-crab snippet runs until the flake is actually asked to write into a home.

---

## The option surface

Everything is off/null by default. `programs.nix-crab`:

| Option | Applies | What it does |
| ------ | ------- | ------------ |
| `steam.enable` | system | Turns the Steam client on/off. `null` (default) = on as soon as a nix-crab feature needs it. |
| `steam.package` | system | The Steam package everything is built on (default `pkgs.steam`, or Millennium's when `millennium.enable`). Injection is applied on top. |
| `steam.extraCompatPackages` | system | Compatibility tools made available to Steam. |
| `steam.extraPkgs` | system | Extra FHS libraries, fed into the single `steam.override` nix-crab performs (the old overlay workaround for this is gone). Defaults to a baseline native-gaming set (libXcursor, libXi, libXinerama, libXScrnSaver, libpng, libpulseaudio, libvorbis, libstdc++, libkrb5, keyutils, gamemode); assigning replaces it, `[]` opts out. Plain list, or `p: [...]` applied inside the FHS environment. |
| `steam.config.*` | system | **steam-config-nix**: per-game launch options, compat tools, Proton prefixes, beta branches, languages, winetricks, game files, artwork, non-Steam apps. Alias of upstream's `programs.steam.config`. |
| `slssteam.enable` | system | Inject upstream SLSsteam (`LD_AUDIT` on the Steam package). |
| `slssteam.extraEnv` | system | Extra environment variables on the Steam package. |
| `slssteam-moon.enable` | system | Inject [slsteam-moon](https://github.com/swwayps/slsteam-moon) instead (its own release binary, fetched not compiled). |
| `slssteam.manageConfig` | home | Nix writes `~/.config/SLSsteam/config.yaml`. |
| `slssteam.settings.*` | home | Typed SLSsteam config — see [SLSsteam configuration](#slssteam-configuration). |
| `slssteam.moon.enable` | home | Merge base = slsteam-moon's default config (set together with `slssteam-moon.enable`). |
| `netsock.enable` | home | Install `netsock.so` under `~/.config/SLSsteam/tools/netsock/`. |
| `netsock.games` | home | AppIds that get the netsock launch option, written through steam-config-nix. |
| `luatools.enable` | home | Lumen + the LuaTools plugin under `~/.local/share/Lumen`, `lumen` command, `steam` wrapper, `steam-run`. |
| `luatools.lumenService` | home | Run Lumen as a user service instead of the `steam` wrapper. |
| `millennium.enable` | system | Millennium overlay; `millennium-steam` becomes the Steam base. |
| `millennium.plugins`, `millennium.themes` | home | [steambrew.app](https://steambrew.app) IDs, installed on activation. |
| `accela.enable` | home | ACCELA depot downloader (Qt-clean AppImage wrapper, icon, desktop entry, seeded config). |
| `accela.config.*` | home | ACCELA's `[General]` keys. |
| `steamidra.enable` | home | SteaMidra (SFF) launcher + .NET 9 runtime + forced desktop entry. |
| `downgrade.enable` | system | `nix-crab-downgrade` on PATH. |
| `downgrade.package` | system | Replace the downgrade wrapper. |
| `user` | system | Which user the home-side options apply to (auto-detected with one normal user). |
| `tools.enable` | home | `nix-crab-status` and `nix-crab-update` on PATH. |

Anything else `programs.steam` accepts (`remotePlay.openFirewall`, `protontricks`,
`dedicatedServer`, `gamescopeSession`, …) is written under `steam.*` freeform and forwarded
untouched — upstream's types and docs stay authoritative.

**“home”** in the table means: applied to the chosen user's home (or PATH) by an activation
snippet during `nixos-rebuild switch`, as root, chowned over afterwards. No Home Manager.

Misconfiguration fails at **eval time**, with the fix in the message:

| Assertion | Trigger |
| --------- | ------- |
| settings set without `manageConfig` | your values would be silently dropped |
| `millennium.enable` + `slssteam-moon.enable` | both want Steam's CEF endpoint |
| a feature needs Steam but it is disabled | `steam.enable = false` / `programs.steam.enable = false` |
| `luatools.enable` + `manageConfig` without `slssteam.moon.enable` | wrong config merge base |
| `netsock.games` without `netsock.enable` | no `netsock.so` to point at |
| `netsock.games` without `steam.config.enable` | nowhere to write the launch option |
| `user` set to an unknown user | no such `users.users` entry |
| home-side option set, user ambiguous | `programs.nix-crab.user` has to be named |

---

## How it fits together

```
configuration.nix                      programs.nix-crab.*
        │                                       │
        ▼                                       ▼
┌───────────────────── nixosModules.default ─────────────────────┐
│  steam.*  ─────────────► programs.steam.{enable,package,...}   │
│  steam.config.* ─alias─► programs.steam.config.* (steam-config-│
│                         nix: patcher service, compat tools)    │
│  slssteam.* ─┐                                               │
│  slssteam-moon│──► programs.steam.package = steamBase.override │
│  millennium ─┘     { extraEnv.LD_AUDIT = library-inject:SLSsteam }│
│                                                                │
│  user-scoped options ─► system.activationScripts (nix-crab-*)  │
│                        ├── config.yaml  (fork default ⊕ settings)│
│                        ├── netsock.so + netsock.games wrappers │
│                        ├── Lumen + LuaTools plugin             │
│                        ├── ACCELA / SteaMidra desktop entries  │
│                        └── Millennium plugins & themes         │
│  tools/accela/… ──────► environment.systemPackages             │
└────────────────────────────────────────────────────────────────┘
```

- **`steam.*` is the single owner of the official Steam module.** Whatever you set there is
  translated into `programs.steam.*`, so `nix-crab` and NixOS never fight over the package: the
  injection is built *from* your `steam.package`, and `steam.enable = null` means "on when a
  feature needs it".
- **`steam.config.*` is an alias, not a fork.** It forwards to
  [steam-config-nix](https://github.com/different-name/steam-config-nix)'s `programs.steam.config`,
  which this flake re-exports unchanged — upstream's docs and option search apply 1:1.
- **No Home Manager — not even internally.** The flake has no home-manager input and no
  `homeModules` output; user-scoped options are applied by activation snippets
  (`system.activationScripts."nix-crab-*"`, target user auto-detected from `users.users`) and
  `environment.systemPackages`. Packages deliberately do NOT go through `users.users.<user>`:
  user detection reads `users.users`, and writing it from a user-dependent gate recurses
  (home-manager#594, the same trap its own module documents).

Two client stacks exist and they are mutually exclusive — both want Steam's CEF debugging endpoint:

- **Millennium** (`millennium.enable`) — themes and plugins; takes the endpoint as a pipe.
- **LuaTools** (`slssteam-moon.enable` + `luatools.enable`) — the Lua manifest workflow; needs the
  TCP port Lumen attaches to.

Upstream SLSsteam (`slssteam.enable`) stacks with either, or with nothing.

---

## Steam

```nix
programs.nix-crab.steam = true;   # shorthand — exactly `steam.enable = true`

programs.nix-crab.steam = {
  enable = true;                                  # or leave null: on when a feature needs it
  package = pkgs.steam.override {                 # optional base; injection stacks on top
    extraEnv.MANGOHUD = true;
  };
  extraPkgs = [ pkgs.libXcursor pkgs.libXi ];   # FHS libs — replaces the baseline list
  extraCompatPackages = [ pkgs.proton-ge-custom ];

  remotePlay.openFirewall = true;                 # anything programs.steam accepts passes
  protontricks.enable = true;                     # through untouched

  config = {                                      # steam-config-nix, see below
    enable = true;
  };
};
```

(`steam = true` is a *whole-value* shorthand: a bool can't carry keys, so use
`steam.enable = true` when you set more.)

**Why `extraPkgs` exists.** `programs.steam.package` is a `types.package` option — two definitions
are an eval error, so extra FHS libraries used to require an `nixpkgs.overlays` workaround around
the package. nix-crab performs the *single* override itself (injection env and extra libraries
together), so the libraries live here and chain in with everything else. It defaults to the usual
native-gaming baseline, so a plain `programs.nix-crab.steam.enable = true` already ships with
X-cursor/Xinerama/XScreenSaver, the PulseAudio/Vorbis/PNG libs, krb5, keyutils and gamemode — no
`p: with p; [...]` in your config unless you want *different* libs. When the override is
baseline-only (no injection, no explicit `package`) it goes in at `mkDefault` priority, so your own
raw `programs.steam.package` still wins instead of colliding with it.

`programs.nix-crab.millennium.enable` swaps the default base for Millennium's own `millennium-steam`
(a `steam.override` of its own), so a single `programs.steam.package` ends up carrying
`LD_AUDIT` (SLSsteam), `MILLENNIUM_RUNTIME_PATH` and whatever you add — re-overriding re-enters
Millennium's function, whose merge keeps everything.

## Per-game configuration (steam-config-nix)

```nix
programs.nix-crab.steam.config = {
  enable = true;
  onSteamRunning = "close";                     # wait (default) | close | force-close | skip
  defaultCompatTool = "proton_experimental";

  apps."438100" = {
    name = "VRChat";
    env.MANGOHUD = "1";
    args = [ "--fps=60" ];
    rawLaunchOptions = "DXVK_ASYNC=1 %command%";   # paste-style launch string
  };

  nonSteamApps."Vintage Story" = {
    target = pkgs.vintagestory;
    compatTool = "proton_experimental";
  };
};
```

Upstream documents the whole surface — structured launch options compiled into a wrapper script,
compat tools and Proton prefixes, beta branches and languages, winetricks verbs, game files and
mods, library artwork and desktop entries, per-app systemd units. See its
[docs](https://different-name.github.io/steam-config-nix/docs/) and
[options search](https://different-name.github.io/steam-config-nix/search/); only the *path* is
prefixed here.

Two things to know:

- Steam holds its config files open and rewrites them on exit, so most changes are applied the next
  time Steam closes (`onSteamRunning` controls that).
- Anything typed manually into Steam's launch options field gets overwritten for apps you configure
  here — move what you want to keep into `rawLaunchOptions`.

---

## SLSsteam configuration

`programs.nix-crab.slssteam.settings` mirrors the fork's YAML config file as typed options — the
YAML file *is* the options file ([wiki → Configuration](https://github.com/AceSLS/SLSsteam/wiki/Configuration)).

```nix
programs.nix-crab.slssteam = {
  manageConfig = true;                 # Nix owns ~/.config/SLSsteam/config.yaml
  moon.enable = false;                 # true = merge over slsteam-moon's defaults
  settings = {
    AppIds = [ 440 730 ];              # listOf int
    SmartTickets = 3;                  # bitflag int (1 = SteamDRM, 2 = Denuvo)
    FakeName = "tester";               # string
    IdleStatus = { AppId = 480; Title = "grinding"; };
    ManifestPins."440".locked = true;  # slsteam-moon only
    extraSettings.SomeNewKey = 42;     # freeform escape hatch for untyped keys
  };
};
```

How the file is produced:

- **Every option defaults to `null` = not written.** Unset keeps the fork's documented default;
  the flake has no opinions about your setup.
- The merge base is the *active fork's own* `res/config.yaml` — shipped inside the very release
  archive the binaries come from — so the file always contains every key that fork's C++ reads
  (no "Config loading issues" notification), the comments survive, and the key set follows every
  release the daily sync picks up.
- Values are deep-merged with `yq-go`; AppId-shaped keys come back out unquoted so the LuaTools
  plugin can still read and edit them line-wise.
- One flake-level default is applied: **`DisableCloud: true`**. Both forks default it to `no`
  because they normally ship a cloud-save hook; this flake doesn't ship one any more, and upstream
  documentation says to use `yes` without it — otherwise Valve rejects every upload and each
  unlocked game shows a cloud-sync error. Setting `settings.DisableCloud = false` wins.
- The file is written as a **real file, not a store symlink** (an activation step: atomic,
  644, and only when the content changes). SLSsteam watches it and the LuaTools plugin rewrites
  it; a symlink into `/nix/store` would break both. On every activation the plugin-owned keys
  (`ManifestPins`, `FakeAppIds`) are carried over from the live file — unless *you* declared them,
  in which case Nix owns them and resets them, which is the point.
- `manageConfig` defaults to `false` so tools like SteaMidra can own the file. Setting any
  `settings` key without it fails evaluation rather than silently doing nothing.

Which fork reads what: upstream SLSsteam reads the wiki keys; slsteam-moon additionally reads
`DisableParentalRestrictions`, `AutoUpdateApps`, `Donate`, `Achievements`,
`AchievementOwnerId(s)`, `PatternCache`, `AsyncProvision`, `MaxManagedApps`, `ManifestPins` and
`LogLevel` (its own 0–6 scale, distinct from the bitwise `LogLevels`). Unknown keys are ignored by
whichever fork doesn't read them.

> **Added games are not in `config.yaml`.** slsteam-moon deprecated `AdditionalApps`; games are
> `<appid>.lua` files in `~/.steam/steam/config/stplug-in/`, and manual appids go in
> `~/.config/SLSsteam/luaappids.yaml`.

---

## netsock

The [steamnetsock-patch](https://github.com/yesyes0649/steamnetsock-patch) multiplayer fix. It is
never injected globally and must not be used with anti-cheat games — it scans and modifies game
memory.

```nix
programs.nix-crab.netsock = {
  enable = true;          # installs ~/.config/SLSsteam/tools/netsock/netsock.so
  games = [ 1966720 ];    # per-game launch option, declaratively
};
```

`games` writes exactly the launch option upstream documents —

```
LD_AUDIT="$HOME/.config/SLSsteam/tools/netsock/netsock.so" %command%
```

— through steam-config-nix, so those games get a wrapper and their launch options field points at
it. Name the app or add other options yourself under `steam.config.apps.<id>`; the definitions
merge.

---

## LuaTools (slsteam-moon + Lumen)

Upstream's LuaTools Millennium plugin is end-of-support and its replacement is Windows-only; the
maintained Linux path is [slsteam-moon](https://github.com/swwayps/slsteam-moon) +
[Lumen](https://github.com/swwayps/lumen) +
[luatools-moon](https://github.com/swwayps/luatools-moon) from the same maintainer.

```nix
programs.nix-crab = {
  slssteam-moon.enable = true;          # the injection
  slssteam = {
    manageConfig = true;
    moon.enable = true;                 # merge base = slsteam-moon's config.yaml
  };
  luatools.enable = true;               # Lumen + plugin + steam wrapper
  # luatools.lumenService = true;       # ...or a user service instead of the wrapper
};
```

`luatools.enable` copies Lumen and the plugin into `~/.local/share/Lumen` (a real directory — both
write at runtime; re-synced only when the release version changes), drops a `steam-run` shim for
Lumen's prebuilt binary, adds `steam-run` and a `lumen` command to PATH, touches
`~/.steam/steam/.cef-enable-remote-debugging` (Steam only exposes the CEF endpoint when that marker
exists — restart Steam after the first switch) and shadows `steam` so launching Steam also brings
Lumen up. With `lumenService = true` the wrapper is dropped and Lumen runs as the `nix-crab-lumen`
user service instead (starts at login, `Restart=on-failure`, Steam launches plain).

> **Do not combine with Millennium.** Millennium takes the CEF endpoint as a pipe
> (`--remote-debugging-pipe`), so no TCP port ever appears and Lumen cannot attach. The assertion
> catches it.

---

## Millennium

```nix
programs.nix-crab = {
  millennium = {
    enable = true;
    plugins = [ "3dc714a7c1b1" ];           # steambrew.app/plugin/<id>
    themes  = [ "1wwKwvHrFuzMs7Kb1Uzu" ];   # or a display name / repo name
  };
};
```

Plugins land in `~/.local/share/millennium/plugins`, themes in `~/.steam/steam/millennium/themes`
(that is where Millennium looks), as real directories with a stamp recording what was installed —
later switches touch nothing and need no network, and removing an ID deletes exactly that addon.
Enable the plugin or pick the theme in Millennium's UI afterwards.

Millennium itself is **fetched from its own GitHub release** (`millennium-<ver>-linux-x86_64.tar.gz`,
seconds instead of a ~7 minute local compile of its C++/TypeScript tree), and the daily sync keeps
that current — including restoring the execute bits the release tarball loses (steamwebhelper
runs Millennium's pressure-vessel shim directly; mode 644 there means the Steam client never
opens its window). Expect a Steam client update to be able to break the hook. Millennium does not touch
game processes, so it is irrelevant to VAC.

---

## ACCELA & SteaMidra

```nix
programs.nix-crab = {
  accela = {
    enable = true;
    config.max_downloads = 16;             # ACCELA's [General] keys, all typed
  };
  steamidra.enable = true;
};
```

**ACCELA** ([Enter The Wired](https://github.com/ciscosweater/enter-the-wired)) is the Qt depot
downloader; its typed `[General]` keys are what make it defer to SLSsteam instead of managing games
itself. `~/.config/Tachibana Labs/ACCELA.conf` is **seeded, not managed** — QSettings rewrites it,
so it is only written when absent. The AppImage runs inside an FHS wrapper with a Qt-clean
environment (its bundled PyQt6 otherwise picks up the session's version-mismatched Qt plugins and
dies).

**SteaMidra** ([Midrags/SFF](https://github.com/Midrags/SFF)) is the account/manifest manager. Its
520 MiB AppImage is *not* fetched by Nix — SFF has no versionless asset URL, so pinning it would
mean a hand-bumped hash per release. The launcher downloads exactly the version the flake input
locked (the newest GitHub tag) into `~/.local/share/SteaMidra/` on first run and executes it
through `appimage-run`; `nix flake update` follows new releases. The desktop entry is owned and
forced, because SteaMidra writes its own (broken on NixOS) entry into the same path. Leave
`slssteam.manageConfig` off if SteaMidra should own `config.yaml`.

---

## Client downgrade

```nix
programs.nix-crab.downgrade.enable = true;
# then:
nix-crab-downgrade
```

Pins the Steam client to headcrab's compatible build: writes the update-blocking `steam.cfg`,
downloads the client manifest and `sources.txt` at runtime (both change every Steam build), fetches
the client files with `dlm`, serves them with `dgsc` on `:1666` and applies them through
`steam -forcesteamupdate -forcepackagedownload -overridepackageurl http://localhost:1666/`.

By default none of this is needed: the client follows Valve's updates on its own, and `steam.cfg`
is only written by this script.

---

## Tooling

```
nix-crab-status          # human-readable diagnostics
nix-crab-status --json   # same data, machine-readable
nix-crab-update          # nix flake update -> rebuild -> status
```

`nix-crab-status` reports the client version and whether updates are blocked, the effective
SLSsteam config (`DisableCloud`, `PlayNotOwnedGames`, `SafeMode`, `ManifestPins`, duplicate-key
warnings), the injection fork actually observed in a running Steam process, the LuaTools game
state (`stplug-in` manifest count, `luaappids.yaml`), the steam-config-nix patcher (installed /
active, apps configured) and the Lumen state (installed, running, CEF endpoint attached).

```json
{
  "steam": {"version": "…", "manifest_note": "", "updates_blocked": false},
  "slssteam": {"config_present": true, "disable_cloud": "true", "play_not_owned": "no",
               "safe_mode": "no", "disable_cloud_duplicates": 1, "manifest_pins": false,
               "netsock_present": true},
  "injection": "slsteam-moon (LuaTools)",
  "games": {"stplug_in_dir": "…", "lua_manifests": 3, "luaappids_yaml": false},
  "steam_config": {"service": "active", "template_unit": false, "configured_apps": 1},
  "luatools": {"installed": true, "plugin_installed": true, "running": false, "cef_port": true}
}
```

---

## Packages

Everything this flake can install is also a package output, and every one of them is the *same*
derivation the option installs. No package output is unfree (SLSsteam is AGPL-3.0); Steam's unfree
license only enters through the options, evaluated against *your* nixpkgs config. Most packages are
simply unpacked from upstream's release assets — `nix build` is a download, not a compile.

| Package | Build / run |
| ------- | ----------- |
| `sls-steam` (upstream's own release: `SLSsteam.so` + `library-inject.so` + config) | `nix build .#sls-steam` |
| `slsteam-moon` (the fork's own release zip) | `nix build .#slsteam-moon` |
| `millennium` (Millennium's own release tarball) | `nix build .#millennium` |
| `lumen`, `luatools` (LuaTools, their own release zips) | `nix build .#lumen` |
| `ticket-grabber`, `schema-grabber` (SLSsteam tools) | `nix build .#ticket-grabber` |
| `netsock` | `nix build .#netsock` |
| `accela` (Qt-clean AppImage launcher) — also `default` | `nix build` |
| `steamidra` (downloads the AppImage on first run) | `nix profile install .#steamidra` |
| `steam-config-patcher` (steam-config-nix's patcher) | `nix build .#steam-config-patcher` |
| `nix-crab-status`, `nix-crab-update`, `nix-crab-downgrade` | `nix run .#nix-crab-status` |

There is deliberately **no "Steam with SLSsteam baked in" package**: injection exists only behind
the option, verbatim as the [upstream wiki](https://github.com/AceSLS/SLSsteam/wiki/Installation)
documents it.

---

## Updating

There are two kinds of update, and the repo tracks both.

**Upstream release binaries.** SLSsteam, Millennium, slsteam-moon, Lumen and LuaTools are consumed
as *their own published artifacts* — never compiled here. Their versions and hashes live in
`upstream.lock.json`, a **generated** file:

```json
"slsteam-moon": {
  "repo": "swwayps/slsteam-moon",
  "version": "v2.9",
  "asset": "slsteam-moon-linux-{ver}-lumen.zip",
  "hash": "sha256-lchHAj7Ba3AtyMdKpRPHXgp/A46ycnJeGaBi4wvseLc="
}
```

`./ci/update-binaries.sh` asks each repository for its newest release, downloads the asset,
verifies it against the `.sha256` that project publishes next to it, and rewrites the file. **CI
runs that every day** (the `sync` job of `.github/workflows/ci.yml`) together with
`nix flake update`, then re-evaluates the whole flake, unpacks every binary and opens a PR when
anything moved — validated again by `nix flake check` on the PR. One daily cycle answers both "is
it still working?" and "is it still newest?", with no binary cache of our own to maintain.

**Git inputs.** The six flake inputs — nixpkgs, Millennium's overlay, steam-config-nix,
enter-the-wired, SteaMidra's tag list, netsock's `releases/latest` — move with
`nix flake update`, and the daily sync runs that too. Locally it is just:

```
nix flake update
sudo nixos-rebuild switch    # applies everything in one go
```

`nix-crab-update` does the same three steps (update → rebuild → status). The Steam client tracks
Valve's releases unless you opt into the downgrade.

---

## CloudRedirect is gone

This revision removes **CloudRedirect entirely**: the upstream hook
([Selectively11/CloudRedirect](https://github.com/Selectively11/CloudRedirect)), the
`cloudredirect-moon` fork, its CLI, the Flatpak it ran in, and with them the `nix-flatpak` input.
The options, packages and `~/.local/share/CloudRedirect/*` links no longer exist.

- Cloud saves for unlocked games stay **off** — already the documented setting without a cloud-save
  hook, and the managed config now writes it for you (`DisableCloud = true`, overridable).
- LuaTools still works without it: game lists come from `stplug-in/` and `luaappids.yaml`.
- `slssteam.extraEnv` remains as the escape hatch for anyone bringing their own preload library.

---

## Upstream

What this flake re-exports or consumes instead of reimplementing:

| Upstream | Re-exported as |
| -------- | -------------- |
| [steam-config-nix](https://github.com/different-name/steam-config-nix) | `steam.config.*` (alias), its NixOS module re-exported |
| [Millennium](https://github.com/SteamClientHomebrew/Millennium) | its own Nix overlay (`millennium-steam`) + release binaries |
| [SLSsteam](https://github.com/AceSLS/SLSsteam) | its own release binaries (`sls-steam`, grabbers) |
| [slsteam-moon](https://github.com/swwayps/slsteam-moon), [Lumen](https://github.com/swwayps/lumen), [luatools-moon](https://github.com/swwayps/luatools-moon) | their release binaries (injection, Lumen, the plugin) |
| [enter-the-wired](https://github.com/ciscosweater/enter-the-wired) | its own AppImage package |

Everything else here — the config merge, the LuaTools install, the add-on installer, the downgrade
wrapper and the two commands — exists because no upstream ships it declaratively.

## Tests

`tests/` is a separate flake that consumes this one (`path:..`, so it always tests the checkout it
sits in — no lock to refresh) and exercises the whole surface:

```bash
cd tests
./test-eval.sh    # eval assertions: the unified steam knob (sugar + passthrough),
                  # user detection, the config alias, the activation snippets, a
                  # proof that home-manager is absent entirely, and every bad* config
                  # must FAIL with the intended assertion message
./test-writer.sh  # the real activation text, run against sandbox homes:
                  # config.yaml merge, plugin keys carried over, netsock, Lumen,
                  # both NixOS-path writers, and extraPkgs landing in the FHS closure
```

Coverage (37 evaluation checks + 41 writer/activation checks):
`nixosConfigurations.{bare,full,moon,steamOnly,steamPkg,steamSugar,steamPassthrough,rawSteamPkg,
rawSteamPkgNixCrabOn,smokeNixos,writerSmoke,writerFake,ambiguousUser,explicitUser,badCombo,
badSteamOff,badSettings,badNetsock}` —
`bare` proves nothing turns itself on and that home-manager is absent entirely, `bad*` must fail
evaluation with the right assertion message, `full` proves `LD_AUDIT` and
`MILLENNIUM_RUNTIME_PATH` end up on the same Steam package, and `rawSteamPkg*` prove a raw
`programs.steam.package` beats the `extraPkgs` baseline instead of conflicting with it. The writer suite extracts the real
`system.activationScripts."nix-crab-*"` text and runs it through a driver that mirrors NixOS'
activate script (same `ERR` trap, same nonzero-exit contract), builds the baseline-laden FHS
closure (`gamemode` in `steamOnly` — nobody set it there) and asserts Millennium's `pvs64`/`luavm`
objects are executable (the release tarball ships them 644; without +x steamwebhelper can't
exec the pressure-vessel shim and the Steam client never opens).

CI is deliberately tiny. Everything heavy comes from upstream releases, so there is nothing to
compile and nothing worth caching — a run is a Nix install plus an evaluation, **~30 seconds**, and
no Actions cache is used or created:

- **every push/PR** → `nix flake check` + a formatting gate;
- **pull requests** → the full test suite above as well, before anything merges;
- **daily** → the `sync` job (described under [Updating](#updating)): newest upstream releases +
  `flake.lock`, verified, delivered as a PR.

## Caveats

- This is an independent reimplementation of the h3adcr-b workflow for NixOS — not affiliated with
  h3adcr-b, SLSsteam, Millennium, LuaTools or SteaMidra.
- Downloading and running third-party binaries (the SLSsteam, Millennium, slsteam-moon and Lumen
  releases, `dgsc`, `dlm`, SteaMidra) carries the same risk as the imperative tooling it
  reproduces. SLSsteam injects into a client that runs games with your credentials; use a
  throwaway account if that matters to you.
- `SafeMode` is not set by this flake: it is meant for Steam Deck gamemode and can disable SLSsteam
  on desktop after a client update. `nix-crab-status` prints the value in effect.
- User files are written during `nixos-rebuild switch`: the activation script runs as root, each
  `nix-crab-*` snippet creates what it needs in the chosen user's home and hands it over with
  `chown`. A failing snippet is recorded (the switch still finishes) and retried next time.
- If you run Home Manager *yourself* for your own dotfiles, that stays your business — nix-crab
  neither imports nor requires it, and none of its options live under `home-manager.users`.

## License

MIT — see [LICENSE](LICENSE). Covers this flake's own Nix code only; the upstream projects keep
their own licenses (SLSsteam and slsteam-moon are AGPL-3.0, steam-config-nix is GPL-3.0).

## Credits

An **updated continuation of [nix-crab](https://github.com/ItszFinn/nix-crab)** by **ItszFinn** —
the injection design, the status/update tooling and the Millennium and LuaTools stacks are their
work, under the original MIT license. nix-crab went quiet in September 2026 with broken URLs and
stale pins; this continuation refreshes it, removes CloudRedirect, adds steam-config-nix and moves
the whole home side under plain NixOS config. All credit for the original goes to them.

The projects this flake wires up — and the people behind them:

- **[SLSsteam](https://github.com/AceSLS/SLSsteam)** (AceSLS) — the injection itself, its
  [wiki](https://github.com/AceSLS/SLSsteam/wiki), and the NixOS install method by
  [DeveloperMikey](https://github.com/DeveloperMikey).
- **[slsteam-moon](https://github.com/swwayps/slsteam-moon), [Lumen](https://github.com/swwayps/lumen)
  and [luatools-moon](https://github.com/swwayps/luatools-moon)** (swwayps) — keeping the LuaTools
  workflow alive on Linux.
- **[steam-config-nix](https://github.com/different-name/steam-config-nix)** — declarative Steam
  configuration, the piece that makes per-game behaviour expressible here at all.
- **[Millennium](https://github.com/SteamClientHomebrew/Millennium)** (Steam Homebrew) — client
  themes and plugins, and shipping a Nix package for it.
- **[steamnetsock-patch](https://github.com/yesyes0649/steamnetsock-patch)** (yesyes0649) — the
  multiplayer fix.
- **[ACCELA / Enter The Wired](https://github.com/ciscosweater/enter-the-wired)** (ciscosweater) —
  the depot downloader.
- **[SteaMidra / SFF](https://github.com/Midrags/SFF)** (Midrags) — account and manifest management.
- **[ItszFinn](https://github.com/ItszFinn)** — nix-crab, the project this continues.

Maintained by a young NixOS enthusiast with a lot of help from AI assistants.
