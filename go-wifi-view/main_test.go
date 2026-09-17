package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// ============================================================
// TestMain: shared setup — initialize i18n map and any package state
// touched by the functions under test.
// ============================================================
func TestMain(m *testing.M) {
	s = map[string]string{
		"strength_empty":   "N/A",
		"strength_weak":    "Weak",
		"strength_medium":  "Medium",
		"strength_strong":  "Strong",
		"invalid_num":      "Invalid",
	}
	m.Run()
}

// ============================================================
// parseProfileLine
// Parses a single line of `netsh wlan show profiles` output, returning
// the SSID (or empty if the line isn't a profile entry).
// ============================================================
func TestParseProfileLine(t *testing.T) {
	tests := []struct {
		name string
		line string
		want string
	}{
		// Profile entries (column is "Profile" / equivalent in any lang)
		{"en profile", "    Profile         : HomeWiFi", "HomeWiFi"},
		{"chinese profile", "    配置文件         : HomeWiFi", "HomeWiFi"},
		{"no leading spaces", "Profile : Office", "Office"},
		{"unicode SSID", "    Profile         : 办公室-5G", "办公室-5G"},

		// Non-profile lines should return ""
		{"group policy entry", "    All User Profile     : Guest", ""},
		{"empty value", "    Profile : ", ""},
		{"no colon", "    Profile", ""},
		{"none placeholder", "    <None>", ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseProfileLine(tt.line)
			if got != tt.want {
				t.Errorf("parseProfileLine(%q) = %q, want %q", tt.line, got, tt.want)
			}
		})
	}
}

// ============================================================
// extractPassword
// Pulls the WiFi password out of a `netsh wlan show profile ... key=clear`
// line. Matches one of pwdKeywords (multi-language) or English fallback
// ("key" + "content").
// ============================================================
func TestExtractPassword(t *testing.T) {
	tests := []struct {
		name string
		line string
		want string
	}{
		// English
		{"en key content", "    Key Content            : mySecretPass", "mySecretPass"},
		{"en caps", "    KEY CONTENT            : MyPwd!", "MyPwd!"},

		// Chinese
		{"zh 关键内容", "    关键内容            : 我的密码123", "我的密码123"},

		// Japanese
		{"jp key", "    キー コンテンツ            : passwd", "passwd"},

		// German
		{"de schluessel", "    Schlüsselinhalt       : passwort", "passwort"},

		// Danish
		{"da noegleindhold", "    Nøgleindhold          : adgangskode", "adgangskode"},

		// Norwegian (added in v3.1 — was previously relying on key/content fallback)
		{"no noekkelinnhold", "    Nøkkelinnhold         : passord", "passord"},

		// Fallback: lowercase "key content" still matches
		{"fallback lower", "    key content            : fallback123", "fallback123"},

		// Negative cases
		{"no keyword", "    Authentication         : WPA2-Personal", ""},
		{"empty value", "    Key Content            : ", ""},
		{"unrelated", "    SSID name              : \"MyWiFi\"", ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := extractPassword(tt.line)
			if got != tt.want {
				t.Errorf("extractPassword(%q) = %q, want %q", tt.line, got, tt.want)
			}
		})
	}
}

// ============================================================
// parseSelection
// Parses "1,3,5-7" style user input into a slice of 1-based indices,
// clamped to [1, max]. Out-of-range or non-numeric values are skipped.
// ============================================================
func TestParseSelection(t *testing.T) {
	tests := []struct {
		name string
		in   string
		max  int
		want []int
	}{
		{"single", "3", 10, []int{3}},
		{"multiple", "1,3,5", 10, []int{1, 3, 5}},
		{"with spaces", " 1 , 3 , 5 ", 10, []int{1, 3, 5}},
		{"empty parts", "1,,3", 10, []int{1, 3}},
		{"out of range skipped", "1,99,3", 10, []int{1, 3}},
		{"zero skipped", "0,1,2", 10, []int{1, 2}},
		{"non-numeric skipped", "abc,1,def,2", 10, []int{1, 2}},
		{"empty input", "", 10, nil},
		{"all whitespace", "  ,  , ", 10, nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseSelection(tt.in, tt.max)
			if !equalInts(got, tt.want) {
				t.Errorf("parseSelection(%q, %d) = %v, want %v", tt.in, tt.max, got, tt.want)
			}
		})
	}
}

func equalInts(a, b []int) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// ============================================================
// escapeQRString
// Per WiFi QR spec: escape \, ; , : so the SSID/password can contain them.
// ============================================================
func TestEscapeQRString(t *testing.T) {
	tests := []struct {
		in, want string
	}{
		{"plain", "plain"},
		{"with space", "with space"},
		{"back;slash", `back\;slash`},
		{`back\slash`, `back\\slash`},
		{"a,b,c", `a\,b\,c`},
		{"a:b", `a\:b`},
		{`all;\,:`, `all\;\\\,` + "\u003a" + ""}, // sanity case
		{`mixed\;,:`, `mixed\\\;\\\,\:`},
	}
	for _, tt := range tests {
		t.Run(tt.in, func(t *testing.T) {
			got := escapeQRString(tt.in)
			if got != tt.want {
				t.Errorf("escapeQRString(%q) = %q, want %q", tt.in, got, tt.want)
			}
		})
	}
}

