# the vulture whitelist of the python harnesses: each entry names one
# reference that a static read cannot see, with its reason in one line
# (issue 434). The vulture check of lib/checks.nix reads this file beside
# the suites, so an entry here keeps its name alive for the pass.

# shlex reads whitespace_split and whitespace when the lexer pulls a token
lex.whitespace_split
lex.whitespace

# socketserver calls handle_error of the server when a handler thread raises
server.handle_error

# the http server reads server_version of the handler to build each response
Receiver.server_version

# the http server dispatches a request to do_GET or do_POST by its method
Receiver.do_GET
Receiver.do_POST

# the http server writes each access log line through log_message
Receiver.log_message
