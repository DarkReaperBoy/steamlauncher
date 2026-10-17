# Wrap a shell body as a nix-crab activation snippet — the HM-free
# replacement for home-manager's home.activation.
#
# The body runs inside the system activation script on every
# `nixos-rebuild switch` (as root, after specialfs + users), with the target
# user's HOME/USER/LOGNAME exported and two helpers in scope:
#
#   run <cmd>...   plain execution (kept for familiarity with the old dag)
#   own <path>...  chown to the target user — only when running as root, so
#                  the same snippet runs unprivileged in the test harness
#
# NixOS runs snippets inline under `trap _status=1 ERR` (failures are
# recorded, activation continues, `activate` exits nonzero). The `set -eu`
# lives in a subshell so our strictness cannot leak into other snippets, and
# the `|| { ... _status=1; }` tail is what reports a failed subshell to that
# trap, since commands on the left of `||` are exempt from it.
#
#   import ./activate.nix { inherit pkgs lib user home; } "name-of-entry" ''
#     ...body...
#   ''
{
  lib,
  pkgs,
  user,
  home,
}:
name: body: {
  deps = [
    "specialfs"
    "users"
  ];
  text = ''
    #### nix-crab activation snippet: ${name}
    # target user baked at eval time (tests run the same text unprivileged)
    if ! (
      set -eu
      export HOME=${lib.escapeShellArg home}
      export USER=${lib.escapeShellArg user}
      export LOGNAME=${lib.escapeShellArg user}
      export PATH=${
        lib.makeBinPath (
          with pkgs;
          [
            coreutils
            findutils
            gnugrep
            gnused
            gawk
            curl
            jq
            unzip
            yq-go
          ]
        )
      }:$PATH
      run() { "$@"; }
      own() {
        if [ "$(id -u)" = 0 ] && id ${lib.escapeShellArg user} >/dev/null 2>&1; then
          chown -R ${lib.escapeShellArg user} "$@" 2>/dev/null || true
        fi
      }
      ${body}
    ); then
      echo "nix-crab: activation snippet '${name}' failed" >&2
      _status=1
    fi
  '';
}
