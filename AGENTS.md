# AGENTS.md

NixOS flake (nix-crab, continued from ItszFinn/nix-crab) that makes SLSsteam injection, Millennium *or* LuaTools, per-game Steam config, ACCELA, SteaMidra, netsock and the Steam client-downgrade tool declarative. Everything a user writes is one `programs.nix-crab.*` block in plain NixOS config; Home Manager is driven internally. CloudRedirect is gone; steam-config-nix is re-exported.

## Architecture

- **One namespace**: `programs.nix-crab.*` — including Steam itself (`steam.{enable,package,extraCompatPackages,config}`) and the per-game surface. `steam.config` is a thin alias of steam-config-nix's `programs.steam.config` (`modules/steam-config.nix`); upstream's docs/types stay authoritative.
- **Unit pattern**: `modules/<feature>.nix` is `{ inputs }: { module, mk* }`; `flake.nix` instantiates each once, `.module` for module outputs, `.mk*` for `packages.*` — one definition per derivation. Modules owning no derivation (`settings.nix`, `home-options.nix`, `steam-config.nix`, `netsock-bridge.nix`, `millennium*.nix`, `nixos-home.nix`) are plain. Do not recreate `lib.nix`.
- **Options/config split**: `modules/home-options.nix` declares every home-side option ONCE (plus `settings.nix`); both module sets import it. The per-feature modules only emit config.
- `nixosModules.default` = steam-config-nix's NixOS module + home-manager's NixOS module + `home-options.nix` + `netsock-bridge.nix` + `nixos-home.nix` + `millennium.nix` + `slssteam.nix` + `downgrade.nix`.
- `homeModules.default` = steam-config-nix's HM module + `home-options.nix` + `steam-config.nix` + `netsock-bridge.nix` + `homeConfigModules` (the shared config list). This is the **standalone** path; the NixOS path imports the same list into `home-manager.users.<user>`.
- Units are partial applications: `flake.nix` threads inputs (`(import ./modules/x.nix { inherit input; })`). Never use `inputs` inside a module body.

## Decisions — do not "fix"

