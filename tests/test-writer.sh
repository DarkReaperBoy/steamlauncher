#!/usr/bin/env bash
# Writer tests for the managed ~/.config/SLSsteam/config.yaml (modules/home.nix).
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"  # repo under test

set -u

cd "$(dirname "${BASH_SOURCE[0]}")"
nix flake lock --update-input crab >/dev/null 2>&1

FAILS=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

# --- helpers ---------------------------------------------------------------

run_activation() { # $1 = generation path, $2 = home dir
  HOME="$2" USER=nako LOGNAME=nako "$1/activate" >/tmp/writer-activate.log 2>&1
  echo $?
}

# --- scenario 1: fresh HOME ------------------------------------------------
rm -rf /tmp/hm-test && mkdir -p /tmp/hm-test
gen=$(nix build --no-link --print-out-paths '.#homeConfigurations.smoke.activationPackage')
cfg=/tmp/hm-test/.config/SLSsteam/config.yaml

rc=$(run_activation "$gen" /tmp/hm-test)
[ "$rc" = 0 ] && ok "activation exits 0 on a fresh HOME" || { fail "activation exits 0 (rc=$rc)"; sed -n '1,40p' /tmp/writer-activate.log; }

[ -f "$cfg" ] && ok "config.yaml written" || fail "config.yaml written"
[ "$(stat -c %a "$cfg")" = 644 ] && ok "config.yaml is 644 (writable)" || fail "config.yaml mode is $(stat -c %a "$cfg"), want 644"
[ ! -L "$cfg" ] && ok "config.yaml is a real file" || fail "config.yaml is a symlink"

