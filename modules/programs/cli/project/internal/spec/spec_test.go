package spec

import (
	"bytes"
	"embed"
	"encoding/json"
	"regexp"
	"testing"
)

//go:embed fixtures/exit-code.json fixtures/response-envelope.json
var fixtures embed.FS

type exitTable struct {
	Enum   []int             `json:"enum"`
	Names  []string          `json:"x-enum-varnames"`
	Groups map[string][]int  `json:"x-groups"`
	Ranges map[string]string `json:"x-code-ranges"`
}

type envelopeSchema struct {
	Required             []string        `json:"required"`
	AdditionalProperties bool            `json:"additionalProperties"`
	Properties           map[string]any  `json:"properties"`
	Definitions          map[string]defn `json:"definitions"`
}

type defn struct {
	Type                 string         `json:"type"`
	Required             []string       `json:"required"`
	AdditionalProperties *bool          `json:"additionalProperties"`
	Properties           map[string]any `json:"properties"`
}

func loadExitTable(t *testing.T) exitTable {
	t.Helper()
	raw, err := fixtures.ReadFile("fixtures/exit-code.json")
	if err != nil {
		t.Fatalf("read vendored exit table: %v", err)
	}
	var table exitTable
	if err := json.Unmarshal(raw, &table); err != nil {
		t.Fatalf("parse vendored exit table: %v", err)
	}
	return table
}

// Every code this tool emits must exist in the vendored table, under the
// table's own name for it. This pins the constants to the fixture.
func TestExitCodesMatchVendoredTable(t *testing.T) {
	table := loadExitTable(t)
	for code, want := range exitNames {
		idx := -1
		for i, v := range table.Enum {
			if v == int(code) {
				idx = i
				break
			}
		}
		if idx < 0 {
			t.Errorf("exit code %d (%s) is not in the vendored table", code, want)
			continue
		}
		if table.Names[idx] != want {
			t.Errorf("exit code %d: this tool names it %s, the vendored table names it %s", code, want, table.Names[idx])
		}
	}
}

// The tool must never fall back to a literal code outside the table.
func TestExitCodeOutsideTableHasNoName(t *testing.T) {
	for _, code := range []ExitCode{3, 4, 6, 8, 9, 10, 13, 14, 15, 99, 127} {
		if code.Name() != "UNKNOWN" {
			t.Errorf("exit code %d must not have a name", code)
		}
	}
}

// Retryable must mirror the vendored guidance: only RATE_LIMITED and
// UNAVAILABLE tell the caller to retry the same call.
func TestRetryableMatchesVendoredGuidance(t *testing.T) {
	for code, want := range map[ExitCode]bool{
		Success:          false,
		GeneralError:     false,
		ArgError:         false,
		NotFound:         false,
		PermissionDenied: false,
		RateLimited:      true,
		Unavailable:      true,
	} {
		if got := code.Retryable(); got != want {
			t.Errorf("%s: Retryable() = %v, want %v", code.Name(), got, want)
		}
	}
}

func loadEnvelopeSchema(t *testing.T) envelopeSchema {
	t.Helper()
	raw, err := fixtures.ReadFile("fixtures/response-envelope.json")
	if err != nil {
		t.Fatalf("read vendored envelope schema: %v", err)
	}
	var schema envelopeSchema
	if err := json.Unmarshal(raw, &schema); err != nil {
		t.Fatalf("parse vendored envelope schema: %v", err)
	}
	return schema
}

func writeEnvelope(t *testing.T, e Envelope) map[string]json.RawMessage {
	t.Helper()
	var buf bytes.Buffer
	if err := Write(&buf, e); err != nil {
		t.Fatalf("write envelope: %v", err)
	}
	var obj map[string]json.RawMessage
	if err := json.Unmarshal(buf.Bytes(), &obj); err != nil {
		t.Fatalf("envelope is not one JSON object: %v", err)
	}
	return obj
}

// The envelope must carry exactly the keys the vendored schema allows: the
// five required ones, and no more, because the schema forbids additions.
func TestEnvelopeKeysMatchVendoredSchema(t *testing.T) {
	schema := loadEnvelopeSchema(t)
	for _, exit := range []ExitCode{Success, GeneralError, ArgError, NotFound, PermissionDenied, RateLimited, Unavailable} {
		e := Build("list", exit, map[string]any{"x": 1}, nil, nil, 3)
		obj := writeEnvelope(t, e)
		if len(obj) != len(schema.Properties) {
			t.Errorf("exit %d: envelope has %d keys, schema has %d", exit, len(obj), len(schema.Properties))
		}
		for _, key := range schema.Required {
			if _, ok := obj[key]; !ok {
				t.Errorf("exit %d: envelope is missing required key %s", exit, key)
			}
		}
		for key := range obj {
			if _, ok := schema.Properties[key]; !ok {
				t.Errorf("exit %d: envelope has key %s, which the schema does not allow", exit, key)
			}
		}
	}
}