- **Home Manager is internal.** `modules/nixos-home.nix` detects the target user (`users.users` with exactly one `isNormalUser`, else `programs.nix-crab.user`, else: don't touch any home) and forwards the home-side options into `home-manager.users.<user>`. `home-manager.users` is gated so a system with no home-side option gets no Home Manager at all. `home.stateVersion` gets a `mkDefault`.
  - **`useUserPackages` must stay false** (mkDefault): it writes `users.users.*.packages` from `home-manager.users` while detection reads `users.users` → infinite recursion (home-manager#594). `useGlobalPkgs = true` is safe.
  - **Classification guard**: every `programs.nix-crab` feature must be listed in `nixos-home.nix` as home/system/split or eval fails — that is what stops the forwarding from silently dropping a future option.
  - The user first rejected auto-wiring, then asked for exactly this. Keep it as it is.
- **`programs.nix-crab.steam.*` owns the official Steam module** — `steam.enable` (null = on when a feature needs it), `steam.package` (the base the injection is built from; Millennium's `millennium-steam` when `millennium.enable`), `steam.extraCompatPackages`. All translated into `programs.steam.*` with `mkDefault`. Injection is applied *on top of* `steam.package`, never beside it.
- **Options that are typed but not written default to `null`** — `settings.*` per-key options (`modules/settings.nix`, mirrors upstream's `config.yaml` incl. slsteam-moon's `ManifestPins`), `accela.config.*`. `extraSettings` is the freeform escape hatch. Setting any `settings` key without `manageConfig` fails eval.
- **The managed `config.yaml` is written by an activation step, not `xdg.configFile`** — a store symlink can't be written through by SLSsteam's watcher or the LuaTools plugin (its temp-file+rename escapes the symlink). Real 644 file next to the target, `mv` in, only when content changed. Activation must use `lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "writeBoundary" ]` — HM ties are broken by name and `slssteamConfig` would otherwise land after `reloadSystemd` and be skipped when systemd fails.
- **Merge base = the active fork's own `res/config.yaml`**, deep-merged with `pkgs.yq-go` (`base * overlay`). Never `pkgs.yq` (kislyuk's jq wrapper), never a hand-written YAML renderer, never yq for an EMPTY overlay (nulls → `''`, flow style). Plugin-owned keys (`ManifestPins`, `FakeAppIds`) are carried over from the live file each activation unless the user declared them; extraction must strip comment lines.
- **`DisableCloud: true` is the one flake-level default** — both forks ship `no` because they normally ship a cloud hook; CloudRedirect is gone. User values win.
- **`manageConfig` defaults false** so SteaMidra can own the file.
- **Upstream release binaries, not source builds** — five projects: SLSsteam, Millennium, slsteam-moon, Lumen, LuaTools (`modules/upstream-binaries.nix`). `upstream.lock.json` is **generated** by `ci/update-binaries.sh` (never hand-edit: it verifies each asset against the project's own `.sha256` sidecar, and falls back to the fetched hash when a project publishes none — SLSsteam doesn't). Four flake inputs were deleted for this; only 7 remain (nixpkgs, home-manager, millennium, steam-config-nix, enter-the-wired, steamidra, steamnetsock). Consequences to remember:
  - `sls-steam` is unpacked from `SLSsteam-Any-release.7z` and **must keep the store name `sls-steam-*`** — `nix-crab-status` detects the injected fork by matching that name in `LD_AUDIT`.
  - `ticket-grabber`/`schema-grabber` are framework-dependent .NET 9 publishes from the same 7z; their wrappers only set `DOTNET_ROOT` to `pkgs.dotnet-runtime_9` (the exact store path upstream's own wrapper uses). Nothing compiles in CI — the build step is downloads.
  - the managed-config merge base for *both* forks now comes from the same archive as their binaries (`<pkg>/res/config.yaml`).
- **Millennium wiring**: `modules/millennium.nix` applies *two* overlays — Millennium's own, then one that replaces `final.millennium` with the release binary. `millennium-steam` is defined in terms of `final.millennium`, so it picks the swap up with no other change. Never remap `pkgs.steam = millennium-steam` (recurses).
- **`.github/workflows/ci.yml` is both workflows in one file.** `check` (push/PR/manual): `nix flake check` → `nix fmt` + `git diff --exit-code` → build every package output → run `tests/`. `sync` (daily 04:17 UTC + manual): `ci/update-binaries.sh` → `nix flake update` → `nix flake check` + build the binaries → open a PR (with a job-summary fallback if the repo's Actions-PR setting is off). Actions are pinned to commit SHAs. No binary cache of our own, deliberately.
- **CloudRedirect is gone** (upstream repo, `-moon` fork, CLI, Flatpak, `nix-flatpak` input, `~/.local/share/CloudRedirect/*`). `slssteam.extraEnv` is the escape hatch for a preload library.
- **netsock is never injected globally** — `~/.config/SLSsteam/tools/netsock/netsock.so` + per game only, never with anti-cheat.
- **`steam-run` must stay in the luatools module's packages** — the Lumen shim execs it; `programs.steam` does not provide it.
- **No "Steam with SLSsteam baked in" package**; injection only exists behind `programs.nix-crab.slssteam.enable`. No package output is unfree.
- **Forge inputs**: `steamidra` = `api.github.com/repos/Midrags/SFF/tags` (releases/latest changes hourly → narHash churn; never pin `narHash` either). `enter-the-wired` = the AppImage in the store (versionless URL, no tags). `accela`/`steamidra` AppImages: SteaMidra is downloaded at runtime by the launcher, ACCELA is an `appimageTools` wrapper needing `extraPkgs = p: [ p.zstd ]`.
- **`downgrade.nix`**: `dgsc`/`dlm` pinned to commit `8c36338994fdb085fa07b887f71d64362af51c1d`; manifest + `sources.txt` are fetched at runtime with curl (fetchurl hashes rot every Steam build).
- **`ACCELA.conf` is seeded, never managed** (QSettings rewrites it) — same reasoning as `manageConfig`.
- **`luatools.lumenService`** is an opt-in alternative to the `steam` wrapper sidecar; never both.

## Verification

- `nix flake check` in repo root. `nix fmt` before committing.
- Tests live **in-repo at `tests/`** (`cd tests && ./test-eval.sh && ./test-writer.sh`) — also run by the `check` CI job. The harness flake consumes this repo via `path:..`, recorded in its lock *without* a narHash, so it always evaluates the current checkout; there is nothing to re-lock after edits. Configs: `nixosConfigurations.{bare,full,moon,steamOnly,steamPkg,smokeNixos,ambiguousUser,explicitUser,badCombo,badSteamOff}` + `homeConfigurations.{bare,upstreamCfg,smoke,smokeFake,badSettings,badNetsock}`. `bare` must leave Steam off and Home Manager untouched; `bad*` must fail eval with the intended assertion message; `full` must show `LD_AUDIT` and `MILLENNIUM_RUNTIME_PATH` on the same steam package.
- Sanity for binaries: `nix build .#millennium .#slsteam-moon .#lumen .#luatools`, and `./ci/update-binaries.sh` must report "everything already current" when the lock is right.
- The LuaTools plugin's line regexes must keep matching the generated file: keys bare (`  123:`, `  440: 480`), never `'440'`.
- Deep home-manager evals (whole `home-manager.users.<u>` dump) can trip a benign upstream `accounts.calendar.basePath` error; read leaves instead.

## Gotchas

- **Path-input narHash**: consumers via `path:...` must re-lock after every edit here.
- **`programs.steam.package` has an upstream `apply`** (NixOS re-overrides the package), so its final drv never equals the raw definition — compare configurations, not paths.
- yq-go: no `&&`/`||` (use `and`/`or`), no "plain" style, `-o=json` overlays poison a YAML merge. Keep every intermediate in the pipeline YAML.
- `appimage-run` smoke test: `HOME=$(mktemp -d) QT_QPA_PLATFORM=offscreen accela`.
- `modules/steam.cfg` `BootStrapperForceSelfUpdate` typo was fixed; keep it `disable`.
- `h3adcr-b.sh` in repo root is reference material only — not part of any build.
