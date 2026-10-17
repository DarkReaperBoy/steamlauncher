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

# --- no home-manager, anywhere ---------------------------------------------
# The whole point of the current architecture: nix-crab has no home-manager
# input, does not declare home-manager options, and needs no HM module.

eval_err '.#nixosConfigurations.full.options.home-manager' | grep -q "does not provide attribute" \
  && ok "no HM: home-manager option absent from the module set" || fail "no HM: home-manager option absent"
python3 - <<'EOF' && ok "no HM: home-manager gone from the test lock (transitively)" || fail "no HM: lock still pins home-manager"
import json
lock = json.load(open("flake.lock"))
assert not any(
    "home-manager" in k or v.get("locked", {}).get("repo") == "home-manager"
    for k, v in lock["nodes"].items()
), "home-manager still locked"
EOF

# --- NixOS: bare ------------------------------------------------------------

[ "$(eval_json '.#nixosConfigurations.bare.config.programs.steam.enable')" = "false" ] \
  && ok "bare: Steam off" || fail "bare: Steam off"
[ "$(eval_json '.#nixosConfigurations.bare.config.programs.steam.config.enable')" = "false" ] \
  && ok "bare: steam-config-nix off" || fail "bare: steam-config-nix off"
# (nix-crab-millennium IS present with empty lists by design: emptying the
# lists has to keep running, or removing the last ID would leave it installed.)
nix eval --raw '.#nixosConfigurations.bare.config.system.activationScripts' --apply 's: builtins.toJSON (builtins.attrNames s)' 2>/dev/null \
  | grep -qE 'nix-crab-(slssteam|netsock|luatools|accela|steamidra)' \
  && fail "bare: no file-writer activation snippets" || ok "bare: no file-writer activation snippets"
eval_json '.#nixosConfigurations.bare.config.environment.systemPackages' | grep -q nix-crab \
  && fail "bare: nothing installed" || ok "bare: nothing installed"

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
eval_json '.#nixosConfigurations.full.config.programs.nix-crab.slssteam.manageConfig' | grep -q true \
  && ok "full: settings/manageConfig readable as plain NixOS config" || fail "full: manageConfig"
eval_json '.#nixosConfigurations.full.config.programs.nix-crab.millennium.plugins' | grep -q 3dc714a7c1b1 \
  && ok "full: millennium add-ons configured at the NixOS level" || fail "full: millennium plugins"
eval_raw '.#nixosConfigurations.full.config.system.activationScripts."nix-crab-slssteam-config".text' | grep -q 'config.yaml' \
  && ok "full: config.yaml writer is an activation snippet" || fail "full: config.yaml activation"
eval_raw '.#nixosConfigurations.full.config.system.activationScripts."nix-crab-millennium".text' | grep -q 'crabSync' \
  && ok "full: millennium installer is an activation snippet" || fail "full: millennium activation"
eval_json '.#nixosConfigurations.full.config.environment.systemPackages' | grep -q nix-crab-status \
  && ok "full: nix-crab-status installed system-wide" || fail "full: tools installed"
eval_json '.#nixosConfigurations.full.config.systemd.tmpfiles.rules' | grep -q 'steam-config-nix/apps/440/wrapper' \
  && ok "full: steam-config-nix wrapper link (tmpfiles)" || fail "full: wrapper link"
eval_raw '.#nixosConfigurations.full.config.systemd.services."steam-config-patcher@".serviceConfig.ExecStart' | grep -q steam-config-patcher \
  && ok "full: patcher system unit" || fail "full: patcher unit"

# --- NixOS: steamOnly / sugar / passthrough ---------------------------------

[ "$(eval_json '.#nixosConfigurations.steamOnly.config.programs.steam.enable')" = "true" ] \
  && ok "steamOnly: the unified knob enables Steam" || fail "steamOnly: steam on"
nix derivation show "$(eval_raw '.#nixosConfigurations.steamOnly.config.programs.steam.package.drvPath')" 2>/dev/null | grep -q 'LD_AUDIT' \
  && fail "steamOnly: no injection" || ok "steamOnly: no injection"

[ "$(eval_json '.#nixosConfigurations.steamSugar.config.programs.steam.enable')" = "true" ] \
  && ok "steamSugar: bool shorthand (steam = true) enables Steam" || fail "steamSugar: steam = true"

# the extraPkgs default baseline must be there WITHOUT anyone writing the option...
eval_json '.#nixosConfigurations.steamOnly.config.programs.nix-crab.steam.extraPkgs' | grep -q gamemode \
  && ok "extraPkgs: baseline list ships as the option default" || fail "extraPkgs: option default baseline"
