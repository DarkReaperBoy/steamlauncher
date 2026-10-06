# nix-crab (updated)

> Updated continuation of [ItszFinn/nix-crab](https://github.com/ItszFinn/nix-crab) (upstream inactive
> since 2026-09): refreshed inputs, the dead `dgsc`/`dlm` and stale-hash URLs fixed, GCC 16 build fix
> for slsteam-moon, current Millennium/NixOS module APIs, and the SLSsteam config reworked from a
> typed-module-plus-hardcoded-defaults scheme into **typed per-key options** (see
> [SLSsteam configuration](#slssteam-configuration)).
>
> Every piece of software is both a **package** (`nix build .#<name>`) and an **option** (default
> **off** — import the module, then enable what you want). Nothing installs itself.

Declarative [h3adcr-b](https://github.com/Deadboy666/h3adcr-b/)-equivalent for NixOS.
Installs and wires up [SLSsteam](https://github.com/AceSLS/SLSsteam) (play unlocked/not-owned games),
[CloudRedirect](https://github.com/Selectively11/CloudRedirect) (cloud saves for non-owned/"lua" games)
and the optional [steamnetsock-patch](https://github.com/yesyes0649/steamnetsock-patch) (multiplayer fix),
plus a client-downgrade tool — all from a single flake.

On top of that base, two client-side stacks are available, and they are mutually exclusive:
[Millennium](#millennium-optional) for themes and plugins, or
[LuaTools](#luatools-slsteam-moon--lumen) via slsteam-moon + Lumen. Both want Steam's CEF debugging
endpoint.

## Features

- **SLSsteam** injected into the native Steam package via `LD_AUDIT` (`programs.steam` override) — no
  runtime patching of `steam.sh`.
- **CloudRedirect** installed as a Flatpak (declaratively via `nix-flatpak`) and injected with
  `LD_PRELOAD`.
- **netsock** (steamnetsock-patch) placed at `~/.config/SLSsteam/tools/netsock/netsock.so` for use as a
  per-game launch option.
- **CloudRedirect CLI** (`cloud_redirect_cli`) available on `PATH` and at
  `~/.local/share/CloudRedirect/cloud_redirect_lib`.
- **SteaMidra (SFF)** (optional) — .NET 9 AppImage for managing Steam accounts, tokens and configuration.
- **ACCELA** (optional) — Qt depot-downloader GUI from the Enter The Wired bundle, configured to hand
  its games to SLSsteam.
- **Millennium** (optional) — Steam client modding framework, applied as a `pkgs.steam` overlay so it
  stacks with the SLSsteam injection instead of fighting it. Plugins and themes install declaratively
  by store ID.
- **slsteam-moon + LuaTools** (optional) — the alternative injection: a SLSsteam fork with a native
  Lua manifest importer, built from source, plus Lumen and the LuaTools plugin under
  `~/.local/share/Lumen`. Replaces Millennium, not additive to it.
- **Client downgrade** (`nix-crab-downgrade`) — pins the Steam client to headcrab's compatible build
  using `dlm` + `dgsc` + `-overridepackageurl`.
- **`nix-crab-status`** — diagnostic command showing client version, SLSsteam config, netsock,
  CloudRedirect status (including which hook is wired up), the active injection fork and
  LuaTools/Lumen state. `--json` prints the same as machine-readable JSON.
- **`nix-crab-update`** — one-command maintenance: `nix flake update`, rebuild through
  `nh`/`nixos-rebuild` + `home-manager`, then prints the fresh `nix-crab-status`.
- **Zero-maintenance updates** — by default the Steam client is _not_ frozen: it follows updates on its
  own, and SLSsteam/CloudRedirect/netsock can be updated instantly by running `nix flake update` in your own configuration.

## Packages

Everything this flake can install, as a `packages` output — no module needed, nothing enabled by
default:

| Package                  | What it is                                                              | Build / run                                   |
| ------------------------ | ----------------------------------------------------------------------- | --------------------------------------------- |
| `accela` *               | ACCELA depot downloader (Qt-clean AppImage launcher)                    | `nix build .#accela`                          |
| `sls-steam`              | `SLSsteam.so` + `library-inject.so` — **upstream's own package output** from [AceSLS/SLSsteam](https://github.com/AceSLS/SLSsteam/wiki/Installation) | `nix build .#sls-steam` |
| `slsteam-moon`           | the LuaTools fork's `.so` pair, compiled from source (32-bit)           | `nix build .#slsteam-moon`                    |
| `cloudredirect`          | upstream `cloud_redirect.so` (cloud-saves hook)                         | `nix build .#cloudredirect`                   |
| `cloudredirect-moon`     | LuaTools hook (also scans `stplug-in`/`luaappids.yaml`)                 | `nix build .#cloudredirect-moon`              |
| `cloudredirect-cli`      | `cloud_redirect_cli`                                                    | `nix build .#cloudredirect-cli`               |
| `netsock`                | multiplayer-fix `.so` (per-game `LD_AUDIT`)                             | `nix build .#netsock`                         |
| `steamidra`              | SteaMidra (SFF) launcher (downloads the AppImage on first run)          | `nix profile install .#steamidra`             |
| `lumen`                  | LuaTools backend dist                                                   | `nix build .#lumen`                           |
| `luatools`               | LuaTools plugin dist                                                    | `nix build .#luatools`                        |
| `ticket-grabber`         | SLSsteam ticket grabber                                                 | `nix build .#ticket-grabber`                  |
| `schema-grabber`         | SLSsteam schema grabber                                                 | `nix build .#schema-grabber`                  |
| `nix-crab-status`        | diagnostics (`--json` for machines)                                     | `nix run .#nix-crab-status`                   |
| `nix-crab-update`        | `flake update` + rebuild + status                                       | `nix run .#nix-crab-update`                   |
| `nix-crab-downgrade`     | pin the Steam client to headcrab's build                                | `nix run .#nix-crab-downgrade`                |
| `default`                | = `accela`                                                              | `nix build`                                   |

\* no package output is unfree — SLSsteam is AGPL-3.0. Steam's unfree license only enters the
picture through the module option (`programs.nix-crab.slssteam.enable`), evaluated against *your*
nixpkgs config where you already deal with it (same requirement as upstream's own wiki snippet).

**There is deliberately no "Steam with SLSsteam baked in" package.** Injection happens only when
you enable the option — canonical to the [upstream wiki's NixOS
instructions](https://github.com/AceSLS/SLSsteam/wiki/Installation): `programs.steam.package =
pkgs.steam.override { extraEnv.LD_AUDIT = "…/library-inject.so:…/SLSsteam.so"; }`, which is
exactly what `slssteam.enable` writes.

All of these are the *same derivations* the module options install: every feature lives in one
`modules/<feature>.nix` **unit** (`{ inputs }: { module, mk* }`) — `flake.nix` instantiates it once
and takes `.module` for the module outputs and `.mk*` for the packages. So `nix build
.#nix-crab-status` and enabling `tools.enable` give you bit-identical bits.

## Options

Everything is **off by default**. Import the module, then enable what you want:

```nix
# NixOS
nixosModules.default  # programs.nix-crab.*
# Home Manager
homeModules.default   # programs.nix-crab.*
```

### `nixosModules.default`

| Option                                   | Default | What it does |
| ---------------------------------------- | ------- | ------------ |
| `programs.nix-crab.slssteam.enable`      | off     | Inject upstream SLSsteam into the native Steam package (`LD_AUDIT` via `programs.steam` override). Implies `programs.steam.enable`. |
| `programs.nix-crab.slssteam.extraEnv`    | `{}`    | Extra env vars merged into the Steam override (CloudRedirect's `LD_PRELOAD` uses this). |
| `programs.nix-crab.slssteam-moon.enable` | off     | Inject [slsteam-moon](https://github.com/swwayps/slsteam-moon) (fork with Lua manifest importer) instead. Built from source; takes precedence over `slssteam.enable`. |
| `programs.nix-crab.cloudredirect.enable` | off     | Enable CloudRedirect: Flatpak service + `LD_PRELOAD` to the pinned hook. Asserts an injection is also enabled. |
| `programs.nix-crab.cloudredirect.moon.enable` | off | Use the [cloudredirect-moon](https://github.com/swwayps/cloudredirect-moon) hook (scans `stplug-in`/`luaappids.yaml`). Opt-in, LuaTools stack only. |
| `programs.nix-crab.millennium.enable`    | off     | Apply the [Millennium](https://github.com/SteamClientHomebrew/Millennium) overlay and use `millennium-steam` as the Steam base (themes/plugins). Asserts mutual exclusion with `slssteam-moon`. |
| `programs.nix-crab.downgrade.enable`     | off     | Add `nix-crab-downgrade` to `environment.systemPackages`. |
| `programs.nix-crab.downgrade.package`    | built-in | Override the downgrade wrapper script. |

### `homeModules.default`

| Option                                    | Default | What it does |
| ----------------------------------------- | ------- | ------------ |
| `programs.nix-crab.slssteam.manageConfig` | off     | Nix owns `~/.config/SLSsteam/config.yaml` (fork default ⊕ `settings`). Off by default so SteaMidra & friends can edit it. |
| `programs.nix-crab.slssteam.settings.*`   | all `null` | **Typed SLSsteam config** — see [SLSsteam configuration](#slssteam-configuration). `null` = don't write, keep the fork's default. |
| `programs.nix-crab.slssteam.moon.enable`  | off     | Merge base = slsteam-moon's `res/config.yaml` instead of upstream's. Set alongside the NixOS `slssteam-moon.enable`. |
| `programs.nix-crab.cloudredirect.enable`  | off     | CloudRedirect user side: user Flatpak (flathub + cloudredirect remotes), the `.so`/CLI links its checks `stat`, `cloud_redirect_cli` on `PATH`. Set alongside the NixOS option. |
| `programs.nix-crab.cloudredirect.moon.enable` | off | Point the `~/.local/share/CloudRedirect/cloud_redirect.so` link at the moon hook. Must match the NixOS option. |
| `programs.nix-crab.netsock.enable`        | off     | Install netsock to `~/.config/SLSsteam/tools/netsock/netsock.so` for per-game launch options. |
| `programs.nix-crab.tools.enable`          | off     | Put `nix-crab-status` and `nix-crab-update` on `PATH`. |
| `programs.nix-crab.accela.enable`         | off     | ACCELA desktop app (icon, desktop entry, seeded `ACCELA.conf`). |
| `programs.nix-crab.accela.config.*`       | see below | ACCELA's `[General]` keys as typed options — see [ACCELA configuration](#accela-configuration). |
| `programs.nix-crab.steamidra.enable`      | off     | SteaMidra (SFF) desktop app (.NET 9 runtime + launcher + forced desktop entry). |
| `programs.nix-crab.luatools.enable`       | off     | LuaTools home side: Lumen + plugin into `~/.local/share/Lumen`, `lumen` cmd, `steam` shadow-wrapper that starts Lumen, `steam-run` on `PATH`. Needs NixOS `slssteam-moon.enable` + home `slssteam.moon.enable` (asserted). |
| `programs.nix-crab.luatools.lumenService` | off     | Run Lumen as a systemd user service (`nix-crab-lumen`) instead of the `steam` wrapper. |
| `programs.nix-crab.millennium.plugins`    | `[]`    | Millennium plugin IDs from [steambrew.app/plugins](https://steambrew.app/plugins), installed on activation. |
| `programs.nix-crab.millennium.themes`     | `[]`    | Millennium theme IDs/names from [steambrew.app/themes](https://steambrew.app/themes). |

Assertions (eval-time errors, not runtime surprises):

- `settings` set without `manageConfig` → fails with the fix in the message.
- `millennium` + `slssteam-moon` together → fails (both want Steam's CEF endpoint).
- `cloudredirect` without any injection → fails (nowhere to `LD_PRELOAD`).
- `luatools` + `manageConfig` without `slssteam.moon` → fails (wrong merge base).

## SLSsteam configuration

`programs.nix-crab.slssteam.settings` mirrors upstream's YAML config file as **typed Nix options** —
the YAML file *is* the options file. Every option maps 1:1 to a `config.yaml` key, with upstream's
type and meaning:

- **Full reference:** [SLSsteam wiki → Configuration](https://github.com/AceSLS/SLSsteam/wiki/Configuration)
  (keys, types, bitflag values, special AppIds like `LaunchOptions`' 4294967294/4294967295).
- **The defaults live upstream:** each fork's own `res/config.yaml`
  ([SLSsteam](https://github.com/AceSLS/SLSsteam/blob/main/res/config.yaml),
  [slsteam-moon](https://github.com/swwayps/slsteam-moon/blob/main/res/config.yaml)) — that file is
  the merge base, comments included.

```nix
programs.nix-crab.slssteam = {
  manageConfig = true;              # opt in: Nix owns ~/.config/SLSsteam/config.yaml
  moon.enable = false;              # true = merge over slsteam-moon's defaults
  settings = {
    PlayNotOwnedGames = true;       # bool
    DisableCloud = false;           # needed for CloudRedirect to sync
    AppIds = [ 440 730 ];           # listOf int
    SmartTickets = 3;               # bitflag int (1 = SteamDRM, 2 = Denuvo)
    IdleStatus = { AppId = 480; Title = "grinding"; };  # submodule
    extraSettings.SomeNewKey = 42;  # freeform escape hatch for keys not typed yet
  };
};
```

How the file is produced:

- **Every option defaults to `null` = "not written"** — unset keeps the fork's documented default.
  Nothing here hardcodes an opinionated value; upstream owns the defaults.
- With **no settings set** and `manageConfig = true`, the fork's `res/config.yaml` is used
  **verbatim** (byte-identical, comments intact).
- With settings set, `yq-go` deep-merges your overlay over that base: your values win, everything
  else (and all comments) survives. Because the base contains *every key the fork's C++ reads*, the
  generated file never triggers the "Config loading issues" notification on Steam start — which is
  what upstream's typed-module-plus-hardcoded-defaults scheme got wrong (it bit-rotted: upstream
  deleted `PlayNotOwnedGames` from the C++ while the module kept writing it).
- The key set tracks upstream automatically: when SLSsteam adds a config key, `nix flake update`
  picks it up (the base comes from the input). Until a key is typed here, `extraSettings` accepts
  it as freeform YAML.
- `manageConfig` defaults to `false`: the file stays unmanaged so SteaMidra and friends can edit
  it. Setting any `settings` key without `manageConfig` **fails evaluation** with a pointer to the
  fix, instead of silently dropping your values.

Which side reads what: upstream SLSsteam reads the wiki keys; slsteam-moon additionally reads
`DisableParentalRestrictions`, `AutoUpdateApps`, `Donate`, `Achievements`, `PatternCache`,
`AsyncProvision`, `MaxManagedApps`, `LogLevel` (its own 0-6 scale, distinct from upstream's bitwise
`LogLevels`) — all typed below. Unknown keys are ignored by whichever fork doesn't read them, so
one config serves both.

## ACCELA configuration

`programs.nix-crab.accela.config` exposes ACCELA's `[General]` INI keys — these are what make
ACCELA hand games to SLSsteam instead of managing them itself (they match what enter-the-wired's
own `accela` script forces):

| Option | Default | Meaning |
| ------ | ------- | ------- |
| `auto_skip_single_choice` | `true` | Skip dialogs that only offer one choice. |
| `library_mode` | `true` | Work against the Steam library. |
| `max_downloads` | `16` | Parallel depot downloads. |
| `sls_config_management` | `true` | Hand config management to SLSsteam. |
| `slssteam_mode` | `true` | Hand games to SLSsteam instead of standalone installs. |
| `use_steamless` | `true` | Steamless (no-Steam) mode. |

The file is **seeded, not managed**: `~/.config/Tachibana Labs/ACCELA.conf` is only written when it
does not exist (QSettings rewrites it, so a store symlink would break it) — same reasoning as
`slssteam.manageConfig`. Change the options only if you have not run ACCELA yet, or edit the file
directly afterwards.

## Installation


Add the flake as an input:

```nix
{
  inputs = {
    nix-crab.url = "github:YOUR_GITHUB_USER/steam-launcher";  # or path:/home/you/steam-launcher
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
}
```

### NixOS module

```nix
modules = [
  nix-crab.nixosModules.default
  {
    programs.nix-crab.slssteam.enable = true;
    programs.nix-crab.cloudredirect.enable = true;
    # programs.nix-crab.millennium.enable = true;  # optional
    # programs.nix-crab.downgrade.enable = true;   # optional
  }
];
```

### Home Manager module

```nix
modules = [
  nix-crab.homeModules.default
];
```

Both modules must be imported: the NixOS module injects SLSsteam/CloudRedirect into Steam, the home
module provides the SLSsteam config (`~/.config/SLSsteam/config.yaml`), netsock, the CloudRedirect
CLI and installs `org.cloudredirect.CloudRedirect` as a user Flatpak. Import both in one switch so
they stay in sync.

## Upstream status

Checked 2026-10-06 (GitHub `pushed_at` on every wired repo) — the flake follows **all-live**
upstreams. This matters because the previous maintainer went quiet:

| Repository | Last push | Status | How this flake tracks it |
| ---------- | --------- | ------ | ------------------------ |
| [ItszFinn/nix-crab](https://github.com/ItszFinn/nix-crab) (the original) | 2026-09-05 (main) | **inactive** — only its lock-bot branch still pushes | forked here; all fixes below are ours |
| [AceSLS/SLSsteam](https://github.com/AceSLS/SLSsteam) | 2026-10-04 | active | git input → `nix flake update` |
| [Selectively11/CloudRedirect](https://github.com/Selectively11/CloudRedirect) | 2026-10-04 (v2.6.6) | active | `releases/latest/download/…` → newest release on update |
| [SteamClientHomebrew/Millennium](https://github.com/SteamClientHomebrew/Millennium) | 2026-10-04 | active | git input, `nixpkgs` follows this flake |
| [swwayps/slsteam-moon](https://github.com/swwayps/slsteam-moon) | 2026-09-29 | active | git input |
| [swwayps/luatools-moon](https://github.com/swwayps/luatools-moon) | 2026-09-29 | active | git input |
| [Deadboy666/h3adcr-b-modul3s](https://github.com/Deadboy666/h3adcr-b-modul3s) | 2026-09-28 | active (mid-migration: `dgsc`/`dlm` deleted from `main`) | binaries pinned to the last commit that has them; `sources.txt` fetched at runtime |
| [gmodena/nix-flatpak](https://github.com/gmodena/nix-flatpak) | 2026-09-26 | active | git input |
| [swwayps/lumen](https://github.com/swwayps/lumen) | 2026-09-21 | active | git input |
| [swwayps/cloudredirect-moon](https://github.com/swwayps/cloudredirect-moon) | 2026-09-19 | active | git input |
| [yesyes0649/steamnetsock-patch](https://github.com/yesyes0649/steamnetsock-patch) | 2026-09-14 | active | `releases/latest/download/fix.so` |
| [ciscosweater/enter-the-wired](https://github.com/ciscosweater/enter-the-wired) | 2026-09-04 | active | git input (ACCELA) |
| [Midrags/SFF](https://github.com/Midrags/SFF) (SteaMidra) | 2026-08-21 (v6.6.6) | active | `/tags` list → newest tag on update |

**Getting the latest upstream automatically:**

- Git inputs (SLSsteam, moon, Lumen, …) and `releases/latest/download` file inputs (CloudRedirect,
  netsock) re-resolve on `nix flake update` — and this repo runs the
  [update-flake-lock](https://github.com/DeterminateSystems/update-flake-lock) GitHub Action
  (weekly + manual), which opens a PR refreshed `flake.lock` validated by `nix flake check` in CI.
  Locally: `nix-crab-update` does update → rebuild → status in one command.
- The Steam client itself follows Valve's updates by default (`steam.cfg` only written by the
  opt-in downgrade).
- Config keys track upstream because the merge base is the fork's own `res/config.yaml` from the
  locked input — no hardcoded key list to go stale.

## Updating

```
nix flake update
sudo nixos-rebuild switch   # or: home-manager switch
```

This repository also runs the [update-flake-lock](https://github.com/DeterminateSystems/update-flake-lock)
GitHub Action (weekly + manual dispatch): it opens a pull request with a refreshed `flake.lock`,
which CI then validates with `nix flake check` before merge. If you host your own copy, the same
action keeps the `nix-crab` input current on your side.

That is all. SLSsteam, CloudRedirect, netsock and the CloudRedirect CLI all track their upstream
releases through the locked inputs. The Steam client updates itself on next launch.

> **Note:** If a Steam client update briefly breaks SLSsteam, the SLSsteam project usually fixes it
> quickly — the next `nix flake update` picks the fix up. `SafeMode` is not set by this flake;
> if you turn it on yourself, be aware it is meant for Steam Deck gamemode and can wrongly disable
> SLSsteam on desktop. `nix-crab-status` prints the value in effect.

## CloudRedirect app status

The app's "SLSsteam" row is a prerequisite check for the imperative h3adcr-b layout: it stats
`~/.local/share/SLSsteam/SLSsteam.so`. Nix keeps SLSsteam in the store, so the home module links it
to that path and grants the Flatpak `/nix/store:ro` (otherwise the symlink dangles inside the
sandbox) — the app then shows **"SLSsteam: Installed"**.

The CloudRedirect row works the same way: the app's deploy check stats
`~/.local/share/CloudRedirect/cloud_redirect.so` and otherwise reports **"failed to deploy"**. The
home module links that path to the pinned flake input — the same `.so` that
`modules/cloudredirect.nix` puts in `LD_PRELOAD`, so there is only ever one library.

What the app's own "deploy" would do beyond that — patching `steam.sh` — this flake does not need;
injection comes from `LD_PRELOAD`. Verify it with `DoInit: SUCCESS` in
`~/.config/CloudRedirect/cr_debug.log`. Don't press deploy in the app: the linked `.so` is
read-only in the store, so the app cannot write over it.

CloudRedirect only syncs if `DisableCloud: no` is set in `~/.config/SLSsteam/config.yaml`. Careful
with duplicate keys: SLSsteam's yaml-cpp lets the **last** occurrence win, and SteaMidra appends a
second flat key block to the file — so a `DisableCloud: no` at the top can be silently overridden by
a `DisableCloud: yes` further down. `nix-crab-status` reads the last occurrence and warns about
duplicates.

## Client downgrade (optional)

If you want to pin the Steam client to headcrab's compatible build instead of following updates:

```nix
programs.nix-crab.downgrade.enable = true;
```

Then run:

```
nix-crab-downgrade
```

This mirrors headcrab's flow: it writes the update-blocking `steam.cfg`, downloads the client
manifest, fetches the pinned client files with `dlm`, serves them with `dgsc` on `:1666` and applies
them via `steam -forcesteamupdate -forcepackagedownload -overridepackageurl http://localhost:1666/`.

Two upstream-rot fixes live here:

- **`dgsc`/`dlm` are pinned to a commit, not `refs/heads/main`** — upstream deleted both binaries
  from `main` on 2026-09-28 (mid-migration), so the old URLs 404'd. The commit pin is byte-identical
  to what was previously hash-pinned.
- **The manifest and `sources.txt` are fetched at runtime**, like `headcrab.sh` itself does. They
  change with every Steam build, so pinning them as `fetchurl` hashes (the old approach) broke the
  *build* on the next client bump — both pinned hashes had already gone stale. `sources.txt` is
  regenerated from the manifest upstream, so latest-of-both is the consistent pair.

> The downgrade is inherently pinned to a specific Steam build. Only use it if you explicitly want
> to freeze the client.

## netsock (multiplayer fix)

netsock fixes multiplayer in a few games that use SteamNetworkingSockets with SLSsteam's
`FakeAppIds`. It is **not** injected globally — set it as a **per-game launch option** in Steam:

```
LD_AUDIT="$HOME/.config/SLSsteam/tools/netsock/netsock.so" %command%
```

> **Never use netsock with anti-cheat games** — it scans and modifies game memory.

## nix-crab-status

```
nix-crab-status
```

Prints the Steam client version, SLSsteam config values, netsock presence, CloudRedirect status
(Flatpak + CLI), whether client updates are blocked, the injection fork observed in a running
Steam (`slsteam-moon` vs upstream SLSsteam) and the LuaTools/Lumen state (installed, plugin,
running, CEF endpoint attached). The CloudRedirect `Hook:` line reports which `cloud_redirect.so`
is wired up (upstream vs moon) by resolving the `~/.local/share` link — the same choice the
injection uses, so it shows what the game list scanner actually reads.

`--json` emits the same data as one JSON object:

```json
{
  "steam": {"version": "...", "manifest_note": "...", "updates_blocked": false},
  "slssteam": {"config_present": true, "disable_cloud": "no", "play_not_owned": "yes",
               "safe_mode": "no", "disable_cloud_duplicates": 2, "netsock_present": true},
  "injection": "slsteam-moon (LuaTools)",
  "games": {"stplug_in_dir": "/home/you/.steam/steam/config/stplug-in",
            "lua_manifests": 3, "luaappids_yaml": false},
  "cloudredirect": {"enabled": true, "hook": "moon (LuaTools)",
                    "cli_present": true, "flatpak_installed": true},
  "luatools": {"installed": true, "plugin_installed": true, "running": true, "cef_port": true}
}
```

`stplug_in_dir` and `manifest_note` are empty strings when not applicable.

## nix-crab-update

```
nix-crab-update
```

Runs `nix flake update` in the current directory, then switches with whatever is installed — `nh os
switch` + `nh home switch` if `nh` is on `PATH`, otherwise `sudo nixos-rebuild switch --flake .`
plus `home-manager switch --flake .` — and finally prints `nix-crab-status` so you see the updated
versions in the same breath. Run it from your configuration repo (the one that imports
`nix-crab`); it exits before touching anything if there is no `flake.nix` in `$PWD`. It needs the
home module for the final status line; without it the rest still runs.

## SteaMidra (optional GUI)

If you want to use [SteaMidra (SFF)](https://github.com/Midrags/SFF) to manage Steam accounts, tokens and settings:

```nix
programs.nix-crab.steamidra.enable = true;
```

The release version comes from the `steamidra` flake input (GitHub's tag list), but the 520 MiB
AppImage is _not_ fetched by Nix: SFF has no versionless asset URL, so a Nix fetch would need a
hand-bumped SRI hash for every release. Instead the `steamidra` launcher downloads and unpacks
exactly the locked version into `~/.local/share/SteaMidra/` on first run (with a desktop
notification), then runs it through `appimage-run` with QtWebEngine sandboxing disabled. After
`nix flake update` the next launch picks up the new version. The desktop icon appears after that
first run. If you use SteaMidra alongside Nix-managed config, set `programs.nix-crab.slssteam.manageConfig = true;` or leave it unmanaged (`false`, the default) so SteaMidra can update `config.yaml` directly.

## Millennium (optional)

[Millennium](https://github.com/SteamClientHomebrew/Millennium) adds themes and plugins to the Steam
client:

```nix
programs.nix-crab.millennium.enable = true;
```

Millennium's own overlay is applied (it defines `millennium` and `millennium-steam`); remapping
`pkgs.steam = millennium-steam` on top of it — what older versions of this flake did — would now
recurse, because Millennium's overlay resolves steam.nix's `steam` argument from the final package
set. Instead `modules/slssteam.nix` takes `millennium-steam` as the *override base* whenever
`millennium.enable` is on, so a single `programs.steam.package` definition carries everything:
re-overriding re-enters Millennium's steam.nix, whose `extraEnv // millenniumEnv` merge keeps
`MILLENNIUM_RUNTIME_PATH` alongside `LD_AUDIT` (SLSsteam) and `LD_PRELOAD` (CloudRedirect).

`millennium.enable` on its own also works now (it enables `programs.steam` with the Millennium
package); combine with `slssteam.enable` for the injection.

Two things to expect:

- **No binary cache.** Upstream publishes no substituter, so Millennium is compiled locally — about
  7 minutes for the 32- and 64-bit C++ trees on a 4-core laptop. The first build also pulls a large
  toolchain (rustc, gcc, cmake, bun) and the pinned second nixpkgs, so expect a few GB of downloads
  once; later rebuilds only recompile the three Millennium derivations.
- **The `millennium` input follows this flake's `nixpkgs`** (upstream made `inputs.nixpkgs`
  followable in PR #919). The separate `nixpkgs-bun` pin is kept — upstream warns the bun FOD hash
  depends on the exact bun version and must not follow another nixpkgs.

### Plugins and themes

Both are named by the `id` in their store URL — `https://steambrew.app/plugin/3dc714a7c1b1`,
`https://steambrew.app/theme/1wwKwvHrFuzMs7Kb1Uzu` (the store's card menu copies it for you). Themes
also accept their display name or GitHub repo name, whichever is at hand:

```nix
programs.nix-crab.millennium = {
  plugins = [ "3dc714a7c1b1" ];
  themes  = [ "1wwKwvHrFuzMs7Kb1Uzu" ];  # or "Adwaita"
};
```

On activation each entry is resolved against the store index (`/api/v1/plugins` for plugins,
`/api/v2` for themes) and unpacked where Millennium looks for it. Note that those are two different
places on Linux: plugins go to `~/.local/share/millennium/plugins` (its `MILLENNIUM__PLUGINS_PATH`),
themes to `~/.steam/steam/millennium/themes` (its internal `get_millennium_path()`). A stamp in
`~/.local/share/millennium/.nix-crab/` records what was installed, so later switches touch nothing and
hit no network unless you add an entry. Themes additionally get the `metadata.json` (owner, repo,
commit) that Millennium writes itself, so its updater knows what is on disk.

Installing is all this does. Enable the plugin, or pick the theme, once in Millennium's UI afterwards
— both live in a `config.json` that Millennium rewrites, so this flake stays out of it. Millennium
scans these folders at client startup, so restart Steam before looking for a fresh addon.

Take an entry out of the list and the next switch deletes its folder again. Only stamped addons are
touched, so whatever you installed yourself through Millennium's UI stays where it is. The active
theme is not reset — if you remove the theme you are currently using, pick another one in the UI.

Downloaded at activation, not with `fetchzip`: both stores serve an addon's newest commit, so a pinned
hash would break on every upstream release. They also land as real directories rather than store
symlinks, because Millennium writes into these folders.

### Risks and limits

Millennium loads by symlinking its bootstrap over `libXtst.so.6` in `~/.local/share/Steam/ubuntu12_*`.
It does not touch game processes, so it is irrelevant to VAC — but a Steam client update can break the
hook, and untrusted third-party plugins run unsandboxed with your user's rights. Millennium also cannot
be combined with the LuaTools stack (`slssteam-moon.enable` + `luatools.enable`) — both want Steam's
CEF debugging endpoint; see the LuaTools section below.

## LuaTools (slsteam-moon + Lumen)

Upstream's LuaTools Millennium plugin is end-of-support and its new app is Windows-only. The maintained
Linux path is the [slsteam-moon](https://github.com/swwayps/slsteam-moon) stack from the same maintainer:
a SLSsteam fork with a native Lua-manifest importer, plus [Lumen](https://github.com/swwayps/lumen) (a
static Lua backend) and the LuaTools plugin port.

Upstream SLSsteam stays the default. `slssteam-moon.enable` swaps the Steam injection to slsteam-moon
(which self-injects via `LD_AUDIT`, exactly like `slssteam.enable`):

```nix
programs.nix-crab.slssteam-moon.enable = true;
```

The LuaTools frontend is separate: the home-module `luatools.enable` installs Lumen + the plugin into
`~/.local/share/Lumen` and provides the `lumen` command. It does **not** switch the injection — set
`slssteam-moon.enable` on the NixOS side for that (Lumen's UI drives slsteam-moon's Lua manifest
importer, so upstream SLSsteam won't do):

```nix
# NixOS module — inject slsteam-moon instead of upstream SLSsteam:
programs.nix-crab.slssteam-moon.enable = true;
# NixOS module — cloud saves for LuaTools games need the moon hook (opt-in).
# `moon` only picks the variant; CloudRedirect itself still has to be enabled:
programs.nix-crab.cloudredirect.enable = true;
programs.nix-crab.cloudredirect.moon.enable = true;

# home module — installs Lumen + the plugin into ~/.local/share/Lumen:
programs.nix-crab.luatools.enable = true;
# home module — keep the CloudRedirect app status on the same hook:
programs.nix-crab.cloudredirect.moon.enable = true;
```

Enabling `luatools` also touches `~/.steam/steam/.cef-enable-remote-debugging` on activation — Steam
only exposes the endpoint when that marker exists, and it is read at client startup, so restart Steam
after the first switch.

Lumen and the plugin are pinned by git rev, not the versionless `releases/latest` URLs (those change
content on every release and would break the lock's narHash).

With `luatools.enable` set, launching Steam starts Lumen automatically: the module shadows the
`steam` command with a wrapper that starts Steam, waits for slsteam-moon to publish its CEF
remote-debugging port to `~/.local/share/Lumen/cef_port` (a free loopback port, rewritten from
Steam's hard-coded 8080), then runs Lumen against it — the binary runs through `steam-run` on NixOS.
This covers both the `steam` command and Steam's desktop entry (both resolve the `steam` binary on
`PATH`). The `lumen` command remains for attaching Lumen to an already-running Steam. slsteam-moon
reads Lua manifests from `~/.steam/steam/config/stplug-in/`.

If you prefer Lumen as a managed service instead of the `steam`-wrapper sidecar, set
`programs.nix-crab.luatools.lumenService = true;` (home module). Lumen then starts at login under
`systemctl --user` (unit `nix-crab-lumen`, `Restart=on-failure`) and the `steam` command is
**not** shadowed — Steam launches plain and Lumen attaches on its own once the CEF port is
published. The default keeps the wrapper, which only runs Lumen while Steam is used; the two modes
are mutually exclusive by construction (the wrapper is dropped when the service is enabled).

> **Games do not land in `~/.config/SLSsteam/config.yaml`.** slsteam-moon deprecated the
> `AdditionalApps` section there — it is read only for backward compatibility. Added games are
> `<appid>.lua` files in `~/.steam/steam/config/stplug-in/` (the LuaTools plugin writes those), and
> manual additions go in `~/.config/SLSsteam/luaappids.yaml` as an `AdditionalApps` list. If you
> were checking `config.yaml` for your games, look at those two places instead — an empty
> `AdditionalApps` in `config.yaml` is expected, not a sign that the import failed.

> **Cloud saves for LuaTools games need the patched CloudRedirect hook — opt in.** Upstream
> `cloud_redirect.so` reads the game list only from `config.yaml`'s `AdditionalApps`, so it never
> sees stplug-in games. For the LuaTools stack, enable [cloudredirect-moon](https://github.com/swwayps/cloudredirect-moon),
> which additionally scans `stplug-in` and `luaappids.yaml` (set `programs.nix-crab.cloudredirect.moon.enable`
> in both modules). It still reads the legacy `config.yaml` list, so it also covers upstream
> SLSsteam — but it is opt-in and only needed for LuaTools; upstream CloudRedirect stays the default.

> **Do not combine with Millennium.** Lumen talks to Steam over the CEF remote-debugging **port**;
> Millennium grabs the same endpoint by launching `steamwebhelper` with `--remote-debugging-pipe`, so
> no TCP port exists, `~/.local/share/Lumen/cef_port` is never written, and Lumen cannot attach. The
> two stacks are mutually exclusive: either `millennium.enable` (themes/plugins) or
> `slssteam-moon.enable` + `luatools.enable` (LuaTools), not both. (The old LuaTools Millennium plugin
> is end-of-support anyway — this flake's LuaTools path is the maintained one.) If you see
> `--remote-debugging-pipe` on the `steamwebhelper` process, Millennium is holding the endpoint and
> LuaTools will not work.

## Comparison to h3adcr-b

| h3adcr-b                                  | nix-crab                                                    |
| ----------------------------------------- | ----------------------------------------------------------- |
| Patches `steam.sh` at runtime             | NixOS `programs.steam` override (`LD_AUDIT` / `LD_PRELOAD`) |
| Downloads binaries on every run           | Pinned, reproducible flake inputs                           |
| Blocking `steam.cfg` always written       | Only written by the optional downgrade script               |
| Auto-downgrade on client version mismatch | Follows client updates; downgrade is opt-in                 |
| Headcrab Updater desktop app              | `nix flake update`                                          |
| Multi-distro support                      | NixOS (native Steam)                                        |

## Caveats

- This is a _reimplementation_ of h3adcr-b for NixOS — not affiliated with h3adcr-b, SLSsteam or
  CloudRedirect.
- CloudRedirect is experimental by nature; back up saves you care about.
- Downloading and running third-party binaries (`dgsc`, `dlm`, `cloud_redirect_cli`) carries the same
  risk as h3adcr-b itself.

## License

MIT — see [LICENSE](LICENSE). Covers this flake's own Nix code only; the upstream projects it wires
up keep their own licenses (SLSsteam is AGPL-3.0).

## Credits

This repository is an **updated continuation of [nix-crab](https://github.com/ItszFinn/nix-crab)**
by **ItszFinn** — the architecture (two-module design, `LD_AUDIT`/`LD_PRELOAD` injection, the
status/update tooling, the Millennium and LuaTools stacks) is their work, and the original MIT
license carries over. nix-crab went quiet in September 2026 with broken URLs and stale pins; this
fork refreshes it, fixes the rot, and reworks the config into typed options. All credit for the
original goes to them.

A huge thank you to the developers of the projects that make this declarative NixOS reproduction possible.

This repository was created and is maintained by a **13-year-old NixOS enthusiast** (who knows that while this project's setup is anything but optimal, it works perfectly and gets the job done!), developed and polished with the help of the **[opencode](https://github.com/anomalyco/opencode)** AI assistant.

Project Credits:

- **[SLSsteam](https://github.com/AceSLS/SLSsteam)** (by AceSLS) — for the incredible Steam injection capability, its [wiki](https://github.com/AceSLS/SLSsteam/wiki) (the configuration documentation this module's options mirror), and the official NixOS install method by **[DeveloperMikey](https://github.com/DeveloperMikey)**.
- **[CloudRedirect](https://github.com/Selectively11/CloudRedirect)** (by Selectively11) — for the reliable cloud save syncing.
- **[SteaMidra (SFF)](https://github.com/Midrags/SFF)** (by Midrags) — for the powerful configuration and account manager.
- **[steamnetsock-patch](https://github.com/yesyes0649/steamnetsock-patch)** (by yesyes0649) — for the multiplayer fixes.
- **[Millennium](https://github.com/SteamClientHomebrew/Millennium)** (by Steam Homebrew) — for the client themes and plugins, and for shipping its own Nix package.
- **[slsteam-moon](https://github.com/swwayps/slsteam-moon), [Lumen](https://github.com/swwayps/lumen) and the [LuaTools port](https://github.com/swwayps/luatools-moon)** (by swwayps) — for keeping the LuaTools workflow alive on Linux.
- **[ACCELA / Enter The Wired](https://github.com/ciscosweater/enter-the-wired)** (by ciscosweater) — for the depot downloader this flake wraps.