// ============================================================
// buildWiFiString — assembles the WIFI:T:WPA;...; QR payload.
// ============================================================
func TestBuildWiFiString(t *testing.T) {
	tests := []struct {
		ssid, pwd, want string
	}{
		{"Home", "secret123", "WIFI:T:WPA;S:Home;P:secret123;;"},
		{"with space", "pass word", "WIFI:T:WPA;S:with space;P:pass word;;"},
		{`back\slash`, `p;ass`, `WIFI:T:WPA;S:back\\slash;P:p\;ass;;`},
		{"comma,here", "ok", "WIFI:T:WPA;S:comma\\,here;P:ok;;"},
	}
	for _, tt := range tests {
		t.Run(tt.ssid, func(t *testing.T) {
			got := buildWiFiString(tt.ssid, tt.pwd)
			if got != tt.want {
				t.Errorf("buildWiFiString(%q, %q) = %q, want %q", tt.ssid, tt.pwd, got, tt.want)
			}
		})
	}
}

// ============================================================
// csvEscape (RFC 4180)
// ============================================================
func TestCsvEscape(t *testing.T) {
	tests := []struct {
		in, want string
	}{
		{"plain", "plain"},
		{"", ""},
		{"with,comma", "\"with,comma\""},
		{`with"quote`, `with""quote`},
		{`both,"x`, `"both,""x"`},
	}
	for _, tt := range tests {
		t.Run(tt.in, func(t *testing.T) {
			got := csvEscape(tt.in)
			if got != tt.want {
				t.Errorf("csvEscape(%q) = %q, want %q", tt.in, got, tt.want)
			}
		})
	}
}

// ============================================================
// sanitizeFilename
// Replaces \ / : * ? " < > | and space with underscore.
// ============================================================
func TestSanitizeFilename(t *testing.T) {
	tests := []struct {
		in, want string
	}{
		{"plain", "plain"},
		{"with space", "with_space"},
		{`back\slash`, "back_slash"},
		{"forward/slash", "forward_slash"},
		{"colon:test", "colon_test"},
		{`star*and?question`, "star_and_question"},
		{`quotes"and<angle>`, "quotes_and_angle_"},
		{"pipe|char", "pipe_char"},
		{"mix\\of:all/used", "mix_of_all_used"},
	}
	for _, tt := range tests {
		t.Run(tt.in, func(t *testing.T) {
			got := sanitizeFilename(tt.in)
			if got != tt.want {
				t.Errorf("sanitizeFilename(%q) = %q, want %q", tt.in, got, tt.want)
			}
		})
	}
}

// ============================================================
// fuzzySearchWiFi — multi-token substring AND, case-insensitive.
// ============================================================
func TestFuzzySearchWiFi(t *testing.T) {
	orig := wifiNames
	defer func() { wifiNames = orig }()

	wifiNames = []string{
		"CMCC-XanaHotel1e8329-5G",
		"TP-LINK_Home",
		"Home5G",
		"Office-Guest",
		"home_office",
		"Restaurant-WiFi",
	}

	tests := []struct {
		name  string
		query string
		want  []int
	}{
		{"empty returns all", "", []int{0, 1, 2, 3, 4, 5}},
		{"whitespace returns all", "   ", []int{0, 1, 2, 3, 4, 5}},
		{"single substring", "home", []int{1, 2, 4}},
		{"single case-insensitive", "HOME", []int{1, 2, 4}},
		{"no match", "nonexistent", nil},
		{"multi-token AND", "home 5g", []int{2}},
		{"multi-token reversed", "5g home", []int{2}},
		{"multi-token none", "home xyz", nil},
		{"unicode substring", "酒店", nil},
		{"exact match", "Restaurant-WiFi", []int{5}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := fuzzySearchWiFi(tt.query)
			if !equalInts(got, tt.want) {
				t.Errorf("fuzzySearchWiFi(%q) = %v, want %v", tt.query, got, tt.want)
			}
		})
	}
}