grep -q '^AppIds:$' "$cfg" && ok "base keys present (AppIds)" || fail "base keys present"
grep -A1 '^AppIds:$' "$cfg" | grep -q '440' && ok "user setting applied (AppIds: 440)" || fail "user setting applied"
grep -q '^DisableCloud: true$' "$cfg" && ok "flake default DisableCloud: true written" || fail "DisableCloud flip"
grep -q '#Disables Family Share license locking' "$cfg" && ok "base comments survive" || fail "base comments survive"
grep -q '^{' "$cfg" && fail "no flow-style corruption" || ok "no flow-style corruption"
grep -q 'FakeAppIds:.\+' "$cfg" && fail "nulls not degraded" || ok "nulls not degraded"
if (cd /tmp && nix run nixpkgs#yq-go -- eval "$cfg" >/dev/null 2>&1); then
  ok "config.yaml parses as YAML"
else
  fail "config.yaml parses as YAML"
fi

# --- scenario 2: idempotent re-run ----------------------------------------
before=$(sha256sum < "$cfg")
rc=$(run_activation "$gen" /tmp/hm-test)
after=$(sha256sum < "$cfg")
[ "$rc" = 0 ] && [ "$before" = "$after" ] && ok "second run: identical file, exit 0" || fail "second run idempotent"
grep -q 'up to date' /tmp/writer-activate.log && ok "second run reports up to date" || fail "second run reports up to date"

# --- scenario 3: runtime keys written by the LuaTools plugin are kept -------
python3 - "$cfg" <<'EOF'
import sys
p = sys.argv[1]
text = open(p).read()
text += """
ManifestPins:
  123:
    locked: true
    depots:
      456: "789"
FakeAppIds:
  730: 480
"""
open(p, "w").write(text)
EOF
rc=$(run_activation "$gen" /tmp/hm-test)
[ "$rc" = 0 ] && ok "third run (plugin edits present) exit 0" || { fail "third run exit 0"; tail -20 /tmp/writer-activate.log; }
grep -q '^  123:$' "$cfg" && ok "ManifestPins preserved (unquoted appid key)" || fail "ManifestPins preserved"
grep -q '^  730: 480$' "$cfg" && ok "FakeAppIds preserved" || fail "FakeAppIds preserved"
grep -q '^  - 440$' "$cfg" && ok "user AppIds still there after preservation merge" || fail "user AppIds kept"

# --- scenario 4: declared FakeAppIds is Nix's, plugin edits are reset -------
rm -rf /tmp/hm-test2 && mkdir -p /tmp/hm-test2
gen2=$(nix build --no-link --print-out-paths '.#homeConfigurations.smokeFake.activationPackage')
cfg2=/tmp/hm-test2/.config/SLSsteam/config.yaml
rc=$(run_activation "$gen2" /tmp/hm-test2)
[ "$rc" = 0 ] && ok "smokeFake activation exit 0" || { fail "smokeFake activation"; tail -20 /tmp/writer-activate.log; }
python3 - "$cfg2" <<'EOF'
import sys
p = sys.argv[1]
open(p, "a").write("\nManifestPins:\n  999:\n    locked: true\nFakeAppIds:\n  730: 480\n")
EOF
rc=$(run_activation "$gen2" /tmp/hm-test2)
grep -q '^  999:$' "$cfg2" && ok "undeclared ManifestPins kept" || fail "undeclared ManifestPins kept"
grep -q '^  730: 480$' "$cfg2" && fail "declared FakeAppIds resets plugin edit" || ok "declared FakeAppIds resets plugin edit"
grep -q '^  440: 480$' "$cfg2" && ok "declared FakeAppIds value present" || fail "declared FakeAppIds value present"

# --- scenario 5: legacy store symlink is replaced, not written through ------
rm -rf /tmp/hm-test && mkdir -p /tmp/hm-test/.config/SLSsteam
legacy=$(nix build --no-link --print-out-paths "$root#sls-steam")/res/config.yaml
ln -sf "$legacy" /tmp/hm-test/.config/SLSsteam/config.yaml
rc=$(run_activation "$gen" /tmp/hm-test)
[ -L /tmp/hm-test/.config/SLSsteam/config.yaml ] && fail "legacy symlink replaced" || ok "legacy symlink replaced"
grep -q 'installed SLSsteam config.yaml' /tmp/writer-activate.log && ok "legacy symlink replaced message" || fail "legacy symlink replaced message"
grep -q '^AppIds:$' /tmp/hm-test/.config/SLSsteam/config.yaml && ok "config content correct after symlink replacement" || fail "content after symlink replacement"

# --- scenario 6: netsock.games wires a steam-config-nix launch wrapper ------
wrapper=$(readlink -f /tmp/hm-test/.local/share/steam-config-nix/apps/1966720/wrapper 2>/dev/null || true)
[ -n "$wrapper" ] && [ -f "$wrapper" ] && ok "netsock wrapper exists" || fail "netsock wrapper exists"
grep -q 'LD_AUDIT="\$HOME/.config/SLSsteam/tools/netsock/netsock.so"' "$wrapper" 2>/dev/null \
  && ok "netsock wrapper exports LD_AUDIT" || fail "netsock wrapper exports LD_AUDIT"
grep -q 'netsock.so' /tmp/hm-test/.config/SLSsteam/tools/netsock/netsock.so 2>/dev/null \
  && true # file is binary; just check it exists
[ -f /tmp/hm-test/.config/SLSsteam/tools/netsock/netsock.so ] && ok "netsock.so linked" || fail "netsock.so linked"

# --- scenario 7: nix-crab-status runs, both modes ---------------------------
status=$(nix build --no-link --print-out-paths "$root#nix-crab-status")/bin/nix-crab-status
HOME=/tmp/hm-test USER=nako "$status" >/tmp/status.txt 2>&1 \
  && ok "nix-crab-status text mode runs" || { fail "nix-crab-status text mode"; cat /tmp/status.txt; }
HOME=/tmp/hm-test USER=nako "$status" --json >/tmp/status.json 2>&1 \
  && ok "nix-crab-status json mode runs" || { fail "nix-crab-status json mode"; cat /tmp/status.json; }
python3 -c "import json;d=json.load(open('/tmp/status.json'));assert 'steam_config' in d and 'cloudredirect' not in d" \
  && ok "status JSON valid + has steam_config, no cloudredirect" || { fail "status JSON"; cat /tmp/status.json; }
grep -q 'DisableCloud:   true' /tmp/status.txt && ok "status reports DisableCloud" || fail "status reports DisableCloud"

# --- scenario 8: the same writer, driven from plain NixOS config ------------
rm -rf /tmp/hm-nixos && mkdir -p /tmp/hm-nixos
gen3=$(nix build --no-link --print-out-paths \
  '.#nixosConfigurations.smokeNixos.config.home-manager.users.nako.home.activationPackage')
HOME=/tmp/hm-nixos USER=nako LOGNAME=nako "$gen3/activate" >/tmp/hm-nixos.log 2>&1
grep -q "installed SLSsteam config.yaml" /tmp/hm-nixos.log \
  && ok "nixos path: config.yaml written" || fail "nixos path: config.yaml"
grep -q '^DisableCloud: true$' /tmp/hm-nixos/.config/SLSsteam/config.yaml \
  && ok "nixos path: managed config content" || fail "nixos path: config content"
[ -f /tmp/hm-nixos/.config/SLSsteam/tools/netsock/netsock.so ] \
  && ok "nixos path: netsock.so linked" || fail "nixos path: netsock.so"
[ -x /tmp/hm-nixos/.local/share/Lumen/lumen ] \
  && ok "nixos path: Lumen installed" || fail "nixos path: Lumen"
# the wrapper link itself is a tmpfiles rule on the NixOS path
# (/var/lib/steam-config-nix/...), covered by test-eval.sh; here the wrapper
# package is what has to exist and carry LD_AUDIT.
wrapper3=$(nix build --no-link --print-out-paths "$root#netsock" 2>/dev/null)
[ -n "$wrapper3" ] && ok "nixos path: netsock package builds" || fail "nixos path: netsock package"
[ -e /tmp/hm-nixos/.config/systemd/user/nix-crab-lumen.service ] \
  && ok "nixos path: lumen user unit" || fail "nixos path: lumen user unit"
HOME=/tmp/hm-nixos USER=nako "$status" --json >/tmp/status-nixos.json 2>&1 \
  && python3 -c "import json;d=json.load(open('/tmp/status-nixos.json'));assert d['slssteam']['config_present']" \
  && ok "nixos path: nix-crab-status sees the config" || fail "nixos path: nix-crab-status"

echo
if [ "$FAILS" = 0 ]; then echo "ALL WRITER TESTS PASSED"; else echo "$FAILS TEST(S) FAILED"; exit 1; fi
