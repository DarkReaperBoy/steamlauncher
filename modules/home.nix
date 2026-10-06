# Home-side hub: SLSsteam config management, CloudRedirect user side, netsock.
# Unit shape: flake.nix takes `.module` (this file owns its options) and
# `.mkNetsock` (packages.netsock). Builders it needs from sibling features are
# re-used by importing those units here — flake.nix stays the only place that
# wires units into outputs, and package/option bits stay identical.
{
  nix-flatpak,
  steamnetsock,
  cloudredirect,
  cloudredirect-moon,
  cloudredirect-cli,
  sls-steam,
  slsteam-moon,
}:
let
  slssteamUnit = import ./slssteam.nix { inherit sls-steam slsteam-moon; };
  cloudredirectUnit = import ./cloudredirect.nix {
    inherit
      cloudredirect
      cloudredirect-moon
      cloudredirect-cli
      ;
  };
in
{
  # netsock as a buildable single-file package (nix build .#netsock). The
  # home.file link below uses the raw input directly — same content, and the
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

      slssteamPkg = slssteamUnit.mkSlsSteam pkgs;
      cloudredirectCli = cloudredirectUnit.mkCloudredirectCli pkgs;

      # The typed settings (modules/settings.nix) are all-null until the user sets
      # something; extraSettings is the freeform escape hatch. The overlay written
      # to config.yaml is the merge of both with nulls stripped — so an untouched
      # settings set produces an empty overlay.
      typedSettings = builtins.removeAttrs cfg.slssteam.settings [ "extraSettings" ];
      settingsOverlay = stripNulls (typedSettings // cfg.slssteam.settings.extraSettings);

      # Merge base: the ACTIVE fork's own default config (res/config.yaml from the
      # pinned input). It contains every key that fork's C++ reads, so the
      # generated file never trips "Config loading issues" notifications, and its
      # comments survive into the output. The user's overlay is applied on top —
      # only what they set overrides the documented default. The key set tracks
      # upstream with nix flake update; nothing is hardcoded here.
      forkDefault =
        if cfg.slssteam.moon.enable then
          "${slsteam-moon}/res/config.yaml"
        else
          "${sls-steam}/res/config.yaml";

      # Two paths: with an empty overlay the fork default is used verbatim (no
      # re-serialization — yq's merge of an empty overlay degrades nulls to '' and
      # switches to flow style); otherwise yq-go deep-merges overlay over base.
      # Only mikefarah's yq (pkgs.yq-go) supports eval-all/select — plain
      # pkgs.yq is kislyuk's jq wrapper and silently wrote an empty file.
      managedConfig =
        if settingsOverlay == { } then
          forkDefault
        else
          pkgs.runCommand "config.yaml"
            {
              nativeBuildInputs = [ pkgs.yq-go ];
            }
            ''
              # base * overlay: deep merge, overlay keys win, base comments preserved.
              yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
                ${forkDefault} ${settingsFormat.generate "slssteam-overlay.yaml" settingsOverlay} > $out
            '';
    in
    {
      imports = [
        ./settings.nix
        nix-flatpak.homeManagerModules.nix-flatpak
      ];

      options.programs.nix-crab = {
        slssteam.manageConfig = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether Nix manages ~/.config/SLSsteam/config.yaml. Disabled by
            default so tools like SteaMidra can edit the file without it being
            reset on the next home-manager switch. When enabled, the file is the
            active fork's default config merged with `settings`.
          '';
        };

        slssteam.moon.enable = lib.mkEnableOption ''
          slsteam-moon as the config merge base (programs.nix-crab.slssteam.
          settings is applied over slsteam-moon's default config instead of
          upstream SLSsteam's). Set this together with the NixOS module's
          programs.nix-crab.slssteam-moon.enable — the two modules are
          evaluated separately, same as cloudredirect.moon.
        '';

        cloudredirect.enable = lib.mkEnableOption ''
          the CloudRedirect user side: installs org.cloudredirect.CloudRedirect
          as a user Flatpak (remotes flathub + cloudredirect), links the hook
          and CLI where the app checks for them, and puts cloud_redirect_cli on
          PATH. Set together with the NixOS module's cloudredirect.enable.
        '';

        cloudredirect.moon.enable = lib.mkEnableOption ''
          the cloudredirect-moon hook instead of upstream CloudRedirect for the
          ~/.local/share/CloudRedirect/cloud_redirect.so link. Must match the NixOS
          module's programs.nix-crab.cloudredirect.moon.enable. Only enable for
          the LuaTools stack.
        '';

        netsock.enable = lib.mkEnableOption ''
          installing netsock (steamnetsock-patch) to
          ~/.config/SLSsteam/tools/netsock/netsock.so for use as a per-game launch
          option (LD_AUDIT=.../netsock.so %command%). Never injected globally.
        '';
      };

      config = {
        assertions = [
          {
            assertion = settingsOverlay == { } || cfg.slssteam.manageConfig;
            message = ''
              programs.nix-crab.slssteam.settings is set, but manageConfig = false,
              so the values would be silently ignored. Set
              programs.nix-crab.slssteam.manageConfig = true; to have Nix write
              ~/.config/SLSsteam/config.yaml. (Leave both unset if an external
              tool such as SteaMidra should own the file.)
            '';
          }
        ];

        # Written only when explicitly managed; otherwise the path is untouched
        # (SLSsteam creates its own default on first run, external tools edit it).
        xdg.configFile."SLSsteam/config.yaml" = lib.mkIf cfg.slssteam.manageConfig {
          source = managedConfig;
        };

        services.flatpak = lib.mkIf cfg.cloudredirect.enable {
          packages = [
            {
              appId = "org.cloudredirect.CloudRedirect";
              origin = "cloudredirect";
            }
          ];
          # The app's SLSsteam check follows ~/.local/share/SLSsteam/SLSsteam.so
          # (see home.file below) into the Nix store, so the sandbox has to see the
          # store — with only filesystems=home that symlink is dangling inside the
          # Flatpak and the check fails.
          overrides.settings."org.cloudredirect.CloudRedirect".Context.filesystems = [
            "/nix/store:ro"
          ];
          remotes = [
            {
              name = "flathub";
              location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
            }
            {
              name = "cloudredirect";
              location = "https://raw.githubusercontent.com/Selectively11/CloudRedirect/refs/heads/gh-pages/cloudredirect.flatpakrepo";
            }
          ];
        };

        home.file = {
          # netsock: per-game multiplayer fix, only where it is asked for.
          ".config/SLSsteam/tools/netsock/netsock.so" = lib.mkIf cfg.netsock.enable {
            source = steamnetsock;
          };

          # The CloudRedirect app's prerequisite check stats
          # $XDG_DATA_HOME/SLSsteam/SLSsteam.so (the imperative h3adcr-b layout).
          # Nix keeps SLSsteam in the store, so without this link the app shows
          # "SLSsteam: Not found". Presence is all the check looks at, so
          # upstream's .so stands in for either fork.
          ".local/share/SLSsteam/SLSsteam.so" = lib.mkIf cfg.cloudredirect.enable {
            source = "${slssteamPkg}/SLSsteam.so";
          };
          ".local/share/CloudRedirect/cloud_redirect_lib" = lib.mkIf cfg.cloudredirect.enable {
            source = "${cloudredirectCli}/bin/cloud_redirect_cli";
          };
          # Same deal for CloudRedirect's own deploy check: it stats
          # $XDG_DATA_HOME/CloudRedirect/cloud_redirect.so and reports "failed to
          # deploy" without it. Follow the same hook choice as the LD_PRELOAD in
          # modules/cloudredirect.nix so the app's status matches what is injected.
          ".local/share/CloudRedirect/cloud_redirect.so" = lib.mkIf cfg.cloudredirect.enable {
            source =
              if cfg.cloudredirect.moon.enable then "${cloudredirect-moon}/cloud_redirect.so" else cloudredirect;
          };
        };

        home.packages = lib.optionals cfg.cloudredirect.enable [ cloudredirectCli ];
      };
    };
}
