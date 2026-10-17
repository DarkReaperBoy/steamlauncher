#!/usr/bin/env bash
# Eval-level tests for the flake in tests/ (this file's parent directory).
set -u

cd "$(dirname "${BASH_SOURCE[0]}")"
nix flake lock --update-input crab >/dev/null 2>&1

FAILS=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

eval_raw() { nix eval --raw "$1" 2>/dev/null; }
eval_json() { nix eval --json "$1" 2>/dev/null; }
eval_err() { nix eval --raw "$1" 2>&1 >/dev/null; }

# --- NixOS: bare ------------------------------------------------------------

[ "$(eval_json '.#nixosConfigurations.bare.config.programs.steam.enable')" = "false" ] \
  && ok "bare: Steam off" || fail "bare: Steam off"
[ "$(eval_json '.#nixosConfigurations.bare.config.home-manager.users')" = "{}" ] \
  && ok "bare: Home Manager is not wired for anyone" || fail "bare: HM untouched"
[ "$(eval_json '.#nixosConfigurations.bare.config.programs.steam.config.enable')" = "false" ] \
  && ok "bare: steam-config-nix off" || fail "bare: steam-config-nix off"

# --- NixOS: full (everything, plain NixOS config) ---------------------------

if eval_raw '.#nixosConfigurations.full.config.system.build.toplevel.drvPath' >/dev/null; then
  ok "full: toplevel evaluates"
else
  fail "full: toplevel evaluates"
fi
djson=$(nix derivation show "$(eval_raw '.#nixosConfigurations.full.config.programs.steam.package.drvPath')" 2>/dev/null)
echo "$djson" | grep -q 'LD_AUDIT=.*SLSsteam.so' && ok "full: LD_AUDIT injected" || fail "full: LD_AUDIT injected"
echo "$djson" | grep -q 'MILLENNIUM_RUNTIME_PATH=' && ok "full: Millennium stacks with it" || fail "full: Millennium stacks"
eval_json '.#nixosConfigurations.full.config.programs.steam.config.apps."440"' | grep -q 'Team Fortress 2' \
  && ok "full: programs.nix-crab.steam.config aliases programs.steam.config" || fail "full: steam.config alias"
eval_json '.#nixosConfigurations.full.config.programs.steam.config.apps."1966720"' | grep -q 'netsock' \
  && ok "full: netsock.games bridge at NixOS level" || fail "full: netsock bridge"
eval_json '.#nixosConfigurations.full.config.home-manager.users.tester.programs.nix-crab.slssteam.manageConfig' | grep -q true \
  && ok "full: home options forwarded to home-manager" || fail "full: forwarding"
eval_json '.#nixosConfigurations.full.config.home-manager.users.tester.programs.nix-crab.netsock.games' | grep -q 1966720 \
  && ok "full: netsock forwarded" || fail "full: netsock forwarded"
eval_json '.#nixosConfigurations.full.config.home-manager.users.tester.programs.nix-crab.millennium.plugins' | grep -q 3dc714a7c1b1 \
  && ok "full: millennium add-ons forwarded" || fail "full: millennium forwarded"
eval_raw '.#nixosConfigurations.full.config.home-manager.users.tester.home.stateVersion' >/dev/null \
  && ok "full: HM gets a stateVersion" || fail "full: HM stateVersion"
eval_json '.#nixosConfigurations.full.config.home-manager.users.tester.home.packages' >/dev/null \
  && ok "full: HM profile has packages" || fail "full: HM packages"
eval_json '.#nixosConfigurations.full.config.systemd.tmpfiles.rules' | grep -q 'steam-config-nix/apps/440/wrapper' \
  && ok "full: steam-config-nix wrapper link (tmpfiles)" || fail "full: wrapper link"
eval_raw '.#nixosConfigurations.full.config.systemd.services."steam-config-patcher@".serviceConfig.ExecStart' | grep -q steam-config-patcher \
  && ok "full: patcher system unit" || fail "full: patcher system unit"

# --- NixOS: steamOnly -------------------------------------------------------

[ "$(eval_json '.#nixosConfigurations.steamOnly.config.programs.steam.enable')" = "true" ] \
  && ok "steamOnly: the unified knob enables Steam" || fail "steamOnly: steam on"
