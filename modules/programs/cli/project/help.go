package main

import (
	"fmt"
	"io"
	"strings"
)

// This file is the help system. One table, commandDocs, holds every command:
// its summary line for the overview, its usage, its prose, its options, and
// its examples. `project --help`, `project help [<command>]`, and `project
// <command> --help` print from it, and the argument-error paths point at
// `project help <command>` instead of repeating a usage line. One place
// describes one command, so the screens cannot drift apart.

// optionDoc is one option of a command screen: the flag with its value
// placeholder, and what it does.
type optionDoc struct {
	flag string
	text string
}

// exampleDoc is one example line: the command line, and the comment that
// says what it does.
type exampleDoc struct {
	line    string
	comment string
}

// commandDoc is one command of the overview and of its own screen. group ""
// keeps a command out of the overview but reachable through help: the ide
// verbs that only tmux hooks and yazi call.
type commandDoc struct {
	name     string
	group    string
	summary  string
	usage    []string
	prose    string
	options  []optionDoc
	examples []exampleDoc
}

const (
	groupWorktrees = "Worktrees and sessions"
	groupAsk       = "Ask and tell"
	groupWindows   = "Ide windows"
)

// overviewWidth and optionTextBase bound the printed lines: the screens stay
// readable in an 80-column terminal.
const (
	overviewWidth = 78
	hangingFlagAt = 26 // a flag column wider than this pushes the text below
)

