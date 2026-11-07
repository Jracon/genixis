package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"genixis/project/internal/spec"
)

// This file is the board of the reviewer rig (issue #102, built by issue
// #181): one read that joins the frontier of the project with the open
// issues and the open pull requests of the forge, plus the per-area planned
// and done counts of docs/progress.md. The board is read-only: the forge
// answers through tea list calls, which write nothing, and the token stays
// with tea.

// boardIssue is one open issue of the tea list.
type boardIssue struct {
	Number string `json:"index"`
	Title  string `json:"title"`
}

// boardPull is one open pull request of the tea list. Head is the branch
// the pull request carries, and Body holds the closing keywords that link
// it to its issues.
type boardPull struct {
	Number string `json:"index"`
	Title  string `json:"title"`
	Body   string `json:"body"`
	Head   string `json:"head"`
}

// boardRow is one row of the board: an open issue with its pull request,
// its worktree, and its review worktree, or an open pull request that no
// open issue carries, or a frontier branch that no open pull request
// carries.
type boardRow struct {
	issue       int
	pull        int
	title       string
	branch      string
	worktree    string
	dirty       bool
	review      string
	reviewDirty bool
}

// areaCount is the planned and the done count of one area of
// docs/progress.md.
type areaCount struct {
	area    string
	planned int
	done    int
}

// boardStats are the headline counts of the board.
type boardStats struct {
	issues   int
	pulls    int
	branches int
}

// cmdBoard is `project board [<dir>]`: print the board. Inside tmux the
// board opens in a popup that pages the text; outside tmux it prints to
// stdout.
func cmdBoard(argv []string, stdout, stderr io.Writer) spec.ExitCode {
	if helpFlag(argv) {
		printCommandDoc(stdout, "board")
		return spec.Success
	}
	if len(argv) > 1 {
		return fail(stderr, spec.ArgError, "usage: project board [<dir>]")
	}
	target := ""
	if len(argv) == 1 {
		target = argv[0]
	}
	dir, err := dirArg(target)
	if err != nil {
		return fail(stderr, spec.GeneralError, "%v", err)
	}
	if project, ok := insideProject(dir); ok {
		dir = project
	}
	if !isProjectDir(dir) {
		return fail(stderr, spec.NotFound, "%s is not a project (no main/ checkout)", dir)
	}
	rows, areas, stats, warnings := readBoard(dir)
	for _, warning := range warnings {
		printfDiag(stderr, "%s", warning)
	}
	text := renderBoard(dir, rows, areas, stats)
	if os.Getenv("TMUX") != "" {
		return boardPopup(text, stdout)
	}
	fmt.Fprint(stdout, text)
	return spec.Success
}

// readBoard gathers the board of the project at dir: the frontier read, the
// open issues and pull requests through tea, and the progress counts of the
// main checkout. Every failure becomes a warning, so the board always
// shows what it could read.
func readBoard(dir string) ([]boardRow, []areaCount, boardStats, []string) {
	var warnings []string
	f, err := frontierOf(dir)
	if err != nil {
		f = &frontier{}
		warnings = append(warnings, fmt.Sprintf("the frontier read failed: %s", err.Error()))
	}
	var issues []boardIssue
	var pulls []boardPull
	if !commandExists("tea") {
		warnings = append(warnings, "tea is not on PATH, so the board shows no issues and no pull requests")
	} else {
		mainDir := filepath.Join(dir, "main")
		if raw, teaErr := runCmd(mainDir, nil, "tea", "issues", "list", "--state", "open", "--output", "json"); teaErr != nil {
			warnings = append(warnings, fmt.Sprintf("tea listed no issues: %s", teaErr.Error()))
		} else if err := jsonUnmarshal([]byte(raw), &issues); err != nil {
			warnings = append(warnings, fmt.Sprintf("the issue list of tea did not parse: %s", err.Error()))
		}
		if raw, teaErr := runCmd(mainDir, nil, "tea", "pulls", "list", "--state", "open", "--fields", "index,title,body,head", "--output", "json"); teaErr != nil {
			warnings = append(warnings, fmt.Sprintf("tea listed no pull requests: %s", teaErr.Error()))
		} else if err := jsonUnmarshal([]byte(raw), &pulls); err != nil {
			warnings = append(warnings, fmt.Sprintf("the pull request list of tea did not parse: %s", err.Error()))
		}
	}
	rows := boardJoin(issues, pulls, f)
	var areas []areaCount
	if raw, readErr := os.ReadFile(filepath.Join(dir, "main", "docs", "progress.md")); readErr == nil {
		areas = progressCounts(string(raw))
	}
	return rows, areas, boardStats{issues: len(issues), pulls: len(pulls), branches: len(f.entries)}, warnings
}

