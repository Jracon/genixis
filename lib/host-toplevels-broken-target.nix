# The broken target of the teeth fixture of the host-toplevels check
# (lib/checks.nix). The fixture module imports this file behind a timer
# value, and the throw stands for the error that an import of a missing
# file raises when a rebuild forces the timer. A path that points at no
# file itself raises an error that restricted eval lets no check catch,
# so a real broken import of a host kills the check evaluation itself,
# and the gate reddens; the fixture throws instead.
throw "host-toplevels: the broken import target of the teeth fixture"