[ "$(eval_json '.#nixosConfigurations.steamOnly.config.home-manager.users')" = "{}" ] \
  && ok "steamOnly: no Home Manager wiring" || fail "steamOnly: no HM"
nix derivation show "$(eval_raw '.#nixosConfigurations.steamOnly.config.programs.steam.package.drvPath')" 2>/dev/null | grep -q 'LD_AUDIT' \
  && fail "steamOnly: no injection" || ok "steamOnly: no injection"

# a Steam package chosen through programs.nix-crab.steam.package
# programs.steam.package has an upstream `apply` (it re-overrides the package),
# so compare the two configurations against each other, not against a raw path.
p1=$(nix derivation show "$(eval_raw '.#nixosConfigurations.steamPkg.config.programs.steam.package.drvPath')" 2>/dev/null | grep -c 'NIX_CRAB_TEST')
p2=$(nix derivation show "$(eval_raw '.#nixosConfigurations.steamOnly.config.programs.steam.package.drvPath')" 2>/dev/null | grep -c 'NIX_CRAB_TEST')
[ "$p1" -ge 1 ] && [ "$p2" = 0 ] \
  && ok "steamPkg: custom package flows into programs.steam.package" || fail "steamPkg: package ($p1/$p2)"

# --- NixOS: moon ------------------------------------------------------------

nix derivation show "$(eval_raw '.#nixosConfigurations.moon.config.programs.steam.package.drvPath')" 2>/dev/null | grep -q 'slsteam-moon.*/library-inject.so' \
  && ok "moon: slsteam-moon injected" || fail "moon: slsteam-moon injected"
eval_json '.#nixosConfigurations.moon.config.home-manager.users.tester.programs.nix-crab.luatools.enable' | grep -q true \
  && ok "moon: luatools forwarded" || fail "moon: luatools forwarded"

# --- NixOS: user detection --------------------------------------------------

eval_err '.#nixosConfigurations.ambiguousUser.config.system.build.toplevel.drvPath' | grep -q 'programs.nix-crab.user' \
  && ok "ambiguousUser: asks for an explicit user" || fail "ambiguousUser assertion"
[ "$(eval_raw '.#nixosConfigurations.explicitUser.config.home-manager.users.bob.home.username')" = "bob" ] \
  && ok "explicitUser: configures the named user" || fail "explicitUser: bob configured"
eval_err '.#nixosConfigurations.explicitUser.config.home-manager.users.tester.home.username' >/dev/null \
  && fail "explicitUser: nobody else" || ok "explicitUser: nobody else"

# --- NixOS: assertions ------------------------------------------------------

eval_err '.#nixosConfigurations.badCombo.config.system.build.toplevel.drvPath' | grep -q "mutually exclusive" \
  && ok "badCombo: millennium+moon assertion" || fail "badCombo assertion"
eval_err '.#nixosConfigurations.badSteamOff.config.system.build.toplevel.drvPath' | grep -q "needs the Steam client" \
  && ok "badSteamOff: steam.enable=false assertion" || fail "badSteamOff assertion"

# --- Home Manager (standalone output) ---------------------------------------

if eval_raw '.#homeConfigurations.bare.activationPackage.drvPath' >/dev/null; then
  ok "home bare: activation package evaluates"
else
  fail "home bare: activation package evaluates"
fi
if eval_raw '.#homeConfigurations.full.activationPackage.drvPath' >/dev/null \
  || eval_raw '.#homeConfigurations.upstreamCfg.activationPackage.drvPath' >/dev/null; then
  ok "home configs: activation packages evaluate"
else
  fail "home configs: activation packages evaluate"
fi
eval_json '.#homeConfigurations.upstreamCfg.config.programs.steam.config.enable' | grep -q true \
  && ok "home: steam-config-nix alias works standalone too" || fail "home: alias"

eval_err '.#homeConfigurations.badSettings.activationPackage.drvPath' | grep -q "manageConfig = false" \
  && ok "badSettings: settings-without-manageConfig assertion" || fail "badSettings assertion"
eval_err '.#homeConfigurations.badNetsock.activationPackage.drvPath' | grep -q "programs.nix-crab.steam.config.enable" \
  && ok "badNetsock: netsock.games assertion" || fail "badNetsock assertion"

echo
if [ "$FAILS" = 0 ]; then echo "ALL EVAL TESTS PASSED"; else echo "$FAILS EVAL TEST(S) FAILED"; exit 1; fi
