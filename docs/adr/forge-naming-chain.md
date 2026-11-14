# The naming chain of the forge

Record 2 of the register. The index of the register sits in docs/decisions.md.

2. The naming chain of the forge. Made: 2026-11-06, issue 166, transport record second revision. Decision: the repository owns no address for the forge name. The router DNS override resolves the name on the LAN, and the tailnet delegates local.jracon.xyz to the router through split DNS, so the name resolves wherever Tailscale runs. This record supersedes the stage 0 verdicts on the ssh route over MagicDNS and on the /etc/hosts pin (issue 166, stage 0 record, 2026-11-05), which kept a committed pin and a tailnet-primary transport. Alternatives that lost: the committed hosts pins on every host, because they added no reachability in any state; the hand-written pin on m2pro-mbp, for the same reason. Reopens: a state in which the router cannot hold the override, or the split DNS delegation stops.