# ...but a RAW programs.steam.package must keep working next to us: the
# baseline-only override goes in at mkDefault priority, so it never turns
# into a second same-priority definition (types.package: two of those = eval
# error) and the user's own package wins.
p3=$(nix derivation show "$(eval_raw '.#nixosConfigurations.rawSteamPkg.config.programs.steam.package.drvPath')" 2>/dev/null | grep -c 'NIX_CRAB_RAW')
p4=$(nix derivation show "$(eval_raw '.#nixosConfigurations.rawSteamPkgNixCrabOn.config.programs.steam.package.drvPath')" 2>/dev/null | grep -c 'NIX_CRAB_RAW')
[ "$p3" -ge 1 ] && [ "$p4" -ge 1 ] \
  && ok "extraPkgs: raw programs.steam.package wins over the baseline (no conflict)" \
  || fail "extraPkgs: raw package conflict ($p3/$p4)"

[ "$(eval_json '.#nixosConfigurations.steamPassthrough.config.programs.steam.remotePlay.openFirewall')" = "true" ] \
  && ok "passthrough: remotePlay.openFirewall reaches programs.steam" || fail "passthrough: remotePlay"
[ "$(eval_json '.#nixosConfigurations.steamPassthrough.config.programs.steam.protontricks.enable')" = "true" ] \
  && ok "passthrough: protontricks.enable reaches programs.steam" || fail "passthrough: protontricks"

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
eval_raw '.#nixosConfigurations.moon.config.system.activationScripts."nix-crab-luatools".text' | grep -q 'Lumen' \
  && ok "moon: luatools sync is an activation snippet" || fail "moon: luatools activation"
nix eval --raw --apply 's: builtins.toJSON (builtins.attrNames s)' '.#nixosConfigurations.moon.config.systemd.user.services' 2>/dev/null | grep -q nix-crab-lumen \
  && ok "moon: lumen user unit (NixOS systemd.user schema)" || fail "moon: lumen unit"

# --- NixOS: user detection --------------------------------------------------

eval_err '.#nixosConfigurations.ambiguousUser.config.system.build.toplevel.drvPath' | grep -q 'programs.nix-crab.user' \
  && ok "ambiguousUser: asks for an explicit user" || fail "ambiguousUser assertion"
eval_raw '.#nixosConfigurations.explicitUser.config.system.activationScripts."nix-crab-netsock".text' | grep -q '/home/bob' \
  && ok "explicitUser: activation targets the named user" || fail "explicitUser: bob targeted"
eval_raw '.#nixosConfigurations.explicitUser.config.system.activationScripts."nix-crab-netsock".text' | grep -q '/home/tester' \
  && fail "explicitUser: nobody else" || ok "explicitUser: nobody else"

# --- NixOS: assertions ------------------------------------------------------

eval_err '.#nixosConfigurations.badCombo.config.system.build.toplevel.drvPath' | grep -q "mutually exclusive" \
  && ok "badCombo: millennium+moon assertion" || fail "badCombo assertion"
eval_err '.#nixosConfigurations.badSteamOff.config.system.build.toplevel.drvPath' | grep -q "needs the Steam client" \
  && ok "badSteamOff: steam.enable=false assertion" || fail "badSteamOff assertion"
eval_err '.#nixosConfigurations.badSettings.config.system.build.toplevel.drvPath' | grep -q "manageConfig = false" \
  && ok "badSettings: settings-without-manageConfig assertion" || fail "badSettings assertion"
eval_err '.#nixosConfigurations.badNetsock.config.system.build.toplevel.drvPath' | grep -q "programs.nix-crab.steam.config.enable" \
  && ok "badNetsock: netsock.games assertion" || fail "badNetsock assertion"

# --- activation text extraction (what test-writer.sh runs) ------------------

txt=$(nix eval --raw --apply 'cs: builtins.concatStringsSep "\n" (map (n: cs.${n}.text) (builtins.filter (n: builtins.substring 0 9 n == "nix-crab-") (builtins.attrNames cs)))' \
  '.#nixosConfigurations.writerSmoke.config.system.activationScripts' 2>/dev/null)
echo "$txt" | grep -q 'SLSsteam/config.yaml' && echo "$txt" | grep -q 'netsock.so' \
  && ok "writerSmoke: activation snippets extract and carry both writers" \
  || fail "writerSmoke: activation extraction"

echo
if [ "$FAILS" = 0 ]; then echo "ALL EVAL TESTS PASSED"; else echo "$FAILS EVAL TEST(S) FAILED"; exit 1; fi
