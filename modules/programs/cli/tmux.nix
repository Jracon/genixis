{
  local,
  ...
}:

{
  programs.tmux = {
    enable = true;

    baseIndex = 1;
    disableConfirmationPrompt = true;
    escapeTime = 200;
    keyMode = "vi";
    mouse = true; # TODO based on local.gui or isDarwin?
    newSession = true;
  };
}
