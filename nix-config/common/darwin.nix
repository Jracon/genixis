{ 
  self, 
  ... 
}:

{
  system = {
    stateVersion = 5; # used for backwards compatibility, please read the changelog before changing. (darwin-rebuild changelog)
    configurationRevision = self.rev or self.dirtyRev or null; # git commit hash for darwin-version.
  };
}
