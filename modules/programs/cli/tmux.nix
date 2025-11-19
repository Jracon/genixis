{
  pkgs,
  ...
}:

{
  programs.tmux = {
    enable = true;

    baseIndex = 1;
    disableConfirmationPrompt = true;
    escapeTime = 200;
    keyMode = "vi";
    mouse = if pkgs.stdenv.isDarwin then true else false;
    newSession = true;
  };
}