// closingKeyword names the words that link a pull request to the issue it
// solves, whatever their case. The dispatcher reads the same words when it
// links entities.
var closingKeyword = regexp.MustCompile(`(?i)\b(?:close[sd]?|fix(?:e[sd]?)?|resolve[sd]?)\s+#(\d+)`)

// closingNumbers returns every issue number that a closing keyword of the
// body names, in order of appearance.
func closingNumbers(body string) []int {
	var numbers []int
	for _, match := range closingKeyword.FindAllStringSubmatch(body, -1) {
		if n, err := strconv.Atoi(match[1]); err == nil {
			numbers = append(numbers, n)
		}
	}
	return numbers
}

// reviewBranch matches the branch of the worktree that `project review`
// makes, and names the pull request it reads.
var reviewBranch = regexp.MustCompile(`^review/pr-(\d+)$`)

// reviewPullNumber is the pull request that a review branch reads, or 0
// for every other branch.
func reviewPullNumber(branch string) int {
	match := reviewBranch.FindStringSubmatch(branch)
	if match == nil {
		return 0
	}
	n, err := strconv.Atoi(match[1])
	if err != nil {
		return 0
	}
	return n
}

// boardJoin joins the three reads of the board. The head branch of a pull
// request names the branch of a worktree, and the body of a pull request
// holds a closing keyword for each issue it solves: those two keys carry
// the join. Every open issue gets a row that names its pull request, its
// worktree, and the review worktree of the pull request, when each exists.
// An open pull request that no open issue row carries gets its own row,
// and so does every frontier branch that no open pull request carries,
// except the review branch of an open pull request, which rides on the row
// of that pull request.
func boardJoin(issues []boardIssue, pulls []boardPull, f *frontier) []boardRow {
	// deterministic order: the lowest pull request wins an issue that
	// several claim
	sorted := append([]boardPull(nil), pulls...)
	sort.Slice(sorted, func(i, j int) bool {
		a, _ := strconv.Atoi(sorted[i].Number)
		b, _ := strconv.Atoi(sorted[j].Number)
		return a < b
	})
	headOf := map[int]string{}
	closesOf := map[int][]int{}
	openPull := map[int]bool{}
	for _, pull := range sorted {
		n, err := strconv.Atoi(pull.Number)
		if err != nil {
			continue
		}
		headOf[n] = pull.Head
		closesOf[n] = closingNumbers(pull.Body)
		openPull[n] = true
	}
	pullOf := map[int]int{} // issue number -> the pull request that closes it
	for _, pull := range sorted {
		n, _ := strconv.Atoi(pull.Number)
		for _, issue := range closesOf[n] {
			if _, taken := pullOf[issue]; !taken {
				pullOf[issue] = n
			}
		}
	}
	worktreeOf := map[string]string{}
	dirtyOf := map[string]bool{}
	for _, report := range f.worktrees {
		if report.main || report.branch == "" {
			continue
		}
		worktreeOf[report.branch] = filepath.Base(report.path)
		dirtyOf[report.branch] = report.dirty
	}
	reviewOf := func(pull int) (string, bool) {
		branch := fmt.Sprintf("review/pr-%d", pull)
		return worktreeOf[branch], dirtyOf[branch]
	}

	var rows []boardRow
	shown := map[int]bool{} // pull requests that a row carries already
	for _, issue := range issues {
		n, err := strconv.Atoi(issue.Number)
		if err != nil {
			continue
		}
		row := boardRow{issue: n, title: issue.Title}
		if pull, ok := pullOf[n]; ok {
			row.pull = pull
			shown[pull] = true
			row.branch = headOf[pull]
			row.worktree = worktreeOf[row.branch]
			row.dirty = dirtyOf[row.branch]
			row.review, row.reviewDirty = reviewOf(pull)
		}
		rows = append(rows, row)
	}
	for _, pull := range sorted {
		n, _ := strconv.Atoi(pull.Number)
		if shown[n] {
			continue
		}
		row := boardRow{
			pull:     n,
			title:    pull.Title,
			branch:   headOf[n],
			worktree: worktreeOf[headOf[n]],
			dirty:    dirtyOf[headOf[n]],
		}
		row.review, row.reviewDirty = reviewOf(n)
		rows = append(rows, row)
	}
	for _, entry := range f.entries {
		if headCarried(entry.Branch, headOf) {
			continue
		}
		if reviewPullNumber(entry.Branch) != 0 && openPull[reviewPullNumber(entry.Branch)] {
			continue
		}
		rows = append(rows, boardRow{
			branch:   entry.Branch,
			worktree: worktreeOf[entry.Branch],
			dirty:    dirtyOf[entry.Branch],
		})
	}
	return rows
}

