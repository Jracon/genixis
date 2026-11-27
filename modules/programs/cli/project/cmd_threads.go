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
	"time"

	"genixis/project/internal/spec"
)

// This file is the thread store of the repository (docs/threads.md): the
// coordination records of the loop as plain markdown, one directory per
// thread. The read verbs print a thread in the order that an editor reads
// it, and the write verbs write files only: the caller commits the write as
// a normal git commit, so a write lands through a pull request and the store
// runs no step of the loop by itself.

// threadSlug matches the directory name of a thread: lowercase letters,
// digits, and hyphens, with no hyphen at an end (docs/threads.md).
var threadSlug = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)

// threadLogin matches the author field of a file of the store: the login of
// the writer. The same shape serves the event file names, so a name never
// breaks the file name grammar.
var threadLogin = regexp.MustCompile(`^[a-z0-9][a-z0-9-]*$`)

// threadEventName matches one event file: the four-digit sequence, the type,
// and the author, in the order the reading order sorts on.
var threadEventName = regexp.MustCompile(`^([0-9]{4})-([a-z]+)-([a-z0-9-]+)\.md$`)

// threadDate is the UTC timestamp shape of the date keys.
const threadDate = "2006-01-02T15:04:05Z"

// cmdThreads implements `project threads`: list, show, new, and add on the
// thread store of the repository of the current directory.
func cmdThreads(argv []string, stdin io.Reader, stdout, stderr io.Writer) spec.ExitCode {
	if helpFlag(argv) {
		printCommandDoc(stdout, "threads")
		return spec.Success
	}
	if len(argv) == 0 {
		return fail(stderr, spec.ArgError, "threads needs a verb (see project help threads)")
	}
	switch argv[0] {
	case "list":
		return threadsList(argv[1:], stdout, stderr)
	case "show":
		return threadsShow(argv[1:], stdout, stderr)
	case "new":
		return threadsNew(argv[1:], stdin, stderr)
	case "add":
		return threadsAdd(argv[1:], stdin, stderr)
	default:
		return fail(stderr, spec.ArgError, "unknown threads verb %s (see project help threads)", argv[0])
	}
}

// threadStore answers the store directory of the repository that the current
// directory is in, and the repository root for messages. The store may not
// exist yet: `new` makes it.
func threadStore() (root, store string, err error) {
	root = gitTopLevel(cwd())
	if root == "" {
		return "", "", fmt.Errorf("no repository at %s", cwd())
	}
	return root, filepath.Join(root, "threads"), nil
}

// threadMeta is the frontmatter of one file of the store. A key that the
// file omits reads as the empty string.
type threadMeta struct {
	title  string
	author string
	date   string
	status string
	origin string
	typ    string
}

// threadFile is one parsed file of a thread directory.
type threadFile struct {
	name string // the base name, thread.md for the body
	meta threadMeta
	body string
}

// parseThreadFile reads one markdown file of the store: the keys between the
// two --- lines, then the body after them. A file without a frontmatter
// block answers its whole text as the body, so a hand-made file stays
// readable and the show verb degrades to plain printing.
func parseThreadFile(path string) (threadFile, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return threadFile{}, err
	}
	text := string(raw)
	file := threadFile{name: filepath.Base(path)}
	rest, ok := strings.CutPrefix(text, "---\n")
	if !ok {
		file.body = strings.Trim(text, "\n")
		return file, nil
	}
	block, body, ok := strings.Cut(rest, "\n---\n")
	if !ok {
		file.body = strings.Trim(text, "\n")
		return file, nil
	}
	for _, line := range strings.Split(block, "\n") {
		key, value, ok := strings.Cut(line, ": ")
		if !ok {
			continue
		}
		switch key {
		case "title":
			file.meta.title = value
		case "author":
			file.meta.author = value
		case "date":
			file.meta.date = value
		case "status":
			file.meta.status = value
		case "origin":
			file.meta.origin = value
		case "type":
			file.meta.typ = value
		}
	}
	// the writer puts one blank line between the block and the body, so the
	// parse takes the body after that line and trims the ends
	file.body = strings.Trim(body, "\n")
	return file, nil
}

