{
  lib,
  pkgs,
  ...
}:

let
  readJson = path: builtins.fromJSON (builtins.readFile path);

  # A Home Manager profile owns its settings.json and extensions.json
  # (mkVscodeModule.nix: profileDir, extensionJsonFile). A non-default profile
  # inherits nothing from default, so the shared parts are prepended below.
  shared = {
    extensions =
      (with pkgs.vscode-extensions; [
        anthropic.claude-code # Claude Code for VS Code
        editorconfig.editorconfig # EditorConfig
        mkhl.direnv # direnv
        vscode-icons-team.vscode-icons # vscode-icons
      ])
      ++ (with pkgs.open-vsx; [
        jeanp413.open-remote-ssh # Open Remote - SSH (VSCodium-compatible remote-ssh)
      ]);
    userSettings = readJson ./vscodium/settings.json;
  };

  languages = {
    nix = {
      extensions = with pkgs.vscode-extensions; [
        jnoortheen.nix-ide # Nix language support
      ];
      userSettings = {
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nixd";
      };
    };
    go = {
      extensions = with pkgs.vscode-extensions; [
        golang.go # Go
      ];
      userSettings = { };
    };
    python = {
      extensions = with pkgs.vscode-extensions; [
        detachhead.basedpyright # basedpyright language server
        charliermarsh.ruff # ruff linter and formatter
      ];
      userSettings = readJson ./vscodium/python.json;
    };
    lua = {
      extensions =
        (with pkgs.vscode-extensions; [
          sumneko.lua # Lua language server
        ])
        ++ (with pkgs.open-vsx; [
          johnnymorganz.stylua # StyLua formatter
        ]);
      userSettings = { };
    };
    shell = {
      extensions = with pkgs.vscode-extensions; [
        timonwong.shellcheck # ShellCheck
        mkhl.shfmt # shfmt
      ];
      userSettings = { };
    };
  };

  # The genixis profile: all five language profiles plus the repository extras.
  genixis = {
    extensions =
      lib.concatMap (l: l.extensions) (lib.attrValues languages)
      ++ (with pkgs.vscode-extensions; [
        esbenp.prettier-vscode # Prettier
        matthewpi.caddyfile-support # Caddyfile
      ]);
    userSettings = lib.foldl' lib.recursiveUpdate { } (
      map (l: l.userSettings) (lib.attrValues languages)
    );
  };

  withShared = profile: {
    extensions = shared.extensions ++ profile.extensions;
    userSettings = lib.recursiveUpdate shared.userSettings profile.userSettings;
  };
in
{
  programs.vscodium = {
    enable = true;

    profiles = lib.mapAttrs (_: withShared) (languages // { inherit genixis; }) // {
      # The update checks are settable on the default profile only, and they apply to all profiles.
      default =
        (withShared {
          extensions = [ ];
          userSettings = { };
        })
        // {
          enableExtensionUpdateCheck = true;
          enableUpdateCheck = true;
        };
    };
  };
}