// headCarried reports whether a frontier branch is the head of an open pull
// request.
func headCarried(branch string, headOf map[int]string) bool {
	for _, head := range headOf {
		if head == branch {
			return true
		}
	}
	return false
}

// progressCounts reads docs/progress.md: one `## ` heading starts an area,
// and each `- [x]` line is done work and each `- [ ]` line is planned work.
// The file itself owns the full record; the board counts only.
func progressCounts(markdown string) []areaCount {
	var areas []areaCount
	for _, line := range strings.Split(markdown, "\n") {
		switch {
		case strings.HasPrefix(line, "## "):
			areas = append(areas, areaCount{area: strings.TrimSpace(strings.TrimPrefix(line, "## "))})
		case strings.HasPrefix(line, "- [x]"):
			if len(areas) > 0 {
				areas[len(areas)-1].done++
			}
		case strings.HasPrefix(line, "- [ ]"):
			if len(areas) > 0 {
				areas[len(areas)-1].planned++
			}
		}
	}
	return areas
}

// renderBoard writes the board as plain text: the headline counts, one row
// on two lines, and the progress counts by area.
func renderBoard(dir string, rows []boardRow, areas []areaCount, stats boardStats) string {
	var b strings.Builder
	fmt.Fprintf(&b, "%s — the board: %d open issues, %d open pull requests, %d branches in flight\n\n", filepath.Base(dir), stats.issues, stats.pulls, stats.branches)
	for _, row := range rows {
		switch {
		case row.issue != 0:
			fmt.Fprintf(&b, "#%-4d %s\n", row.issue, row.title)
		case row.pull != 0:
			fmt.Fprintf(&b, "pull #%-4d %s\n", row.pull, row.title)
		default:
			fmt.Fprintf(&b, "branch %s\n", row.branch)
		}
		fmt.Fprintf(&b, "      %s\n", row.stateLine())
	}
	if len(areas) > 0 {
		fmt.Fprintf(&b, "\nprogress by area, done/planned:\n")
		parts := make([]string, 0, len(areas))
		for _, area := range areas {
			parts = append(parts, fmt.Sprintf("%s %d/%d", area.area, area.done, area.planned))
		}
		fmt.Fprintf(&b, "  %s\n", strings.Join(parts, ", "))
	}
	return b.String()
}

// stateLine is the second line of a row: what carries the work and where it
// lives.
func (r boardRow) stateLine() string {
	var parts []string
	switch {
	case r.pull != 0:
		parts = append(parts, fmt.Sprintf("pull #%d head %s", r.pull, r.branch))
	case r.branch != "":
		parts = append(parts, fmt.Sprintf("branch %s", r.branch))
	}
	if r.worktree != "" {
		parts = append(parts, fmt.Sprintf("worktree %s%s", r.worktree, dirtyMark(r.dirty)))
	}
	if r.review != "" {
		parts = append(parts, fmt.Sprintf("review %s%s", r.review, dirtyMark(r.reviewDirty)))
	}
	if len(parts) == 0 {
		return "no pull request"
	}
	return strings.Join(parts, ", ")
}

func dirtyMark(dirty bool) string {
	if dirty {
		return " (dirty)"
	}
	return ""
}

// boardPopup pages the board text in a tmux popup, the picked surface of
// issue #102: less scrolls and searches, q closes, and the Go module stays
// free of a TUI dependency. The call returns when the popup closes.
func boardPopup(text string, stdout io.Writer) spec.ExitCode {
	file, err := os.CreateTemp("", "project-board-*.txt")
	if err != nil {
		fmt.Fprint(stdout, text)
		return spec.Success
	}
	name := file.Name()
	if _, writeErr := file.WriteString(text); writeErr != nil {
		os.Remove(name)
		fmt.Fprint(stdout, text)
		return spec.Success
	}
	file.Close()
	defer os.Remove(name)
	if _, err := tmux("display-popup", "-E", "-h", "90%", "-w", "90%", "less "+name); err != nil {
		fmt.Fprint(stdout, text)
	}
	return spec.Success
}