var commandDocs = []commandDoc{
	{
		name:    "open",
		group:   groupWorktrees,
		summary: "open a checkout in an ide window; make its worktree when needed",
		usage: []string{
			"project open [user@host:]<dir> [<branch>] [--from <base>] [--as <name>]",
			"            [--plan <name>|none] [--identity <name>]",
		},
		prose: "Opens main/ of the project, or the worktree of <branch> beside it, in an ide window: nvim over a shell in one column, with the file tree in a left split of nvim, and claude in the other column. It makes the worktree when needed: an existing branch is checked out, a remote-only branch is tracked, a new branch starts from origin/<default>. With no <dir>, it opens the checkout that the current directory is in. A plain repo opens as it is. A missing <dir> asks before it creates the project (a git URL clones it, y starts it empty).",
		options: []optionDoc{
			{flag: "--from <base>", text: "Start a new branch at <base> instead of the default branch. The command records <base> as branch.<branch>.projectBase, and close and clean count a merge into it as merged. A local <base> wins over origin/<base>."},
			{flag: "--as <name>", text: "Directory name of the new worktree, instead of the branch name with / as -. The name cannot contain /."},
			{flag: "--plan <name>", text: "Start the claude session under the plan <name> (~/.config/project/plans/<name>.json). none starts no plan."},
			{flag: "--identity <name>", text: "Git identity of the leg: agent (the default), owner, or a profile that main/.claude/settings.local.json lists. The worktree commits and pushes under it."},
		},
		examples: []exampleDoc{
			{line: "project open", comment: "inside a checkout: open it again"},
			{line: "project open genixis", comment: "main/ of ~/projects/genixis"},
			{line: "project open genixis feat/nav", comment: "the worktree of feat/nav; makes it"},
			{line: "project open dev@services:genixis", comment: "runs there over ssh; a tab attaches"},
		},
	},
	{
		name:    "add",
		group:   groupWorktrees,
		summary: "make the worktree of a branch; print one JSON envelope",
		usage: []string{
			"project add <dir> <branch> [--from <base>] [--as <name>] [--identity <name>]",
		},
		prose: "Makes the worktree of <branch> the way open does, but opens no window and pulls nothing. It prints one JSON envelope on stdout whose data holds the branch and the worktree path. A repeated add for the same branch reports the same worktree: the claim is idempotent. Scripts and agents use it.",
		options: []optionDoc{
			{flag: "--from <base>", text: "Start a new branch at <base> instead of the default branch. The command records <base> as branch.<branch>.projectBase, and close and clean count a merge into it as merged."},
			{flag: "--as <name>", text: "Directory name of the new worktree, instead of the branch name with / as -."},
			{flag: "--identity <name>", text: "Git identity of the leg: agent (the default), owner, or a profile that main/.claude/settings.local.json lists."},
		},
		examples: []exampleDoc{
			{line: "project add . feat/nav", comment: "in the project or a checkout of it"},
			{line: "project add . ui/nav --from ui/trunk --as ui-nav", comment: "stacked branch"},
		},
	},
	{
		name:    "spawn",
		group:   groupWorktrees,
		summary: "make the worktree and start a Claude session on it",
		usage: []string{
			"project spawn [user@host:]<dir> <branch> [--from <base>] [--as <name>]",
			"             [--plan <name>|none] [--identity <name>] [--permission-mode <mode>]",
			"             [--headless] <prompt...>",
		},
		prose: "Makes the worktree like add, then starts a Claude Code session in it. The words after <branch> are the prompt. Without --headless, the window opens in the tmux session of the project, where you watch the agent and answer its permission prompts. With --headless, the session runs in the background, the command prints one JSON envelope with the session name, the session id that claude --bg printed, and the worktree path, and a view window named after the branch opens in the tmux session of the project and attaches by the session id; a background session cannot ask for permission, so it waits at every other prompt. A user@host:<dir> prefix runs the spawn on that host over ssh. When the fetch of a new branch fails, spawn fails with exit code 12 and starts no session: the base of a leg must be current.",
		options: []optionDoc{
			{flag: "--from <base>", text: "Start a new branch at <base> instead of the default branch. The command records <base> as branch.<branch>.projectBase, and close and clean count a merge into it as merged."},
			{flag: "--as <name>", text: "Directory name of the new worktree, instead of the branch name with / as -."},
			{flag: "--plan <name>", text: "Start the session under the plan <name>. none starts no plan. Without the flag, the session inherits the plan of the session that runs the spawn."},
			{flag: "--identity <name>", text: "Git identity of the leg: agent (the default), owner, or a profile that main/.claude/settings.local.json lists."},
			{flag: "--permission-mode <mode>", text: "Permission mode of the session, for example acceptEdits or bypassPermissions. A headless session waits at every prompt without one."},
			{flag: "--headless", text: "Start the session in the background and print one JSON envelope. The envelope carries the session id that claude --bg printed; the claude output goes to stderr; manage the session with claude agents, claude attach, claude logs, and claude stop."},
			{flag: "--print-settings", text: "Print the --settings JSON of the session and start nothing. Internal."},
		},
		examples: []exampleDoc{
			{line: `project spawn . ai/121 "Implement #121. Stop after you push."`, comment: ""},
			{line: "project spawn . review/167 --permission-mode acceptEdits \"Review PR 167.\"", comment: ""},
			{line: "project spawn dev@services:genixis ai/130 --headless \"Fix #130.\"", comment: ""},
		},
	},
	{
		name:    "list",
		group:   groupWorktrees,
		summary: "print branches, worktrees, and merge state as one JSON envelope",
		usage: []string{
			"project list [<dir>]",
		},
		prose: "Prints the frontier of the project as one JSON envelope on stdout: the default branch, each branch with its worktree (its claim) and its merge state, and the dirty state of each worktree. An orchestrator reads it to see which work is in flight and which branches the merge slot accepts.",
		examples: []exampleDoc{
			{line: "project list", comment: "the project of the current directory"},
			{line: "project list genixis", comment: ""},
		},
	},
	{
		name:    "review",
		group:   groupWorktrees,
		summary: "open the head of a pull request as the worktree review/pr-<n>",
		usage: []string{
			"project review [<dir>] <n>",
		},
		prose: "Fetches refs/pull/<n>/head from origin, makes the branch review/pr-<n> at that head, makes or reuses its worktree, and opens it in an ide window under the identity of the owner. Every run moves the branch to the current head of the pull request, so a review never reads a stale revision; a worktree with uncommitted work stays as it is, and the run says so. The command owns the review/pr-<n> namespace: close the worktree to end a review. It fails with exit code 12 when the fetch fails, because a review needs the current head.",
		examples: []exampleDoc{
			{line: "project review 173", comment: "the project of the current directory"},
			{line: "project review genixis 173", comment: "by project name"},
		},
	},
	{
		name:    "board",
		group:   groupWorktrees,
		summary: "show open issues, open pull requests, and the frontier as one board",
		usage: []string{
			"project board [<dir>]",
		},
		prose: "Prints one board that joins the frontier of the project with the open issues and the open pull requests of the forge, read through tea. The head branch of a pull request names the branch of a worktree, and the body of a pull request holds a closing keyword for each issue it solves: those two keys carry the join. A row names the pull request of an issue, the worktree of its head branch, and the review worktree of the pull request, when each exists. An open pull request that no open issue row carries gets its own row, and so does a frontier branch that no open pull request carries. Inside tmux the board opens in a popup that pages the text; outside tmux it prints to stdout. The board writes nothing to the forge.",
		examples: []exampleDoc{
			{line: "project board", comment: "the project of the current directory"},
			{line: "project board genixis", comment: "by project name"},
		},
	},
	{
		name:    "close",
		group:   groupWorktrees,
		summary: "remove a worktree that holds no uncommitted work",
		usage: []string{
			"project close [<worktree>]",
		},
		prose: "Removes one worktree. With no argument, it removes the worktree of the current directory; a bare name is a worktree of the project of the current directory. It refuses while the worktree holds uncommitted work, or while an included file differs from main/. It stops the background sessions of the worktree and closes its windows. It deletes the branch only when it is merged into the default branch or its projectBase; an unmerged branch stays, with a message, and the exit code is 0.",
		examples: []exampleDoc{
			{line: "project close", comment: "the worktree of the current directory"},
			{line: "project close feat-nav", comment: "by directory name"},
			{line: "project close ~/projects/genixis/feat-nav", comment: "by path"},
		},
	},
	{
		name:    "discard",
		group:   groupWorktrees,
		summary: "remove a worktree and its uncommitted work (person at a terminal)",
		usage: []string{
			"project discard [<worktree>]",
		},
		prose: "Close that also removes uncommitted work and the files that project.closeCheck protects. Only a person at a terminal can run it: it refuses inside an agent session and without a terminal, it lists the work it will remove, and it asks for a random six-digit code. It keeps an unmerged branch, as close does.",
		examples: []exampleDoc{
			{line: "project discard feat-nav", comment: ""},
		},
	},
	{
		name:    "clean",
		group:   groupWorktrees,
		summary: "close merged worktrees and delete merged branches",
		usage: []string{
			"project clean [<dir>] [--dry-run] [--gone]",
		},
		prose: "Fetches origin, fast-forwards main/, closes every worktree whose branch is merged, and deletes merged branches that have no worktree. A finished review leg goes too: merged, only its creation in the reflog, and its upstream gone. Work that the forge shows closed goes as well: the head branch and the review branch of a pull request that closed without a merge, and the branch of an issue that closed, each only when no unpushed work exists. A worktree with uncommitted work stays open and is reported. Run it after pull requests merge or close.",
		options: []optionDoc{
			{flag: "-n, --dry-run", text: "Print the steps and change nothing, except the fetch."},
			{flag: "--gone", text: "Also clean branches whose remote branch was deleted, which is how a squash merge shows. A branch goes only when its tip equals its saved upstream tip, so no unpushed work is lost."},
		},
		examples: []exampleDoc{
			{line: "project clean --dry-run", comment: "see the steps first"},
			{line: "project clean --gone", comment: "after squash merges"},
		},
	},
	{
		name:    "lmk",
		group:   groupAsk,
		summary: "answer one quick documentation question with a standalone claude call",
		usage: []string{
			"project lmk [--context <file>] <question...>",
		},
		prose: "Answers one quick documentation question with one standalone claude call that runs in the current checkout, reads the repository with its own tools, prints its answer on this terminal, and ends. No pane is searched and no live session is involved, so the question needs no ide window. Text on piped stdin lands in .scratch/ and the prompt names the file, and --context <file> names a bundle that the caller wrote.",
		options: []optionDoc{
			{flag: "--context <file>", text: "Name a file, typically a bundle under .scratch/, that holds the context of the question. The prompt tells the call to read it."},
		},
		examples: []exampleDoc{
			{line: "lmk why does the dispatcher skip closed issues", comment: "the fish plain-word form"},
			{line: "git log --oneline -5 | project lmk what changed here", comment: "piped stdin is the context"},
		},
	},
	{
		name:    "ask",
		group:   groupAsk,
		summary: "send a question to the claude pane of this checkout",
		usage: []string{
			"project ask [--context <file>] <question...>",
		},
		prose: "Sends one question to the claude pane of the current checkout: the ide window whose @ide_dir is the working tree, and its @ide_agent pane. The text goes in through the tmux buffer as a bracketed paste, and an Enter submits it, so the live session keeps its conversation context and answers with its own tools. --context <file> names a bundle that the caller wrote, the one the ask mapping of the ide window builds (see docs/keymap.md). With no claude pane, the command starts claude in the current terminal with the prompt already entered.",
		options: []optionDoc{
			{flag: "--context <file>", text: "Name a file, typically a bundle under .scratch/, that holds the context of the question. The prompt tells the session to read it."},
		},
		examples: []exampleDoc{
			{line: "project ask --context .scratch/ask-1.md what does this selection do", comment: "the form the nvim mapping uses"},
		},
	},
	{
		name:    "btw",
		group:   groupAsk,
		summary: "send a fact to the claude pane, or into the shared memory of the project",
		usage: []string{
			"project btw [--context <file>] <fact...>",
		},
		prose: "The tell side of lmk: it sends one statement, not a question, to the claude pane the same way. The prompt tells the session to absorb the fact and to write it to the shared project memory when it must outlive the session. With no claude pane it starts no session, because a fact needs no conversation: it writes a dated note into the memory directory of the project and adds the pointer line to the index, and the next session reads the note and files it.",
		options: []optionDoc{
			{flag: "--context <file>", text: "Name a file that holds the context of the fact, the way lmk does."},
		},
		examples: []exampleDoc{
			{line: "btw the forge mirror lives at git+https://github.com/jracon/genixis", comment: ""},
		},
	},
	{
		name:    "convert",
		group:   groupWorktrees,
		summary: "move a plain repo into <repo>/main",
		usage: []string{
			"project convert <repo>",
		},
		prose: "Moves a plain repository into <repo>/main, repairs its linked worktrees, and moves the Claude memory and the transcripts of the old path. The project layout applies to the repo after that.",
		examples: []exampleDoc{
			{line: "project convert ~/src/myrepo", comment: ""},
		},
	},
	{
		name:    "ide",
		group:   groupWindows,
		summary: "build the ide window of a checkout (verbs: pop, close, reload)",
		usage: []string{
			"project ide [--detach <session> | --session <session>] [<dir>] [<title>]",
			"            [claude args...]",
			"project ide pop | close | reload",
		},
		prose: "Builds the ide window of a checkout: nvim over a shell in one column, with the file tree in a left split of nvim, and claude in the other column. Inside tmux, the window is a tab of the current session, built in place when the current window holds one lone pane. Outside tmux, the command attaches to the session named after the directory (or the title). The verbs manage the window: pop moves the current window into a WezTerm window of its own; close kills the ide window and refuses while nvim holds unsaved buffers; reload picks up a rebuild, so it re-sources the tmux config and restarts nvim, with its file tree, on its socket.",
		options: []optionDoc{
			{flag: "--detach <session>", text: "Put the window in the tmux session <session> without attaching and without switching the current window. One project gets one session; project itself uses this form."},
			{flag: "--session <session>", text: "Outside tmux, attach to the session <session> instead of the one named after the directory."},
		},
		examples: []exampleDoc{
			{line: "project ide .", comment: "the ide window of this directory"},
			{line: "project ide close", comment: "from any pane of the window"},
			{line: "project ide pop", comment: "the window into its own WezTerm window"},
		},
	},
	{
		name:    "ide-layout",
		group:   groupWindows,
		summary: "re-proportion the panes of an ide window (tmux hook)",
		usage: []string{
			"ide-layout <target>",
		},
		prose: "Re-proportions the panes of an ide window to its size: claude gets 30% of the width (at least 40 columns) and the shell 20% of the height (at least 6 rows); the editor pane above the shell takes the rest of the width, and the file tree takes its share of the editor. The tmux hooks client-attached and client-resized run it.",
	},
	{
		name:    "ide-open",
		group:   groupWindows,
		summary: "open files in the nvim pane of the ide window (yazi opener)",
		usage: []string{
			"ide-open <files...>",
		},
		prose: "The yazi edit opener. Inside an ide session, it opens each file in the nvim pane over its socket, one tab each, and focuses the pane. Inside tmux elsewhere, it opens the files in a new tmux window.",
	},
	{
		name:    "ide-edit",
		group:   groupWindows,
		summary: "blocking $EDITOR that opens files in the nvim pane",
		usage: []string{
			"ide-edit <files...>",
		},
		prose: "A blocking $EDITOR for tools such as agenix -e: it opens each file in the nvim pane of the ide window, one tab each, and waits until the buffer closes. Outside an ide window, it runs plain nvim in this terminal.",
	},
	{
		name:    "ide-tab",
		group:   groupWindows,
		summary: "select an nvim tab from any pane of the ide window",
		usage: []string{
			"ide-tab <window> <n|next|prev>",
		},
		prose: "Selects tab <n> of the nvim of the ide window <window> (0 is the tenth tab), or the next or previous tab, and focuses the editor pane from any pane. The tmux Ctrl+digit bindings run it.",
	},
	{
		name:    "ide-view",
		group:   groupWindows,
		summary: "show a file read-only in place of the editor pane",
		usage: []string{
			"ide-view <file>",
		},
		prose: "Shows one file read-only in the place of the editor pane: markdown through glow, other files through bat. The viewer is a real pane, so the Option+arrows still move, and q swaps nvim back. Outside an ide session, it opens a tmux popup. Shift+Enter on a file in yazi runs it.",
		options: []optionDoc{
			{flag: "--run <pane> <file>", text: "Internal: the command of the viewer pane."},
			{flag: "--popup <file>", text: "Internal: the command of the popup."},
		},
	},
	{
		name:    "wezterm-attach",
		group:   groupWindows,
		summary: "open one tmux session as a tab of the host window",
		usage: []string{
			"wezterm-attach <session>",
		},
		prose: "Opens one tmux session as a tab of the host window, the WezTerm window titled user@host, and makes the window when no window holds the title. The ide family and project call it; it is the one command that opens such a tab.",
	},
}

