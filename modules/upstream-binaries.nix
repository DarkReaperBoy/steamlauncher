# Upstream release binaries, driven by upstream.lock.json.
#
# Every project here ships its own prebuilt artifact on GitHub Releases with a
# `<asset>.sha256` sidecar. Fetching that instead of compiling from source:
#   - replaces a 32-bit C++ build and two bun/cmake toolchains with a download,
#   - removes three flake inputs (the sources are no longer needed at all),
#   - makes the daily CI a fetch rather than a full rebuild, and
#   - tracks each project's releases, refreshed by ci/update-binaries.sh.
#
# The lock file is generated — never edit it by hand. Every output keeps the
# layout the consuming code already expects (the same paths the source builds
# and flake inputs produced), so a version bump changes nothing but bytes.
{ }:
let
  upstream = builtins.fromJSON (builtins.readFile ../upstream.lock.json);

  # {version} = the tag verbatim (v3.6.1), {ver} = without its leading v (3.6.1)
  assetFor =
    name:
    let
      u = upstream.${name};
      ver = u.version;
      nov = builtins.substring 1 (builtins.stringLength ver - 1) ver;
    in
    "https://github.com/${u.repo}/releases/download/${ver}/${
      builtins.replaceStrings [ "{version}" "{ver}" ] [ ver nov ] u.asset
    }";

  srcFor =
    pkgs: name:
    pkgs.fetchurl {
      url = assetFor name;
      hash = upstream.${name}.hash;
    };
  versionOf = name: upstream.${name}.version;
in
rec {
  # slsteam-moon's own release zip: bin/SLSsteam.so + bin/library-inject.so
  # (the two injected objects, same names as the source build) and
  # res/config.yaml — the merge base for the managed config, now taken from
  # the very archive the binaries come from.
  mkSlsteamMoon =
    pkgs:
    pkgs.runCommand "slsteam-moon-${versionOf "slsteam-moon"}"
      {
        nativeBuildInputs = [
          pkgs.unzip
          pkgs.binutils
        ];
        meta = {
          description = "SLSsteam fork with a native Lua manifest importer (slsteam-moon)";
          homepage = "https://github.com/swwayps/slsteam-moon";
          license = pkgs.lib.licenses.agpl3Only;
          platforms = pkgs.lib.platforms.linux;
        };
      }
      ''
        mkdir -p "$out/res"
        unzip -q ${srcFor pkgs "slsteam-moon"}
        cp slsteam-moon-*-lumen/bin/SLSsteam.so slsteam-moon-*-lumen/bin/library-inject.so "$out/"
        cp slsteam-moon-*-lumen/res/config.yaml "$out/res/"

        # Dependency check, done on the artefacts themselves: neither object
        # links OpenSSL or anything unusual — only libstdc++, libgcc_s, libm and
        # libc, all supplied by the Steam runtime the objects are loaded into.
        # So no patchelf, no rpath: nothing to rescue. Re-run the check if a
        # future release grows a NEEDED entry (readelf -d) before assuming.
        for so in "$out/SLSsteam.so" "$out/library-inject.so"; do
          if readelf -d "$so" | grep -Eq 'libcrypto|libssl|libcurl'; then
            echo "error: $so now links a library the Steam runtime may not ship —" >&2
            echo "       teach modules/upstream-binaries.nix how to satisfy it." >&2
            exit 1
          fi
        done
      '';

  # Lumen's release zip is already the runtime layout (the `lumen` binary plus
  # its lua/ tree) — the same thing the old wheel assembly produced.
  mkLumen =
    pkgs:
    pkgs.runCommand "lumen-${versionOf "lumen"}" { } ''
      mkdir -p "$out"
      ${pkgs.unzip}/bin/unzip -q ${srcFor pkgs "lumen"} -d "$out"
      chmod +x "$out/lumen"
    '';

  # The LuaTools plugin's release zip is the canonical plugin/ tree (plugin.json,
  # backend/, public/), already stripped of runtime state.
  mkLuatools =
    pkgs:
    pkgs.runCommand "luatools-${versionOf "luatools"}" { } ''
      mkdir -p "$out"
      ${pkgs.unzip}/bin/unzip -q ${srcFor pkgs "luatools"} -d "$out"
      chmod +x "$out"/backend/scripts/*.sh "$out"/backend/bin/7zz
    '';

  # Millennium's release tarball carries the same six objects its source build
  # installs into $out/lib (libmillennium_x86.so, the two bootstrap shims, the
  # lua VM, ...) under usr/lib/millennium/. modules/millennium.nix swaps this in
  # for the overlay's own build, so the overlay's steam wiring keeps consuming
  # it unchanged — no cmake, no bun, no TypeScript toolchain.
  mkMillennium =
    pkgs:
    pkgs.runCommand "millennium-${versionOf "millennium"}" { } ''
      mkdir -p "$out/lib"
      tar xf ${srcFor pkgs "millennium"}
      cp -a usr/lib/millennium/. "$out/lib/"
    '';
}
