{
  pkgs,
  ...
}:

{
  programs.tmux = {
    enable = true;

    baseIndex = 1;
    clock24 = true;
    disableConfirmationPrompt = true;
    escapeTime = 200;
    keyMode = "vi";
    mouse = true;
    newSession = true;

    plugins = with pkgs.tmuxPlugins; [
      better-mouse-mode
      yank
    ];
  };
}
