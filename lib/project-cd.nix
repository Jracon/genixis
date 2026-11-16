# The fish cd stub of the project CLI: a child process cannot change the
# directory of the shell that started it, so the binary writes the target to
# PROJECT_CD_FILE and the stub reads it after the binary ends. The argument
# is the command line that runs the binary.
command: ''
  set -l cdfile (mktemp)
  set -lx PROJECT_CD_FILE $cdfile
  ${command} $argv
  set -l st $status
  if test -s $cdfile
      cd (cat $cdfile)
  end
  command rm -f $cdfile
  return $st
''
