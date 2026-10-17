# Resolve programs.nix-crab.user (or the auto-detected single normal user) to
# the user + home directory every user-scoped feature writes into. Pure
# function, not a module: feature modules import it with their own
# `{ config, lib }`, so there is one resolution rule and no extra option.
#
#   target.user -> "alice" or null (ambiguous/absent)
#   target.home -> users.users.<user>.home, or null when user is null (an
#                  explicit but nonexistent user also yields null; user.nix
#                  reports that with a proper assertion instead of an
#                  attribute error).
{ config, lib }:
let
  normalUsers = lib.attrNames (lib.filterAttrs (_: u: u.isNormalUser or false) config.users.users);
  detected = if lib.length normalUsers == 1 then lib.head normalUsers else null;
  user = if config.programs.nix-crab.user != null then config.programs.nix-crab.user else detected;
  home =
    if user != null && config.users.users ? ${user} then config.users.users.${user}.home else null;
in
{
  inherit
    normalUsers
    detected
    user
    home
    ;
}
