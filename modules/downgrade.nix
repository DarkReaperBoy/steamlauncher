# Client downgrade feature: pins the Steam client to headcrab's compatible
# build. Unit shape: flake.nix takes `.module` and `.mkDowngrade` (the
# packages.nix-crab-downgrade output) — same derivation both places.
{ }:
rec {
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
        cat ${./steam.cfg} >"$STEAMCFG"
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

  module =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.programs.nix-crab.downgrade = {
        enable = lib.mkEnableOption "nix-crab client downgrade";
        package = lib.mkOption {
          type = lib.types.package;
          default = mkDowngrade pkgs;
          description = "The nix-crab-downgrade wrapper script";
        };
      };

      config = lib.mkIf config.programs.nix-crab.downgrade.enable {
        environment.systemPackages = [ config.programs.nix-crab.downgrade.package ];
      };
    };
}
