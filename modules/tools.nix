# nix-crab's own commands: diagnostics + maintenance. Unit shape: flake.nix
# takes `.module` (home module, owns the tools.enable option) and
# `.mkStatus`/`.mkUpdate` (the nix-crab-status / nix-crab-update packages) —
# same scripts both places.
{ }:
rec {
  # -- nix-crab tooling -----------------------------------------------------

  # Diagnostic command: client version, SLSsteam config, netsock, steam-config-nix
  # state, injection fork, LuaTools/Lumen state.
  mkStatus =
    pkgs:
    pkgs.writeShellScriptBin "nix-crab-status" ''
      set -u

      MODE="text"
      if [ $# -ge 1 ] && [ "$1" = "--json" ]; then
        MODE="json"
      fi

      PKG="$HOME/.steam/steam/package"
      CFG="$HOME/.config/SLSsteam/config.yaml"
      NETSOOK="$HOME/.config/SLSsteam/tools/netsock/netsock.so"
      STEAMCFG="$HOME/.steam/steam/steam.cfg"
      LUMEN_DIR="$HOME/.local/share/Lumen"

      # flat key block to config.yaml. So always read the last occurrence.
      val() { grep "^$1:" "$CFG" | tail -1 | awk '{print $2}'; }

      json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
      json_str()   { printf '"%s"' "$(json_escape "$1")"; }
      json_bool()  { [ "$1" = 1 ] && printf 'true' || printf 'false'; }

      # -- Steam client -------------------------------------------------------
      STEAM_VERSION=""
      STEAM_NOTE=""
      for f in "$PKG"/steam_client_*; do
        [ -f "$f" ] || continue
        STEAM_VERSION=$(grep -m1 '"version"' "$f" | awk -F'"' '{print $4}')
        [ -n "$STEAM_VERSION" ] && break
      done
      if [ -z "$STEAM_VERSION" ]; then
        STEAM_VERSION="unknown"
        STEAM_NOTE="no manifest in $PKG"
      fi

      # -- SLSsteam config ----------------------------------------------------
      CONFIG_PRESENT=0
      [ -f "$CFG" ] && CONFIG_PRESENT=1
      DISABLECLOUD=""
      PLAYNOTOWNED=""
      SAFEMODE=""
      MANIFESTPINS=0
      DUPES=0
      if [ "$CONFIG_PRESENT" = 1 ]; then
        DISABLECLOUD="$(val DisableCloud)"
        PLAYNOTOWNED="$(val PlayNotOwnedGames)"
        SAFEMODE="$(val SafeMode)"
        DUPES=$(grep -c '^DisableCloud:' "$CFG")
        grep -q '^ManifestPins:' "$CFG" && MANIFESTPINS=1
      fi
      NETSOOK_PRESENT=0
      [ -f "$NETSOOK" ] && NETSOOK_PRESENT=1

      # -- Injection fork (live Steam process) --------------------------------
      # LD_AUDIT lands in the env of every process Steam launches; scan /proc
      # for one carrying it and see which fork is injected. Store names differ:
      # upstream builds as "sls-steam", the fork as "slsteam-moon".
      INJECTION="unknown (Steam not running)"
      if ${pkgs.procps}/bin/pgrep -x steam >/dev/null 2>&1 \
        || ${pkgs.procps}/bin/pgrep -x steamwebhelper >/dev/null 2>&1; then
        INJECTION="none"
        LD=""
        for p in /proc/[0-9]*/environ; do
          [ -r "$p" ] || continue
          LD="$(tr '\0' '\n' < "$p" 2>/dev/null | grep -m1 '^LD_AUDIT=' || true)"
          [ -n "$LD" ] && break
        done
        case "$LD" in
          *slsteam-moon*) INJECTION="slsteam-moon (LuaTools)" ;;
          *SLSsteam-*|*sls-steam*) INJECTION="upstream SLSsteam" ;;
        esac
      fi

      # -- Games (slsteam-moon / LuaTools) ------------------------------------
      # slsteam-moon does NOT write added games into config.yaml's AdditionalApps
      # (that section is deprecated). Games are <appid>.lua files in Steam's
      # stplug-in dir, plus manual appids in luaappids.yaml.
      STPLUG=""
      for root in "$HOME/.steam/steam" "$HOME/.steam/debian-installation" "$HOME/.local/share/Steam"; do
        if [ -d "$root/config/stplug-in" ]; then STPLUG="$root/config/stplug-in"; break; fi
      done
      LUA_COUNT=0
      if [ -n "$STPLUG" ]; then
        LUA_COUNT=$(find "$STPLUG" -maxdepth 1 -name '*.lua' 2>/dev/null | wc -l | tr -d ' ')
      fi
      LUAAPPIDS=0
      [ -f "$HOME/.config/SLSsteam/luaappids.yaml" ] && LUAAPPIDS=1

      # -- steam-config-nix ----------------------------------------------------
      # Its patcher runs as a user service (Home Manager flavour) or as a
      # per-user system unit (NixOS flavour); configured apps live under
      # <dataHome>/steam-config-nix/apps as wrapper links.
      SCN_SERVICE="not installed"
      SCN_UNIT_FILE="$HOME/.config/systemd/user/steam-config-patcher.service"
      SCN_TEMPLATE=0
      if command -v systemctl >/dev/null 2>&1; then
        if [ -e "$SCN_UNIT_FILE" ]; then
          SCN_SERVICE="inactive"
          systemctl --user is-active --quiet steam-config-patcher.service 2>/dev/null \
            && SCN_SERVICE="active"
        elif systemctl list-unit-files --no-legend 'steam-config-patcher@*.service' 2>/dev/null | grep -q .; then
          SCN_TEMPLATE=1
          SCN_SERVICE="inactive"
          systemctl is-active --quiet "steam-config-patcher@$(id -un).service" 2>/dev/null \
            && SCN_SERVICE="active"
        fi
      fi
      SCN_APPS=0
      for root in "$HOME/.local/share/steam-config-nix/apps" /var/lib/steam-config-nix/apps; do
        [ -d "$root" ] || continue
        SCN_APPS=$(find "$root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
        break
      done

      # -- LuaTools / Lumen ----------------------------------------------------
      L_INSTALLED=0
      [ -x "$LUMEN_DIR/lumen" ] && [ -x "$LUMEN_DIR/lumen.bin" ] && L_INSTALLED=1
      L_PLUGIN=0
      [ -d "$LUMEN_DIR/luatools/backend" ] && L_PLUGIN=1
      L_RUNNING=0
      ${pkgs.procps}/bin/pgrep -f "$LUMEN_DIR/lumen.bin" >/dev/null 2>&1 && L_RUNNING=1
      L_CEFPORT=0
      [ -f "$LUMEN_DIR/cef_port" ] && L_CEFPORT=1

      # -- Updates --------------------------------------------------------------
      UPDATES_BLOCKED=0
      [ -f "$STEAMCFG" ] && UPDATES_BLOCKED=1

      if [ "$MODE" = "json" ]; then
        printf '{'
        printf '"steam":{"version":%s,"manifest_note":%s,"updates_blocked":%s},' \
          "$(json_str "$STEAM_VERSION")" "$(json_str "$STEAM_NOTE")" "$(json_bool "$UPDATES_BLOCKED")"
        printf '"slssteam":{"config_present":%s,"disable_cloud":%s,"play_not_owned":%s,"safe_mode":%s,"disable_cloud_duplicates":%s,"manifest_pins":%s,"netsock_present":%s},' \
          "$(json_bool "$CONFIG_PRESENT")" "$(json_str "$DISABLECLOUD")" "$(json_str "$PLAYNOTOWNED")" "$(json_str "$SAFEMODE")" "$DUPES" "$(json_bool "$MANIFESTPINS")" "$(json_bool "$NETSOOK_PRESENT")"
        printf '"injection":%s,' "$(json_str "$INJECTION")"
        printf '"games":{"stplug_in_dir":%s,"lua_manifests":%s,"luaappids_yaml":%s},' \
          "$(json_str "$STPLUG")" "$LUA_COUNT" "$(json_bool "$LUAAPPIDS")"
        printf '"steam_config":{"service":%s,"template_unit":%s,"configured_apps":%s},' \
          "$(json_str "$SCN_SERVICE")" "$(json_bool "$SCN_TEMPLATE")" "$SCN_APPS"
        printf '"luatools":{"installed":%s,"plugin_installed":%s,"running":%s,"cef_port":%s}' \
          "$(json_bool "$L_INSTALLED")" "$(json_bool "$L_PLUGIN")" "$(json_bool "$L_RUNNING")" "$(json_bool "$L_CEFPORT")"
        printf '}\n'
        exit 0
      fi

      echo "=== Steam Client ==="
      if [ -n "$STEAM_VERSION" ] && [ "$STEAM_VERSION" != "unknown" ]; then
        echo "Version: $STEAM_VERSION"
      else
        echo "Version: unknown (no manifest in $PKG)"
      fi

      echo
      echo "=== SLSsteam ==="
      if [ "$CONFIG_PRESENT" = 1 ]; then
        echo "DisableCloud:   $DISABLECLOUD"
        echo "PlayNotOwned:   $PLAYNOTOWNED"
        echo "SafeMode:       $SAFEMODE"
        echo "ManifestPins:   $([ "$MANIFESTPINS" = 1 ] && echo present || echo none)"
        [ "$DUPES" -gt 1 ] && echo "Warning:        DisableCloud set $DUPES times - only the last counts"
      else
        echo "Config missing: $CFG"
      fi
      echo "Netsock:        $([ "$NETSOOK_PRESENT" = 1 ] && echo present || echo missing)"

      echo
      echo "=== Injection (live Steam) ==="
      echo "Fork:           $INJECTION"

      echo
      echo "=== Games (slsteam-moon / LuaTools) ==="
      if [ -n "$STPLUG" ]; then
        echo "stplug-in:      $LUA_COUNT lua manifests ($STPLUG)"
      else
        echo "stplug-in:      missing (no Steam root with config/stplug-in)"
      fi
      if [ "$LUAAPPIDS" = 1 ]; then
        echo "luaappids.yaml: present (manual AdditionalApps list)"
      else
        echo "luaappids.yaml: none"
      fi

      echo
      echo "=== steam-config-nix ==="
      echo "Patcher:        $SCN_SERVICE"
      echo "Configured apps: $SCN_APPS"

      echo
      echo "=== LuaTools / Lumen ==="
      if [ "$L_INSTALLED" = 1 ]; then
        echo "Lumen:          installed"
      else
        echo "Lumen:          not installed (luatools.enable off?)"
      fi
      echo "Plugin:         $([ "$L_PLUGIN" = 1 ] && echo installed || echo missing)"
      echo "Running:        $([ "$L_RUNNING" = 1 ] && echo yes || echo no)"
      echo "CEF endpoint:   $([ "$L_CEFPORT" = 1 ] && echo attached || echo "waiting (restart Steam after the first switch)")"

      echo
      echo "=== Client-Updates ==="
      if [ -f "$STEAMCFG" ]; then
        echo "steam.cfg present -> client updates blocked"
      else
        echo "no steam.cfg -> client follows updates"
      fi
    '';

  # Convenience wrapper: update the consumer flake's inputs, rebuild through
  # whatever switcher is installed, then print the fresh status.
  mkUpdate =
    pkgs:
    pkgs.writeShellScriptBin "nix-crab-update" ''
      set -u

      if [ ! -f flake.nix ]; then
        echo "nix-crab-update: no flake.nix in $PWD - run from your configuration repo" >&2
        exit 1
      fi

      echo "== nix flake update =="
      nix flake update || exit 1

      if command -v nh >/dev/null 2>&1; then
        echo "== nh os switch =="
        nh os switch || echo "nh os switch failed (see output above)" >&2
        echo "== nh home switch =="
        nh home switch || echo "nh home switch failed (see output above)" >&2
      elif command -v nixos-rebuild >/dev/null 2>&1; then
        echo "== nixos-rebuild switch =="
        sudo nixos-rebuild switch --flake . || echo "nixos-rebuild failed (see output above)" >&2
        if command -v home-manager >/dev/null 2>&1; then
          echo "== home-manager switch =="
          home-manager switch --flake . || echo "home-manager switch failed (see output above)" >&2
        fi
      else
        echo "nix-crab-update: neither nh nor nixos-rebuild found - inputs updated, nothing switched" >&2
      fi

      echo
      echo "== nix-crab-status =="
      if command -v nix-crab-status >/dev/null 2>&1; then
        nix-crab-status || true
      else
        echo "nix-crab-status not on PATH (tools.enable off?)"
      fi
    '';

  module =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nix-crab;
      target = import ./target.nix { inherit config lib; };

      # nix-crab-status belongs to using nix-crab at all — the bug form asks
      # for `nix-crab-status --json`, and every feature ships state it
      # reports — so it installs with the first feature that is switched on.
      # Requiring a separate tools.enable on top of the feature was one
      # switch too many. tools.enable keeps its meaning for the maintenance
      # command (nix-crab-update), which no feature depends on.
      anyFeature =
        (cfg.slssteam.enable or false)
        || (cfg.slssteam-moon.enable or false)
        || (cfg.millennium.enable or false)
        || (cfg.netsock.enable or false)
        || (cfg.luatools.enable or false)
        || (cfg.downgrade.enable or false)
        || (cfg.steamidra.enable or false)
        || (cfg.accela.enable or false)
        || (cfg.tools.enable or false)
        || (cfg.steam.config.enable or false)
        || (cfg.steam.enable or null) == true
        || builtins.isAttrs (cfg.steam.enable or null);
    in
    {
      # HM-free: system-wide, like every NixOS program module does it. Writing
      # users.users.<user>.packages instead would recurse: the package gate
      # resolves the user, and resolution reads users.users (home-manager#594
      # documents the same trap).
      config = lib.mkIf (anyFeature && target.user != null) {
        environment.systemPackages = [
          (mkStatus pkgs)
        ]
        ++ lib.optionals cfg.tools.enable [ (mkUpdate pkgs) ];
      };
    };
}