// ok is derived from exit_code alone, in both directions of the vendored
// if/then, and warnings are never null.
func TestEnvelopeDerivations(t *testing.T) {
	codePattern := regexp.MustCompile(`^[A-Z][A-Z0-9_]+$`)
	for _, exit := range []ExitCode{Success, GeneralError, ArgError, NotFound, PermissionDenied, RateLimited, Unavailable} {
		e := Build("add", exit, nil, nil, nil, 1)
		obj := writeEnvelope(t, e)
		var ok bool
		if err := json.Unmarshal(obj["ok"], &ok); err != nil {
			t.Fatalf("ok is not a boolean: %v", err)
		}
		if ok != (exit == Success) {
			t.Errorf("exit %d: ok = %v", exit, ok)
		}
		var errObj map[string]any
		if exit == Success {
			if string(obj["error"]) != "null" {
				t.Errorf("exit %d: error must be null on success", exit)
			}
		} else {
			if err := json.Unmarshal(obj["error"], &errObj); err != nil {
				t.Fatalf("exit %d: error is not an object: %v", exit, err)
			}
			code, _ := errObj["code"].(string)
			if !codePattern.MatchString(code) {
				t.Errorf("exit %d: error.code %q breaks the vendored pattern", exit, code)
			}
			if _, ok := errObj["message"]; !ok {
				t.Errorf("exit %d: error has no message", exit)
			}
		}
		if string(obj["warnings"]) == "null" {
			t.Errorf("exit %d: warnings must never be null", exit)
		}
	}
}

// A specific error keeps its stable code, and retryable mirrors the table.
func TestEnvelopeCarriesErrorDetail(t *testing.T) {
	e := Build("add", NotFound, nil, &Error{Code: "PLAN_NOT_FOUND", Message: "no plan zai"}, nil, 2)
	obj := writeEnvelope(t, e)
	var errObj Error
	if err := json.Unmarshal(obj["error"], &errObj); err != nil {
		t.Fatalf("error detail did not survive the envelope: %v", err)
	}
	if errObj.Code != "PLAN_NOT_FOUND" {
		t.Errorf("error.code = %q, want PLAN_NOT_FOUND", errObj.Code)
	}
	if errObj.Retryable {
		t.Error("NOT_FOUND must not be retryable")
	}
	var meta Meta
	if err := json.Unmarshal(obj["meta"], &meta); err != nil {
		t.Fatalf("meta did not parse: %v", err)
	}
	if meta.ExitCode != int(NotFound) || meta.Command != "add" || meta.DurationMs != 2 {
		t.Errorf("meta = %+v", meta)
	}
}

// The meta object must keep the two fields the vendored schema requires.
func TestMetaRequiredFields(t *testing.T) {
	schema := loadEnvelopeSchema(t)
	metaDef := schema.Definitions["ResponseMeta"]
	e := Build("list", Success, nil, nil, nil, 7)
	obj := writeEnvelope(t, e)
	var meta map[string]any
	if err := json.Unmarshal(obj["meta"], &meta); err != nil {
		t.Fatalf("meta is not an object: %v", err)
	}
	for _, key := range metaDef.Required {
		if _, ok := meta[key]; !ok {
			t.Errorf("meta is missing required key %s", key)
		}
	}
}

// A warning must carry a code and a message and nothing else.
func TestWarningShape(t *testing.T) {
	schema := loadEnvelopeSchema(t)
	warnDef := schema.Definitions["WarningDetail"]
	e := Build("add", Success, nil, nil, []Warning{{Code: "FETCH_FAILED", Message: "could not fetch origin"}}, 1)
	obj := writeEnvelope(t, e)
	var warnings []map[string]any
	if err := json.Unmarshal(obj["warnings"], &warnings); err != nil {
		t.Fatalf("warnings did not parse: %v", err)
	}
	if len(warnings) != 1 {
		t.Fatalf("got %d warnings, want 1", len(warnings))
	}
	for _, key := range warnDef.Required {
		if _, ok := warnings[0][key]; !ok {
			t.Errorf("warning is missing required key %s", key)
		}
	}
	if len(warnings[0]) != len(warnDef.Required) {
		t.Errorf("warning has keys beyond %v: %v", warnDef.Required, warnings[0])
	}
}
