{
  programs.tmux = {
    enable = true;

    baseIndex = 1;
    disableConfirmationPrompt = true;
    escapeTime = 200;
    keyMode = "vi";
    mouse = true;
    newSession = true;
  };
}