// helpFlag reports whether a command line asks for help: an exact --help
// token anywhere, or -h as the first token. -h stays first-only because
// some commands pass later words through (a spawn prompt can hold -h).
func helpFlag(argv []string) bool {
	if len(argv) > 0 && argv[0] == "-h" {
		return true
	}
	for _, arg := range argv {
		if arg == "--help" {
			return true
		}
	}
	return false
}

// findDoc returns the doc of one command, or nil. A name can hold a space.
func findDoc(name string) *commandDoc {
	for i := range commandDocs {
		if commandDocs[i].name == name {
			return &commandDocs[i]
		}
	}
	return nil
}

// printMainHelp writes the overview: what a project directory is, every
// command with one line, and where the detail lives.
func printMainHelp(w io.Writer) {
	fmt.Fprintln(w, "project — the worktrees of a project directory")
	fmt.Fprintln(w)
	fmt.Fprintln(w, "usage: project <command> [args...]")
	fmt.Fprintln(w)
	intro := "A project directory <dir> holds main/ (a clone of the default branch) and one git worktree per branch beside it, at <dir>/<branch>, with each / in the branch name as -. A <dir> that is a bare name means ~/projects/<name>; inside a checkout, the current project applies. project open and project spawn also accept user@host:<dir>, which runs on that host over ssh."
	for _, line := range wrap(intro, overviewWidth) {
		fmt.Fprintln(w, line)
	}
	fmt.Fprintln(w)
	width := 0
	for i := range commandDocs {
		doc := &commandDocs[i]
		if doc.group != "" && len(doc.name) > width {
			width = len(doc.name)
		}
	}
	for _, group := range []string{groupWorktrees, groupAsk, groupWindows} {
		fmt.Fprintln(w, group+":")
		for i := range commandDocs {
			doc := &commandDocs[i]
			if doc.group != group {
				continue
			}
			fmt.Fprintf(w, "  %-*s  %s\n", width, doc.name, doc.summary)
		}
		fmt.Fprintln(w)
	}
	fmt.Fprintln(w, "`project help <command>` prints the usage, options, and examples of one")
	fmt.Fprintln(w, "command. Exit codes: 0 success, 1 general error, 2 argument error,")
	fmt.Fprintln(w, "5 not found, 7 permission denied, 12 unavailable.")
}