// ============================================================
// isSequential — 4+ chars that are each ±1 from previous (asc/desc).
// ============================================================
func TestIsSequential(t *testing.T) {
	tests := []struct {
		in   string
		want bool
	}{
		{"", false},
		{"ab", false},
		{"abc", false},   // 3 chars, threshold is 3 (so asc reaches 2, not enough)
		{"abcd", true},   // asc=3
		{"1234", true},   // asc=3
		{"dcba", true},   // desc=3
		{"4321", true},   // desc=3
		{"abc1", false},  // broken run
		{"password", false},
		{"xyz1234", true}, // asc=3 starting at '1'
		{"aBcd", true},   // case-insensitive
	}
	for _, tt := range tests {
		t.Run(tt.in, func(t *testing.T) {
			got := isSequential(tt.in)
			if got != tt.want {
				t.Errorf("isSequential(%q) = %v, want %v", tt.in, got, tt.want)
			}
		})
	}
}

// ============================================================
// isRepeated — 3+ consecutive identical chars.
// ============================================================
func TestIsRepeated(t *testing.T) {
	tests := []struct {
		in   string
		want bool
	}{
		{"", false},
		{"a", false},
		{"aa", false},
		{"aaa", true},
		{"aaaa", true},
		{"aab", false},
		{"111a", true},
		{"ab111", true},
		{"normal", false},
	}
	for _, tt := range tests {
		t.Run(tt.in, func(t *testing.T) {
			got := isRepeated(tt.in)
			if got != tt.want {
				t.Errorf("isRepeated(%q) = %v, want %v", tt.in, got, tt.want)
			}
		})
	}
}

// ============================================================
// passwordStrength
// ============================================================
func TestPasswordStrength(t *testing.T) {
	tests := []struct {
		name     string
		pwd, ssid string
		minScore int // score must be ≥ this for the label to make sense
		labelOneOf []string // any of these labels is acceptable
	}{
		// Empty
		{"empty password", "", "MyWiFi", 0, []string{"N/A"}},

		// Common passwords — should score 0–1 (weak)
		{"common 'password'", "password", "MyWiFi", 0, []string{"Weak"}},
		{"common '12345678'", "12345678", "MyWiFi", 0, []string{"Weak"}},
		{"common 'qwerty'", "qwerty", "MyWiFi", 0, []string{"Weak"}},

		// SSID substring penalty
		{"contains SSID", "MyWiFi2024!", "MyWiFi", 0, []string{"Weak", "Medium"}},

		// Short passwords
		{"very short", "aB2!", "MyWiFi", 0, []string{"Weak"}},
		{"short", "abcd12", "MyWiFi", 0, []string{"Weak"}},

		// Sequential chars penalty
		{"sequential", "abcdEFGH", "MyWiFi", 0, []string{"Weak", "Medium"}},

		// Repeated chars penalty
		{"repeated", "Xy9!aaaQ", "MyWiFi", 1, []string{"Weak", "Medium"}},

		// Decent passwords
		{"medium", "Xy9!kQwP", "MyWiFi", 1, []string{"Weak", "Medium"}},
		{"medium-long", "Xy9!kQwP2n", "MyWiFi", 2, []string{"Medium", "Strong"}},

		// Strong passwords
		{"strong", "Tr0ub4dor&3", "MyWiFi", 4, []string{"Strong"}},
		{"very strong", "C0rrect-Horse-Battery-Staple!", "MyWiFi", 5, []string{"Strong"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			score, label, _ := passwordStrength(tt.pwd, tt.ssid)
			if score < tt.minScore {
				t.Errorf("passwordStrength(%q,%q) score=%d, want ≥%d", tt.pwd, tt.ssid, score, tt.minScore)
			}
			found := false
			for _, l := range tt.labelOneOf {
				if label == l {
					found = true
					break
				}
			}
			if !found {
				t.Errorf("passwordStrength(%q,%q) label=%q, want one of %v", tt.pwd, tt.ssid, label, tt.labelOneOf)
			}
		})
	}
}

// ============================================================
// buildStrengthBar — output should be max chars total, with a color
// sequence wrapping filled and empty slots. We just check structure.
// ============================================================
func TestBuildStrengthBar(t *testing.T) {
	tests := []struct {
		score, max int
	}{
		{0, 5},
		{1, 5},
		{2, 5},
		{3, 5},
		{5, 5},
		{0, 10},
		{7, 10},
		{99, 5}, // clamped to 5
		{-3, 5}, // clamped to 0
	}
	for _, tt := range tests {
		t.Run("", func(t *testing.T) {
			bar := buildStrengthBar(tt.score, tt.max)
			if bar == "" {
				t.Errorf("buildStrengthBar returned empty")
			}
			// Strip ANSI escapes for content check.
			clean := stripAnsi(bar)
			filled := strings.Count(clean, "\u2588")
			empty := strings.Count(clean, "\u2591")
			wantFilled := tt.score
			if wantFilled > tt.max {
				wantFilled = tt.max
			}
			if wantFilled < 0 {
				wantFilled = 0
			}
			wantEmpty := tt.max - wantFilled
			if filled != wantFilled {
				t.Errorf("filled slots = %d, want %d", filled, wantFilled)
			}
			if empty != wantEmpty {
				t.Errorf("empty slots = %d, want %d", empty, wantEmpty)
			}
		})
	}
}