// writeThreadFile writes one file of the store: the frontmatter keys in a
// fixed order, each only when it holds a value, then the body.
func writeThreadFile(path string, meta threadMeta, body string) error {
	var b strings.Builder
	b.WriteString("---\n")
	for _, key := range []struct{ name, value string }{
		{"title", meta.title},
		{"type", meta.typ},
		{"author", meta.author},
		{"date", meta.date},
		{"status", meta.status},
		{"origin", meta.origin},
	} {
		if key.value == "" {
			continue
		}
		fmt.Fprintf(&b, "%s: %s\n", key.name, key.value)
	}
	b.WriteString("---\n\n")
	b.WriteString(strings.TrimRight(body, "\n"))
	b.WriteString("\n")
	return os.WriteFile(path, []byte(b.String()), 0o644)
}

// threadEvents lists the event files of one thread directory in name order.
func threadEvents(dir string) ([]threadFile, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var events []threadFile
	for _, entry := range entries {
		if entry.IsDir() || !threadEventName.MatchString(entry.Name()) {
			continue
		}
		file, err := parseThreadFile(filepath.Join(dir, entry.Name()))
		if err != nil {
			return nil, err
		}
		events = append(events, file)
	}
	sort.Slice(events, func(i, j int) bool { return events[i].name < events[j].name })
	return events, nil
}

// threadsList implements `project threads list`.
func threadsList(argv []string, stdout, stderr io.Writer) spec.ExitCode {
	if len(argv) != 0 {
		return fail(stderr, spec.ArgError, "usage: project threads list (see project help threads)")
	}
	_, store, err := threadStore()
	if err != nil {
		return fail(stderr, spec.NotFound, "%v", err)
	}
	entries, err := os.ReadDir(store)
	if err != nil {
		if os.IsNotExist(err) {
			return spec.Success
		}
		return fail(stderr, spec.GeneralError, "threads: %v", err)
	}
	var slugs []string
	for _, entry := range entries {
		if entry.IsDir() {
			slugs = append(slugs, entry.Name())
		}
	}
	sort.Strings(slugs)
	for _, slug := range slugs {
		file, err := parseThreadFile(filepath.Join(store, slug, "thread.md"))
		if err != nil {
			fmt.Fprintf(stdout, "%s  -  no thread.md\n", slug)
			continue
		}
		events, err := threadEvents(filepath.Join(store, slug))
		if err != nil {
			events = nil
		}
		fmt.Fprintf(stdout, "%s  %s  %d events  %s\n", slug, statusOf(file.meta), len(events), file.meta.title)
	}
	return spec.Success
}

// statusOf answers the status of a thread for the list line, with a dash for
// a body that states none.
func statusOf(meta threadMeta) string {
	if meta.status == "" {
		return "-"
	}
	return meta.status
}

// threadsShow implements `project threads show <slug>`.
func threadsShow(argv []string, stdout, stderr io.Writer) spec.ExitCode {
	if len(argv) != 1 || strings.HasPrefix(argv[0], "-") {
		return fail(stderr, spec.ArgError, "usage: project threads show <slug> (see project help threads)")
	}
	slug := argv[0]
	_, store, err := threadStore()
	if err != nil {
		return fail(stderr, spec.NotFound, "%v", err)
	}
	dir := filepath.Join(store, slug)
	file, err := parseThreadFile(filepath.Join(dir, "thread.md"))
	if err != nil {
		if os.IsNotExist(err) {
			return fail(stderr, spec.NotFound, "no thread %s", slug)
		}
		return fail(stderr, spec.GeneralError, "threads: %v", err)
	}
	printThreadHead(stdout, slug, file)
	fmt.Fprintln(stdout)
	fmt.Fprintln(stdout, file.body)
	events, err := threadEvents(dir)
	if err != nil {
		return fail(stderr, spec.GeneralError, "threads: %v", err)
	}
	for _, event := range events {
		fmt.Fprintf(stdout, "\n--- event %s %s, author %s, date %s ---\n\n",
			seqOf(event.name), event.meta.typ, event.meta.author, event.meta.date)
		fmt.Fprintln(stdout, event.body)
	}
	return spec.Success
}

// printThreadHead writes the header lines of a thread that the show verb and
// the failure paths share.
func printThreadHead(w io.Writer, slug string, file threadFile) {
	fmt.Fprintf(w, "%s — %s\n", slug, file.meta.title)
	line := fmt.Sprintf("author %s, date %s, status %s", file.meta.author, file.meta.date, statusOf(file.meta))
	if file.meta.origin != "" {
		line += ", origin " + file.meta.origin
	}
	fmt.Fprintln(w, line)
}

// seqOf answers the sequence part of an event file name.
func seqOf(name string) string {
	match := threadEventName.FindStringSubmatch(name)
	if match == nil {
		return ""
	}
	return match[1]
}

