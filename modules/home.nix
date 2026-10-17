# User-scoped hub: SLSsteam config management + netsock.
# Unit shape: flake.nix takes `.module` (this file owns its options) and
# `.mkNetsock` (packages.netsock). Builders live here; flake.nix stays the
# only place that wires units into outputs, so package/option bits stay
# identical.
#
# HM-free: the managed config.yaml and the netsock.so link are written by
# activation snippets (modules/activate.nix) that run on every
# `nixos-rebuild switch` as the resolved user — no home-manager involved.
{
  steamnetsock,
  mkSlsSteam,
  mkSlsteamMoon,
}:
{
  # netsock as a buildable single-file package (nix build .#netsock). The
  # activation link below uses the raw input directly — same content, and the
  # launch-option snippet in the README points at the link path anyway.
  mkNetsock = pkgs: pkgs.runCommand "netsock.so" { } "cp ${steamnetsock} $out";

  module =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      cfg = config.programs.nix-crab;
      target = import ./target.nix { inherit config lib; };

      settingsFormat = pkgs.formats.yaml { };

      # Recursively drop nulls: every typed settings option (settings.nix)
      # defaults to null ("not written -> fork default wins"), so the generated
      # overlay only contains keys the user actually set. Pure builtins.
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

      # The typed settings (modules/settings.nix) are all-null until the user
      # sets something; extraSettings is the freeform escape hatch.
      typedSettings = builtins.removeAttrs cfg.slssteam.settings [ "extraSettings" ];
      userOverlay = stripNulls (typedSettings // cfg.slssteam.settings.extraSettings);

      # Flake-level default, merged under the user's own settings (so an
      # explicit value always wins). slsteam-moon ships `DisableCloud: no`
      # because the LuaTools stack it was built for ships CloudRedirect with it;
      # this flake does not ship CloudRedirect any more, and upstream's own
      # documentation says to use `yes` when no cloud-save hook is present —
      # otherwise Valve's backend rejects every upload and each unlocked game
      # shows a cloud-sync error. One flip, documented, overridable.
      flakeDefaults = {
        DisableCloud = true;
      };

      # What actually gets written when Nix manages the file.
      settingsOverlay = stripNulls (flakeDefaults // userOverlay);

      # Merge base: the ACTIVE fork's own default config (res/config.yaml). It
      # contains every key that fork's C++ reads, so the generated file never
      # trips "Config loading issues" notifications, and its comments survive
      # into the output. The user's overlay is applied on top — only what they
      # set overrides the documented default. Both bases come from the very
      # artefact the binaries describe (the pinned sls-steam source rev, the
      # moon release archive) — nothing hardcoded, and the pin means the tree
      # cannot drift under us.
      forkDefault =
        if cfg.slssteam.moon.enable then
          "${mkSlsteamMoon pkgs}/res/config.yaml"
        else
          "${mkSlsSteam pkgs}/res/config.yaml";

      # Two paths: with nothing to write (no settings, no flake defaults) the
      # fork default is used verbatim, with no re-serialization at all — yq's
      # merge of an EMPTY overlay degrades nulls to '' and switches the whole
      # document to flow style, so that case must never reach yq. Otherwise
      # yq-go deep-merges overlay over base. Only mikefarah's yq (pkgs.yq-go)
      # supports eval-all/select — plain pkgs.yq is kislyuk's jq wrapper and
      # silently wrote an empty file.
      managedConfig =
        if settingsOverlay == { } then
          forkDefault
        else
          pkgs.runCommand "config.yaml"
            {
              nativeBuildInputs = [ pkgs.yq-go ];
            }
            ''
              # The overlay is generated from JSON, so every AppId-shaped key
              # comes out quoted ('440': 480). Both SLSsteam's readers and the
              # LuaTools plugin match map keys line-wise as bare numbers, so
              # unquote integer keys — values are left alone (manifest gids
              # must stay strings).
              sed -E "s/^([[:space:]]*)['\"]([0-9]+)['\"]:/\1\2:/" \
                ${settingsFormat.generate "slssteam-overlay.yaml" settingsOverlay} > overlay.yaml
              # base * overlay: deep merge, overlay keys win, base comments preserved.
              yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
                ${forkDefault} overlay.yaml > $out
            '';

      # Keys of `settingsOverlay` itself — used to decide which live-file keys
      # Nix owns outright (they win) versus which stay runtime-owned.
      declaredKeys = builtins.attrNames settingsOverlay;

      # Keys something else writes into config.yaml at runtime: the LuaTools
      # plugin pins manifests (ManifestPins) and assigns fake AppIds
      # (FakeAppIds) from its UI, editing the file line by line between
      # switches. They are re-applied from the live file on activation unless
      # the user declared them here (a declared key is the user's — Nix wins
      # and the next activation resets it). Without this the managed file would
      # revert every plugin edit on the next switch.
      runtimeKeys = [
        "ManifestPins"
        "FakeAppIds"
      ];
      preserveKeys = builtins.filter (k: !(builtins.elem k declaredKeys)) runtimeKeys;

      # yq program keeping only the runtime keys that are present and non-null.
      # YAML out (not JSON): feeding yq a JSON overlay flips the merged result to
      # flow style and degrades every null to '', which breaks config.yaml.
      preserveExpr = "with_entries(select((${
        lib.concatStringsSep " or " (map (k: ".key == \"${k}\"") preserveKeys)
      }) and .value != null))";

      targetFile = "${target.home}/.config/SLSsteam/config.yaml";
      netsockLink = "${target.home}/.config/SLSsteam/tools/netsock/netsock.so";
      userScoped = target.user != null;

      # Upstream's `setup.sh install` copies the two audit libraries to
      # ~/.local/share/SLSsteam (cp ./bin/*) — the imperative layout every
      # non-NixOS install uses. An h3adcr-b-patched ~/.steam/steam/steam.sh
      # exports LD_AUDIT from exactly there just before exec, for EVERY GAME
      # LAUNCH: the Steam client honors the store path from slssteam.nix, but
      # games spawned through steam.sh get steam.sh's value, not the client's.
      # The old home-manager home.file carried this link (for a presence
      # check); dropping home-manager dropped it and games silently lost
      # SLSsteam while the client kept loading — recreate the canonical dir as
      # links into the SAME store path the LD_AUDIT override uses, so both
      # spellings resolve to one identical SLSsteam.
      slsShare = "${target.home}/.local/share/SLSsteam";
      slsPkg = if cfg.slssteam-moon.enable then mkSlsteamMoon pkgs else mkSlsSteam pkgs;
      injectionOn = cfg.slssteam.enable || cfg.slssteam-moon.enable;
    in
    {
      config = {
        assertions = [
          {
            assertion = userOverlay == { } || cfg.slssteam.manageConfig;
            message = ''
              programs.nix-crab.slssteam.settings is set, but manageConfig = false,
              so the values would be silently ignored. Set
              programs.nix-crab.slssteam.manageConfig = true; to have Nix write
              ~/.config/SLSsteam/config.yaml. (Leave both unset if an external
              tool such as SteaMidra should own the file.)
            '';
          }
          {
            assertion = cfg.netsock.games == [ ] || cfg.netsock.enable;
            message = ''
              programs.nix-crab.netsock.games needs programs.nix-crab.netsock.enable = true,
              otherwise there is no netsock.so for the launch option to point at.
            '';
          }
        ];

        # Written only when explicitly managed; otherwise the path is untouched
        # (SLSsteam creates its own default on first run, external tools edit it).
        #
        # A real file, not a store symlink: SLSsteam's file watcher and the
        # LuaTools plugin cannot write through a symlink (the plugin stages a
        # temp file and renames it over this path, which would silently break
        # out of the symlink and then collide with the next activation).
        system.activationScripts."nix-crab-slssteam-config" =
          lib.mkIf (cfg.slssteam.manageConfig && userScoped)
            (
              import ./activate.nix
                {
                  inherit lib pkgs;
                  user = target.user;
                  home = target.home;
                }
                "slssteam-config"
                ''
                  target="${targetFile}"
                  src="${managedConfig}"
                  # Temp lives next to the target so the final mv is a rename inside
                  # one directory: it replaces a legacy store symlink instead of
                  # writing through it.
                  candidate="$target.tmp.nix-crab"

                  mkdir -p "$(dirname "$target")"
                  # install, not cp: store files are 444, and the whole point is that
                  # SLSsteam and the LuaTools plugin can still write this file.
                  install -m 644 "$src" "$candidate"
                  ${
                    if preserveKeys == [ ] then
                      "true"
                    else
                      ''
                        # Re-apply the keys something else owns at runtime (the
                        # LuaTools plugin edits them between switches), unless the
                        # user declared them — a declared key is the user's, and Nix
                        # resetting it is the point.
                        if [ -f "$target" ]; then
                          runtime_overlay="$target.tmp.nix-crab.runtime"
                          # The comments are stripped and the emptiness checked with
                          # yq itself: with_entries keeps the source file's comments
                          # (merging them duplicates every comment block), and an
                          # "empty" overlay is only empty as a value — piping it into
                          # the merge below degrades nulls to empty strings and flips
                          # the document to flow style.
                          {
                            yq eval \
                              ${lib.escapeShellArg preserveExpr} "$target" 2>/dev/null \
                              || true
                          } | grep -v '^#' > "$runtime_overlay" || true

                          if [ "$(yq eval 'length' "$runtime_overlay" 2>/dev/null || echo 0)" != "0" ]; then
                            if yq eval-all \
                              'select(fileIndex == 0) * select(fileIndex == 1)' \
                              "$src" "$runtime_overlay" > "$candidate" 2>/dev/null; then
                              :
                            else
                              install -m 644 "$src" "$candidate"
                            fi
                          fi
                          rm -f "$runtime_overlay"
                        fi
                      ''
                  }

                  # Same content as the live file -> leave it alone (SLSsteam watches
                  # this file; rewriting it unchanged would look like a change).
                  if [ -f "$target" ] && cmp -s "$candidate" "$target"; then
                    rm -f "$candidate"
                    echo "nix-crab: SLSsteam config.yaml is up to date"
                  else
                    mv -f "$candidate" "$target"
                    own "$target"
                    echo "nix-crab: installed SLSsteam config.yaml to $target"
                  fi
                ''
            );

        # netsock: per-game multiplayer fix, only where it is asked for.
        system.activationScripts."nix-crab-netsock" = lib.mkIf (cfg.netsock.enable && userScoped) (
          import ./activate.nix
            {
              inherit lib pkgs;
              user = target.user;
              home = target.home;
            }
            "netsock"
            ''
              link="${netsockLink}"
              mkdir -p "$(dirname "$link")"
              # -T: a store dir would otherwise nest under a stale symlink.
              ln -sfnT "${steamnetsock}" "$link"
              own "$(dirname "$link")"
              echo "nix-crab: linked netsock.so to $link"
            ''
        );

        # The other half of injection: keep upstream's canonical install dir
        # (~/.local/share/SLSsteam) alive, since steam.sh-launched games read
        # LD_AUDIT from there (see slsShare above).
        system.activationScripts."nix-crab-slssteam-share" = lib.mkIf (injectionOn && userScoped) (
          import ./activate.nix
            {
              inherit lib pkgs;
              user = target.user;
              home = target.home;
            }
            "slssteam-share"
            ''
              share="${slsShare}"
              mkdir -p "$share"
              # -f replaces h3adcr-b's stale regular copy (a 0-byte
              # library-inject.so), -T stops a symlinked dir from nesting.
              # Both targets are the injected fork's own store files.
              ln -sfnT "${slsPkg}/SLSsteam.so" "$share/SLSsteam.so"
              ln -sfnT "${slsPkg}/library-inject.so" "$share/library-inject.so"
              own "$share"
              echo "nix-crab: linked SLSsteam into $share"
            ''
        );
      };
    };
}
