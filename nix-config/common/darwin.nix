{
  self,
  ...
}:

{
  system = {
    # git commit hash for darwin-version.
    configurationRevision = self.rev or self.dirtyRev or null;

    # used for backwards compatibility, please read the changelog before changing. (darwin-rebuild changelog)
    stateVersion = 5;
  };
}