// threadsFlags holds the parsed arguments of the write verbs.
type threadsFlags struct {
	slug     string
	title    string
	typ      string
	author   string
	origin   string
	status   string
	bodyFile string
}

// parseThreadsFlags reads the shared argument form of the write verbs:
// positional words first (the slug, and the title for new), then the flags.
// A bare -- ends the options. kind names the verb in the error lines.
func parseThreadsFlags(kind string, argv []string, stderr io.Writer) (threadsFlags, bool) {
	var flags threadsFlags
	var words []string
	endOfOptions := false
	for i := 0; i < len(argv); i++ {
		arg := argv[i]
		if endOfOptions || !strings.HasPrefix(arg, "-") || arg == "-" {
			words = append(words, arg)
			continue
		}
		switch arg {
		case "--":
			endOfOptions = true
		case "--title", "--type", "--author", "--origin", "--status", "--body-file":
			if i+1 >= len(argv) {
				fail(stderr, spec.ArgError, "%s needs a value after %s (see project help threads)", arg, kind)
				return flags, false
			}
			i++
			value := argv[i]
			switch arg {
			case "--title":
				flags.title = value
			case "--type":
				flags.typ = value
			case "--author":
				flags.author = value
			case "--origin":
				flags.origin = value
			case "--status":
				flags.status = value
			case "--body-file":
				flags.bodyFile = value
			}
		default:
			fail(stderr, spec.ArgError, "unknown option %s (see project help threads)", arg)
			return flags, false
		}
	}
	if len(words) < 1 {
		fail(stderr, spec.ArgError, "threads %s needs a slug (see project help threads)", kind)
		return flags, false
	}
	if len(words) > 1 {
		fail(stderr, spec.ArgError, "threads %s takes one slug, not %d words (see project help threads)", kind, len(words))
		return flags, false
	}
	flags.slug = words[0]
	return flags, true
}

// threadsBody reads the text of a write: the file that --body-file names, or
// piped stdin. A terminal answers no text, so a call at a terminal names the
// flag. Empty text is an argument error, because a body is the point of a
// write.
func threadsBody(kind string, flags threadsFlags, stdin io.Reader, stderr io.Writer) (string, bool) {
	if flags.bodyFile != "" {
		raw, err := os.ReadFile(flags.bodyFile)
		if err != nil {
			fail(stderr, spec.ArgError, "body file %s: %v (see project help threads)", flags.bodyFile, err)
			return "", false
		}
		return string(raw), true
	}
	if f, ok := stdin.(*os.File); ok && isTerminal(f) {
		fail(stderr, spec.ArgError, "threads %s needs --body-file at a terminal (see project help threads)", kind)
		return "", false
	}
	raw, err := io.ReadAll(stdin)
	if err != nil {
		fail(stderr, spec.GeneralError, "threads %s: %v", kind, err)
		return "", false
	}
	if strings.TrimSpace(string(raw)) == "" {
		fail(stderr, spec.ArgError, "threads %s needs text: give --body-file or piped input", kind)
		return "", false
	}
	return string(raw), true
}

// threadsAuthor answers the author of a write: the flag, or the git identity
// of the repository sanitized into the login shape.
func threadsAuthor(flag string, stderr io.Writer) (string, bool) {
	if flag != "" {
		if !threadLogin.MatchString(flag) {
			fail(stderr, spec.ArgError, "author %s is no login: use lowercase letters, digits, and hyphens (see project help threads)", flag)
			return "", false
		}
		return flag, true
	}
	name, _ := runCmd(cwd(), nil, "git", "config", "user.name")
	login := sanitizeLogin(name)
	if login == "" {
		fail(stderr, spec.ArgError, "git names no user here: give --author")
		return "", false
	}
	return login, true
}

// sanitizeLogin lowers a git identity into the login shape of the store:
// every run of bytes outside the login alphabet becomes one hyphen, and no
// hyphen stays at an end.
func sanitizeLogin(name string) string {
	nonLogin := regexp.MustCompile(`[^a-z0-9-]+`)
	login := nonLogin.ReplaceAllString(strings.ToLower(strings.TrimSpace(name)), "-")
	login = strings.Trim(login, "-")
	return login
}

