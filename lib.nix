# Shared derivation builders. Used twice for everything: flake `packages.*`
# (nix build / nix profile install / nix run) and the NixOS/home modules
# (programs.nix-crab.*). One definition, two surfaces — a package output and
# an enable option are always the same bits.
#
# Every function takes `pkgs` as its only argument so it can be instantiated
# per system in flake.nix and per module eval in the modules.
{
  # .so / tool inputs
  sls-steam,
  slsteam-moon,
  enter-the-wired,
  cloudredirect,
  cloudredirect-moon,
  cloudredirect-cli,
  steamnetsock,
  steamidra,
  lumen,
  luatools-moon,
}:
rec {
  # Recursively drop nulls: every typed settings option defaults to null
  # ("not written -> fork default wins"), so the generated overlay only
  # contains keys the user actually set. Pure builtins (lib.nix has no lib).
  stripNulls =
    v:
    if builtins.isAttrs v then
      builtins.mapAttrs (_: stripNulls) (
        builtins.listToAttrs (
          builtins.concatMap (
            n:
            if v.${n} == null then
              [ ]
            else
              [
                {
                  name = n;
                  value = v.${n};
                }
              ]
          ) (builtins.attrNames v)
        )
      )
    else
      v;

  # Newest tag from the pinned /tags JSON (GitHub lists tags newest-first).
  # Re-lock with `nix flake update` to track a new release. Strip a leading
  # "v" without pkgs.lib (this value is needed before any pkgs exists).
  steamidraVersion =
    let
      name = (builtins.head (builtins.fromJSON (builtins.readFile steamidra))).name;
    in
    if builtins.substring 0 1 name == "v" then
      builtins.substring 1 (builtins.stringLength name) name
    else
      name;

  # -- SLSsteam -------------------------------------------------------------

  # Upstream SLSsteam artefacts (SLSsteam.so + library-inject.so), same as the
  # official wiki's NixOS instructions use.
  mkSlsSteam = pkgs: sls-steam.packages.${pkgs.stdenv.hostPlatform.system}.sls-steam;
  mkTicketGrabber = pkgs: sls-steam.packages.${pkgs.stdenv.hostPlatform.system}.ticket-grabber;
  mkSchemaGrabber = pkgs: sls-steam.packages.${pkgs.stdenv.hostPlatform.system}.schema-grabber;

  # slsteam-moon: fork with a native Lua manifest importer. No flake, built
  # from source with the same 32-bit toolchain upstream uses in its own
  # nix-modules/default.nix.
  mkSlsteamMoon =
    pkgs:
    pkgs.pkgsi686Linux.stdenv.mkDerivation {
      pname = "slsteam-moon";
      version = "0.0.0";
      src = slsteam-moon;
      nativeBuildInputs = with pkgs; [ pkg-config ];
      buildInputs = with pkgs.pkgsi686Linux; [
        openssl
        curl
      ];
      # slsteam-moon's headers (utils.hpp, patterns.hpp, memhlp.hpp, hooks.hpp)
      # use uint*_t without including <cstdint>, relying on transitive includes
      # that GCC 14+ removed. Force-include it for every TU instead of patching
      # each header — also covers any future missing-include rot.
      env.NIX_CFLAGS_COMPILE = "-include cstdint";
      # pattern-refresh is a native host helper we don't need; only the two
      # Steam-loaded i386 objects are injected.
      buildPhase = "make bin/SLSsteam.so bin/library-inject.so";
      # -O3 -flto over ~100 translation units; the Makefile only marks `clean`
      # and `rebuild` as .NOTPARALLEL, so the object targets take -j fine.
      enableParallelBuilding = true;
      # embed-version.sh / embed-config.sh are invoked by the Makefile and
      # carry a #!/bin/bash shebang that doesn't exist in the sandbox.
      postPatch = ''
        patchShebangs embed-version.sh embed-config.sh
      '';
      installPhase = ''
        mkdir -p "$out"
        cp bin/SLSsteam.so "$out/"
        cp bin/library-inject.so "$out/"
      '';
      meta = {
        description = "SLSsteam fork with a Lua manifest importer (slsteam-moon)";
        homepage = "https://github.com/swwayps/slsteam-moon";
        license = pkgs.lib.licenses.agpl3Only;
        platforms = pkgs.lib.platforms.linux;
      };
    };

  # -- ACCELA ---------------------------------------------------------------

  # ACCELA's AppImage bundles its own Qt (PyQt6 + Qt 6.11.0). When launched
  # from a KDE/Qt session, QT_PLUGIN_PATH leaks nixpkgs Qt plugin dirs into
  # the bwrap sandbox; Qt then loads version-mismatched plugins
  # (private-ABI symbol errors) and dies. Fix: clean Qt env at launch.
  # zstd/icu/xcb-util-cursor are already in enter-the-wired's extraPkgs.
  mkAccela =
    pkgs:
    let
      accela = enter-the-wired.packages.${pkgs.stdenv.hostPlatform.system}.default;
    in
    pkgs.runCommand "accela"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
        mkdir -p $out/bin
        makeWrapper ${accela}/bin/accela $out/bin/accela \
          --unset QT_PLUGIN_PATH \
          --unset QT_QPA_PLATFORM_PLUGIN_PATH \
          --unset QTWEBKIT_PLUGIN_PATH \
          --unset QML2_IMPORT_PATH
      '';
  accelaPkg = pkgs: enter-the-wired.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # -- CloudRedirect / netsock ---------------------------------------------

  mkCloudredirectCli =
    pkgs:
    pkgs.stdenv.mkDerivation {
      pname = "cloud_redirect_cli";
      version = "0.0.0";
      src = cloudredirect-cli;
      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;
      installPhase = ''
        runHook preInstall
        install -Dm755 "$src" "$out/bin/cloud_redirect_cli"
        runHook postInstall
      '';
      meta.mainProgram = "cloud_redirect_cli";
    };

  # The pinned hooks as buildable single-file packages
  # (`nix build .#cloudredirect` -> the .so itself).
  mkCloudredirect = pkgs: pkgs.runCommand "cloud_redirect.so" { } "cp ${cloudredirect} $out";
  mkCloudredirectMoon =
    pkgs:
    pkgs.runCommand "cloud_redirect-moon.so" { } "cp ${cloudredirect-moon}/cloud_redirect.so $out";

  mkNetsock = pkgs: pkgs.runCommand "netsock.so" { } "cp ${steamnetsock} $out";

  # -- SteaMidra (SFF) ------------------------------------------------------

  # The 520 MiB AppImage is NOT fetched by Nix: SFF has no versionless asset
  # URL, so a Nix fetch would need a hand-bumped SRI hash for every release.
  # The launcher downloads exactly the locked version on first run. Uses $HOME
  # so the package works imperatively; the home module's desktop entry points
  # its Icon= at the absolute path from config.home.homeDirectory.
  mkSteamidra =
    pkgs:
    let
      dataDir = "$HOME/.local/share/SteaMidra";
    in
    pkgs.writeShellScriptBin "steamidra" ''
      set -euo pipefail
      app="${dataDir}/SteaMidra.AppImage"

      if [ "$(cat "${dataDir}/.version" 2>/dev/null || true)" != "${steamidraVersion}" ]; then
        ${pkgs.libnotify}/bin/notify-send -a SteaMidra \
          "Downloading SteaMidra ${steamidraVersion}" "About 520 MiB, this takes a while." || true
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        ${pkgs.curl}/bin/curl -fL --progress-bar -o "$tmp/sff.zip" \
          "https://github.com/Midrags/SFF/releases/download/v${steamidraVersion}/SteaMidra-${steamidraVersion}-linux.zip"
        ${pkgs.unzip}/bin/unzip -qo "$tmp/sff.zip" "SteaMidra*.AppImage" "*.png" -d "$tmp"
        mkdir -p "${dataDir}"
        mv "$tmp"/SteaMidra*.AppImage "$app"
        chmod +x "$app"
        mv "$tmp"/*.png "${dataDir}/steamidra.png"
        echo "${steamidraVersion}" > "${dataDir}/.version"
        ${pkgs.libnotify}/bin/notify-send -a SteaMidra "SteaMidra ${steamidraVersion} ready" || true
      fi

      export APPIMAGE="$app"
      export QTWEBENGINE_DISABLE_SANDBOX=1
      exec ${pkgs.appimage-run}/bin/appimage-run "$app" "$@"
    '';

  # -- LuaTools / Lumen -----------------------------------------------------

  # Build the two dists into store paths. The home module copies them into
  # real directories because Lumen and the plugin write at runtime (config,
  # fetched manifest packs, plugin state).
  mkLumen =
    pkgs:
    pkgs.runCommand "lumen-dist" { } ''
      mkdir -p "$out"
      ${pkgs.unzip}/bin/unzip -qo ${lumen}/dist/lumen-linux.zip -d "$out"
      chmod +x "$out/lumen"
    '';

  mkLuatools =
    pkgs:
    pkgs.runCommand "luatools-moon-dist" { } ''
      mkdir -p "$out"
      cp -r ${luatools-moon}/plugin/. "$out/"
      rm -rf "$out/backend/data" "$out/backend/temp_dl"
      rm -f "$out/backend/lua_runtime.log" "$out/backend/loadedappids.txt" "$out/backend/appidlogs.txt"
      chmod +x "$out/backend/scripts/"*.sh
      chmod +x "$out/backend/bin/7zz"
    '';

  # -- nix-crab tooling -----------------------------------------------------

  # Diagnostic command: client version, SLSsteam config, netsock, CloudRedirect
  # status (incl. which hook is wired up), injection fork, LuaTools state.
  mkStatus =
    pkgs:
    let
      # Both CloudRedirect hooks are store paths known at Nix build time.
      # Resolve the ~/.local/share link against them to report which one is
      # actually wired up (the home link mirrors the LD_PRELOAD choice).
      # Upstream is a `type = "file"` input (the .so itself); moon is a git
      # input with the .so at the repo root.
      CR_UP = cloudredirect;
      CR_MOON = "${cloudredirect-moon}/cloud_redirect.so";
    in
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
      CRLINK="$HOME/.local/share/CloudRedirect/cloud_redirect.so"

      CR_UP="${CR_UP}"
      CR_MOON="${CR_MOON}"
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
      DUPES=0
      if [ "$CONFIG_PRESENT" = 1 ]; then
        DISABLECLOUD="$(val DisableCloud)"
        PLAYNOTOWNED="$(val PlayNotOwnedGames)"
        SAFEMODE="$(val SafeMode)"
        DUPES=$(grep -c '^DisableCloud:' "$CFG")
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
          *sls-steam*)    INJECTION="upstream SLSsteam" ;;
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

      # -- CloudRedirect -------------------------------------------------------
      CR_ENABLED=0
      case "$DISABLECLOUD" in
        no | false) CR_ENABLED=1 ;;
      esac
      CR_HOOK="missing"
      if [ -e "$CRLINK" ]; then
        CR_TARGET="$(readlink -f "$CRLINK" 2>/dev/null || true)"
        case "$CR_TARGET" in
          "$CR_MOON") CR_HOOK="moon (LuaTools)" ;;
          "$CR_UP")   CR_HOOK="upstream" ;;
          *)          CR_HOOK="other: $CR_TARGET" ;;
        esac
      fi
      CR_CLI=0
      [ -x "$HOME/.local/share/CloudRedirect/cloud_redirect_lib" ] && CR_CLI=1
      CR_FLATPAK=0
      [ -d "$HOME/.local/share/flatpak/app/org.cloudredirect.CloudRedirect" ] && CR_FLATPAK=1

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
        printf '"slssteam":{"config_present":%s,"disable_cloud":%s,"play_not_owned":%s,"safe_mode":%s,"disable_cloud_duplicates":%s,"netsock_present":%s},' \
          "$(json_bool "$CONFIG_PRESENT")" "$(json_str "$DISABLECLOUD")" "$(json_str "$PLAYNOTOWNED")" "$(json_str "$SAFEMODE")" "$DUPES" "$(json_bool "$NETSOOK_PRESENT")"
        printf '"injection":%s,' "$(json_str "$INJECTION")"
        printf '"games":{"stplug_in_dir":%s,"lua_manifests":%s,"luaappids_yaml":%s},' \
          "$(json_str "$STPLUG")" "$LUA_COUNT" "$(json_bool "$LUAAPPIDS")"
        printf '"cloudredirect":{"enabled":%s,"hook":%s,"cli_present":%s,"flatpak_installed":%s},' \
          "$(json_bool "$CR_ENABLED")" "$(json_str "$CR_HOOK")" "$(json_bool "$CR_CLI")" "$(json_bool "$CR_FLATPAK")"
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
      echo "=== CloudRedirect ==="
      # Both spellings: SLSsteam and SteaMidra write YAML 1.2 true/false, a
      # hand-edited or headcrab-era config carries YAML 1.1 yes/no.
      if [ "$CR_ENABLED" = 1 ]; then
        echo "Status: Enabled (DisableCloud: $DISABLECLOUD)"
      else
        echo "Status: Disabled"
      fi
      echo "Hook:           $CR_HOOK"
      echo "CLI:            $([ "$CR_CLI" = 1 ] && echo present || echo missing)"
      echo "Flatpak:        $([ "$CR_FLATPAK" = 1 ] && echo installed || echo not installed)"

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

  # Client downgrade: pins the Steam client to headcrab's compatible build.
  mkDowngrade =
    pkgs:
    let
      mkBin =
        {
          name,
          url,
          hash,
        }:
        pkgs.stdenv.mkDerivation {
          inherit name;
          src = pkgs.fetchurl {
            inherit url;
            sha256 = hash;
          };
          dontUnpack = true;
          dontConfigure = true;
          dontBuild = true;
          installPhase = ''
            runHook preInstall
            install -Dm755 "$src" "$out/bin/${name}"
            runHook postInstall
          '';
        };

      # dgsc/dlm were deleted from h3adcr-b-modul3s' main branch on 2026-09-28
      # ("Delete dgsc" / "Delete dlm" — upstream is mid-migration), which broke
      # the raw refs/heads/main URLs. Pin to the last commit that still has
      # them; the binaries are byte-identical to the previously pinned hashes.
      dgsc = mkBin {
        name = "nix-crab-dgsc";
        url = "https://raw.githubusercontent.com/Deadboy666/h3adcr-b-modul3s/8c36338994fdb085fa07b887f71d64362af51c1d/dgsc";
        hash = "sha256-CJUdjpmNl9xKNcuTdsiIuY+l37Pb8D0vyWKZQD/QBCI=";
      };

      dlm = mkBin {
        name = "nix-crab-dlm";
        url = "https://raw.githubusercontent.com/Deadboy666/h3adcr-b-modul3s/8c36338994fdb085fa07b887f71d64362af51c1d/dlm";
        hash = "sha256-ly66uMEsDEfvfTn5geCKMzovEfrmlWqzuTZlORecdxQ=";
      };
    in
    # sources.txt and the client manifest are per-client-build data: they
    # change with every Steam release, so pinning them as fetchurl hashes
    # rots the module on the next client bump — both hashes had already gone
    # stale. Fetch them at runtime instead, exactly like headcrab.sh does;
    # sources.txt is regenerated from the manifest by upstream's
    # update-sources.py, so latest-of-both is the consistent pair.
    pkgs.writeShellScriptBin "nix-crab-downgrade" ''
      set -euo pipefail

      PKG="$HOME/.steam/steam/package"
      STEAMCFG="$HOME/.steam/steam/steam.cfg"
      mkdir -p "$(dirname "$STEAMCFG")" "$PKG"

      if [ ! -f "$STEAMCFG" ]; then
        cat ${./modules/steam.cfg} >"$STEAMCFG"
      fi

      rm -f "$PKG"/*

      MANIFEST_URL="https://raw.githubusercontent.com/Deadboy666/SteamTracking/refs/heads/headcrab/ClientManifest/steam_client_ubuntu12"
      SOURCES_URL="https://raw.githubusercontent.com/Deadboy666/h3adcr-b-modul3s/main/sources.txt"

      echo "Downloading client manifest..."
      ${pkgs.curl}/bin/curl -fsSL -o "$PKG/steam_client_ubuntu12" "$MANIFEST_URL"

      echo "Downloading package list..."
      ${pkgs.curl}/bin/curl -fsSL -o "$PKG/sources.txt" "$SOURCES_URL"

      echo "Fetching client files (nix-crab-dlm)..."
      cd "$PKG"
      ${dlm}/bin/nix-crab-dlm --input-file "$PKG/sources.txt" --max-concurrent 16

      echo "Starting nix-crab-dgsc on :1666..."
      ${dgsc}/bin/nix-crab-dgsc --port 1666 --silent &
      DGSC_PID=$!
      trap 'kill "$DGSC_PID" 2>/dev/null || true' EXIT

      echo "Applying client via Steam override..."
      steam -forcesteamupdate -forcepackagedownload -overridepackageurl http://localhost:1666/ -exitsteam

      echo "Done."
    '';
}