// printCommandDoc writes one command screen: title, usage, prose, options,
// examples.
func printCommandDoc(w io.Writer, name string) {
	doc := findDoc(name)
	if doc == nil {
		return
	}
	fmt.Fprintf(w, "%s — %s\n", doc.name, doc.summary)
	fmt.Fprintln(w)
	for i, line := range doc.usage {
		if i == 0 {
			fmt.Fprintf(w, "usage: %s\n", line)
		} else {
			fmt.Fprintf(w, "       %s\n", line)
		}
	}
	if doc.prose != "" {
		fmt.Fprintln(w)
		for _, line := range wrap(doc.prose, overviewWidth) {
			fmt.Fprintln(w, line)
		}
	}
	if len(doc.options) > 0 {
		flagWidth := 0
		for _, opt := range doc.options {
			if len(opt.flag) > flagWidth {
				flagWidth = len(opt.flag)
			}
		}
		hanging := flagWidth > hangingFlagAt
		indent := strings.Repeat(" ", 2+flagWidth+2)
		textWidth := overviewWidth - 2 - flagWidth - 2
		fmt.Fprintln(w)
		fmt.Fprintln(w, "Options:")
		for _, opt := range doc.options {
			if hanging {
				fmt.Fprintf(w, "  %s\n", opt.flag)
				for _, line := range wrap(opt.text, overviewWidth-len(indent)) {
					fmt.Fprintln(w, indent+line)
				}
				continue
			}
			first := true
			for _, line := range wrap(opt.text, textWidth) {
				if first {
					fmt.Fprintf(w, "  %-*s  %s\n", flagWidth, opt.flag, line)
					first = false
				} else {
					fmt.Fprintln(w, indent+line)
				}
			}
		}
	}
	if len(doc.examples) > 0 {
		fmt.Fprintln(w)
		fmt.Fprintln(w, "Examples:")
		for _, ex := range doc.examples {
			if ex.comment == "" {
				fmt.Fprintf(w, "  %s\n", ex.line)
			} else {
				fmt.Fprintf(w, "  %s   # %s\n", ex.line, ex.comment)
			}
		}
	}
}

// wrap breaks text into lines of at most width columns on spaces. A word
// longer than the width stays whole.
func wrap(text string, width int) []string {
	var lines []string
	line := ""
	for _, word := range strings.Fields(text) {
		switch {
		case line == "":
			line = word
		case len(line)+1+len(word) <= width:
			line += " " + word
		default:
			lines = append(lines, line)
			line = word
		}
	}
	if line != "" {
		lines = append(lines, line)
	}
	return lines
}