// threadsNew implements `project threads new <slug> ...`: it writes
// thread.md of a new thread.
func threadsNew(argv []string, stdin io.Reader, stderr io.Writer) spec.ExitCode {
	flags, ok := parseThreadsFlags("new", argv, stderr)
	if !ok {
		return spec.ArgError
	}
	if !threadSlug.MatchString(flags.slug) {
		return fail(stderr, spec.ArgError, "slug %s is not a thread slug: use lowercase letters, digits, and hyphens (see project help threads)", flags.slug)
	}
	if flags.title == "" {
		return fail(stderr, spec.ArgError, "threads new needs --title (see project help threads)")
	}
	if flags.status == "" {
		flags.status = "open"
	}
	if flags.status != "open" && flags.status != "closed" {
		return fail(stderr, spec.ArgError, "status %s is neither open nor closed (see project help threads)", flags.status)
	}
	root, store, err := threadStore()
	if err != nil {
		return fail(stderr, spec.NotFound, "%v", err)
	}
	author, ok := threadsAuthor(flags.author, stderr)
	if !ok {
		return spec.ArgError
	}
	body, ok := threadsBody("new", flags, stdin, stderr)
	if !ok {
		return spec.ArgError
	}
	dir := filepath.Join(store, flags.slug)
	if info, err := os.Stat(dir); err == nil && info.IsDir() {
		return fail(stderr, spec.GeneralError, "the thread %s exists", flags.slug)
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fail(stderr, spec.GeneralError, "threads: %v", err)
	}
	meta := threadMeta{title: flags.title, author: author, date: time.Now().UTC().Format(threadDate), status: flags.status, origin: flags.origin}
	path := filepath.Join(dir, "thread.md")
	if err := writeThreadFile(path, meta, body); err != nil {
		return fail(stderr, spec.GeneralError, "threads: %v", err)
	}
	printfDiag(stderr, "threads: wrote %s", filepath.Join(relTo(root, path)))
	return spec.Success
}

// threadsAdd implements `project threads add <slug> ...`: it writes the next
// event file of a thread.
func threadsAdd(argv []string, stdin io.Reader, stderr io.Writer) spec.ExitCode {
	flags, ok := parseThreadsFlags("add", argv, stderr)
	if !ok {
		return spec.ArgError
	}
	if !threadSlug.MatchString(flags.slug) {
		return fail(stderr, spec.ArgError, "slug %s is not a thread slug: use lowercase letters, digits, and hyphens (see project help threads)", flags.slug)
	}
	if flags.typ == "" {
		return fail(stderr, spec.ArgError, "threads add needs --type (see project help threads)")
	}
	if flags.typ != "comment" && flags.typ != "verdict" {
		return fail(stderr, spec.ArgError, "type %s is neither comment nor verdict (see project help threads)", flags.typ)
	}
	root, store, err := threadStore()
	if err != nil {
		return fail(stderr, spec.NotFound, "%v", err)
	}
	dir := filepath.Join(store, flags.slug)
	if info, err := os.Stat(dir); err != nil || !info.IsDir() {
		return fail(stderr, spec.NotFound, "no thread %s", flags.slug)
	}
	author, ok := threadsAuthor(flags.author, stderr)
	if !ok {
		return spec.ArgError
	}
	body, ok := threadsBody("add", flags, stdin, stderr)
	if !ok {
		return spec.ArgError
	}
	next, err := nextEventSeq(dir)
	if err != nil {
		return fail(stderr, spec.GeneralError, "threads: %v", err)
	}
	meta := threadMeta{typ: flags.typ, author: author, date: time.Now().UTC().Format(threadDate)}
	path := filepath.Join(dir, fmt.Sprintf("%04d-%s-%s.md", next, flags.typ, author))
	if err := writeThreadFile(path, meta, body); err != nil {
		return fail(stderr, spec.GeneralError, "threads: %v", err)
	}
	printfDiag(stderr, "threads: wrote %s", relTo(root, path))
	return spec.Success
}

// nextEventSeq answers the sequence that the next event of a thread takes:
// one above the highest sequence that the directory holds, and 1 for an
// empty one.
func nextEventSeq(dir string) (int, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return 0, err
	}
	next := 1
	for _, entry := range entries {
		match := threadEventName.FindStringSubmatch(entry.Name())
		if match == nil {
			continue
		}
		seq, err := strconv.Atoi(match[1])
		if err != nil {
			continue
		}
		if seq >= next {
			next = seq + 1
		}
	}
	return next, nil
}

// relTo answers the path of a store file as the messages name it, relative
// to the repository root.
func relTo(root, path string) string {
	rel, err := filepath.Rel(root, path)
	if err != nil {
		return path
	}
	return filepath.ToSlash(rel)
}
