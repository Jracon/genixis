// Package spec implements the machine-facing output contracts of this tool:
// the exit-code table and the JSON response envelope.
//
// Both come from the CLI agent specification (cli-agent-spec), vendored as
// pinned fixtures one directory up. Issue #74 (phase 3) adopts these two
// contracts and nothing else from that specification: no conformance kit, no
// skills, no runtime dependency. The machine-facing subcommands (add, spawn
// --headless, list) emit one envelope on stdout and exit with codes from the
// subset that applies to this tool. Interactive subcommands stay plain text
// but exit with codes from the same table.
//
// Exit-code subset of this tool, and where each code fires:
//
//	 0 SUCCESS            operation completed
//	 1 GENERAL_ERROR      unclassified failure (a git step failed, and so on)
//	 2 ARG_ERROR          bad arguments: a wrong flag, a missing branch, a
//	                      spawn without a prompt, a form this tool refuses
//	 5 NOT_FOUND          a named project, branch, plan, or worktree is absent
//	 7 PERMISSION_DENIED  the tool refuses for policy: discard outside a
//	                      person's terminal, a close the closeCheck vetoes
//	11 RATE_LIMITED       reserved: a called service reports rate limiting.
//	                      No code path emits it today; the dispatcher (phase 4)
//	                      parses it, so the code stays in the table
//	12 UNAVAILABLE        a dependency is beyond reach: the ssh of a delegated
//	                      call times out, the claude of a headless spawn is
//	                      missing
package spec

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
)

// ExitCode is a process exit code from the vendored table. The zero value is
// SUCCESS, so a zero-valued ExitCode is a valid, successful one.
type ExitCode int

// The exit codes this tool emits. The names match the vendored table's
// x-enum-varnames entries, and spec_test.go pins that match.
const (
	Success          ExitCode = 0
	GeneralError     ExitCode = 1
	ArgError         ExitCode = 2
	NotFound         ExitCode = 5
	PermissionDenied ExitCode = 7
	RateLimited      ExitCode = 11
	Unavailable      ExitCode = 12
)

// exitNames maps each code to its name in the vendored table.
var exitNames = map[ExitCode]string{
	Success:          "SUCCESS",
	GeneralError:     "GENERAL_ERROR",
	ArgError:         "ARG_ERROR",
	NotFound:         "NOT_FOUND",
	PermissionDenied: "PERMISSION_DENIED",
	RateLimited:      "RATE_LIMITED",
	Unavailable:      "UNAVAILABLE",
}

// exitRetryable mirrors the retry guidance of the vendored table: only the
// infrastructure codes tell the caller to retry.
var exitRetryable = map[ExitCode]bool{
	RateLimited: true,
	Unavailable: true,
}

// Name returns the stable name of the code in the vendored table, or
// "UNKNOWN" for a code outside the subset.
func (c ExitCode) Name() string {
	if name, ok := exitNames[c]; ok {
		return name
	}
	return "UNKNOWN"
}

// Retryable reports whether the vendored table tells the caller to retry the
// same invocation after a back-off.
func (c ExitCode) Retryable() bool {
	return exitRetryable[c]
}

// Error is a structured failure for an envelope. Code is a stable identifier
// the caller branches on; the vendored schema pins its shape to
// ^[A-Z][A-Z0-9_]+$.
type Error struct {
	Code        string `json:"code"`
	Message     string `json:"message"`
	Detail      string `json:"detail,omitempty"`
	Cause       string `json:"cause,omitempty"`
	Retryable   bool   `json:"retryable,omitempty"`
	FixRequired string `json:"fix_required,omitempty"`
	Suggestion  string `json:"suggestion,omitempty"`
}

// Warning is a non-fatal diagnostic. The vendored schema requires a code and
// a message and allows no other property.
type Warning struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// Meta carries the self-describing fields of an envelope. The vendored schema
// requires exit_code and duration_ms; the rest are the optional fields this
// tool fills in.
type Meta struct {
	Command       string `json:"command"`
	DurationMs    int64  `json:"duration_ms"`
	ExitCode      int    `json:"exit_code"`
	SchemaVersion string `json:"schema_version,omitempty"`
	ToolVersion   string `json:"tool_version,omitempty"`
}

// Envelope is the one JSON object a machine-facing subcommand prints on
// stdout. The five keys are always present, whatever the outcome.
type Envelope struct {
	OK       bool      `json:"ok"`
	Data     any       `json:"data"`
	Error    *Error    `json:"error"`
	Warnings []Warning `json:"warnings"`
	Meta     Meta      `json:"meta"`
}

// Build assembles an envelope for one finished invocation. exitCode decides
// every derived field: ok, error, and the retryable flags. data may be nil
// only on failure, and warnings may be empty but never nil.
func Build(command string, exitCode ExitCode, data any, errDetail *Error, warnings []Warning, durationMs int64) Envelope {
	if warnings == nil {
		warnings = []Warning{}
	}
	meta := Meta{
		Command:    command,
		DurationMs: durationMs,
		ExitCode:   int(exitCode),
	}
	if errDetail != nil {
		errDetail.Retryable = exitCode.Retryable()
	} else if exitCode != Success {
		errDetail = &Error{
			Code:    exitCode.Name(),
			Message: fmt.Sprintf("%s ended with exit code %s", command, exitCode.Name()),
		}
	}
	return Envelope{
		OK:       exitCode == Success,
		Data:     data,
		Error:    errDetail,
		Warnings: warnings,
		Meta:     meta,
	}
}

// Write prints the envelope as one JSON object with a trailing newline.
func Write(w io.Writer, e Envelope) error {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(e); err != nil {
		return err
	}
	_, err := w.Write(buf.Bytes())
	return err
}