// stripAnsi removes ANSI escape sequences from s.
func stripAnsi(s string) string {
	var b strings.Builder
	i := 0
	for i < len(s) {
		if s[i] == 0x1b && i+1 < len(s) && s[i+1] == '[' {
			// Skip until 'm' or other terminator.
			i += 2
			for i < len(s) && s[i] != 'm' {
				i++
			}
			i++ // skip 'm'
			continue
		}
		b.WriteByte(s[i])
		i++
	}
	return b.String()
}

// ============================================================
// escapeForShellArg — protect cmd.exe /c "...\"%s\"..." invocations
// from SSID injection. SSID is arbitrary user-controlled text and
// could contain cmd.exe metacharacters like " & | < > ( ) ; , ^
// that would otherwise be interpreted as shell syntax.
// ============================================================
func TestEscapeForShellArg(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{"plain SSID unchanged", "HomeWiFi-5G", "HomeWiFi-5G"},
		{"empty string", "", ""},
		{"single quote doubled", `Foo"`, `"Foo""`},
		{"ampersand escaped", "Foo&Bar", "Foo^&Bar"},
		{"pipe escaped", "Foo|Bar", "Foo^|Bar"},
		{"angle brackets escaped", "Foo<Bar>Baz", "Foo^<Bar^>Baz"},
		{"parens escaped", "Foo(Bar)", "Foo^(Bar^)"},
		{"caret escaped first", "Foo^Bar", "Foo^^Bar"},
		{"combo injection attempt", `Foo"&calc&"`, `"Foo""^&calc^&""`},
		{"space kept literal (handled by surrounding quotes)", "Foo Bar", "Foo Bar"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := escapeForShellArg(tt.in)
			if got != tt.want {
				t.Errorf("escapeForShellArg(%q) = %q, want %q", tt.in, got, tt.want)
			}
		})
	}
}

// ============================================================
// uniqueFilename — when the requested path already exists on disk,
// append "_(2)", "_(3)", ... before the extension until a free slot
// is found. Protects against same-second export / QR collisions.
// ============================================================
func TestUniqueFilename(t *testing.T) {
	tmp := t.TempDir()

	tests := []struct {
		name string
		setup []string // filenames to pre-create before calling
		input string
		wantSuffix string // expected suffix appended ("" means no change)
	}{
		{
			name: "no collision returns original",
			setup: nil,
			input: filepath.Join(tmp, "fresh.txt"),
			wantSuffix: "",
		},
		{
			name: "one collision appends _(2)",
			setup: []string{"taken.txt"},
			input: filepath.Join(tmp, "taken.txt"),
			wantSuffix: "_(2).txt",
		},
		{
			name: "two collisions appends _(3)",
			setup: []string{"taken.txt", "taken_(2).txt"},
			input: filepath.Join(tmp, "taken.txt"),
			wantSuffix: "_(3).txt",
		},
		{
			name: "gap in sequence still picks next free slot",
			setup: []string{"a.txt", "a_(2).txt"}, // _(3) is free
			input: filepath.Join(tmp, "a.txt"),
			wantSuffix: "_(3).txt",
		},
		{
			name: "preserves extension",
			setup: []string{"x.png"},
			input: filepath.Join(tmp, "x.png"),
			wantSuffix: "_(2).png",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			for _, f := range tt.setup {
				if err := os.WriteFile(filepath.Join(tmp, f), []byte("x"), 0644); err != nil {
					t.Fatal(err)
				}
			}
			got := uniqueFilename(tt.input)
			want := tt.input
			if tt.wantSuffix != "" {
				ext := filepath.Ext(tt.input)
				want = strings.TrimSuffix(tt.input, ext) + tt.wantSuffix
			}
			if got != want {
				t.Errorf("uniqueFilename(%q) = %q, want %q", tt.input, got, want)
			}
		})
	}
}

// ============================================================
// buildProgressBar — percentage in 0–100 range, bar width = 10.
// ============================================================
func TestBuildProgressBar(t *testing.T) {
	tests := []struct {
		processed, total int
		wantPct          int
	}{
		{0, 100, 0},
		{1, 100, 1},
		{50, 100, 50},
		{100, 100, 100},
		{0, 0, 0},  // avoid div-by-zero
		{5, 0, 0},
		{25, 100, 25},
	}
	for _, tt := range tests {
		t.Run("", func(t *testing.T) {
			bar := stripAnsi(buildProgressBar(tt.processed, tt.total))
			if !strings.Contains(bar, fmt.Sprintf("%d%%", tt.wantPct)) {
				t.Errorf("buildProgressBar(%d, %d) = %q, want %d%%", tt.processed, tt.total, bar, tt.wantPct)
			}
		})
	}
}