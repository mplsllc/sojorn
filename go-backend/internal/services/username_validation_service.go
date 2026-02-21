// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package services

import (
	"context"
	"regexp"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

type UsernameViolation int

const (
	UsernameOK UsernameViolation = iota
	UsernameReserved
	UsernameInappropriate
	UsernameInvalidFormat
)

type UsernameCheckResult struct {
	Violation UsernameViolation
	Message   string
}

// ValidateUsernameWithDB checks a handle against the reserved_usernames DB table,
// inappropriate words, and format rules. All reserved names are managed via admin console.
func ValidateUsernameWithDB(ctx context.Context, pool *pgxpool.Pool, handle string) UsernameCheckResult {
	h := strings.ToLower(strings.TrimSpace(handle))

	// Format check
	if len(h) < 3 || len(h) > 30 {
		return UsernameCheckResult{UsernameInvalidFormat, "Username must be between 3 and 30 characters."}
	}
	if !validHandleRegex.MatchString(h) {
		return UsernameCheckResult{UsernameInvalidFormat, "Username can only contain letters, numbers, underscores, and periods."}
	}

	// Reserved check — DB only
	if pool != nil {
		var count int
		err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM reserved_usernames WHERE username = $1`, h).Scan(&count)
		if err == nil && count > 0 {
			return UsernameCheckResult{
				UsernameReserved,
				"This username is reserved. If you officially represent this brand, company, or public figure, you can submit a verification request at support@sojorn.net to claim it.",
			}
		}
	}

	// Inappropriate check
	if reason := isInappropriate(h); reason != "" {
		return UsernameCheckResult{UsernameInappropriate, "This username is not allowed: " + reason}
	}

	return UsernameCheckResult{UsernameOK, ""}
}

// ValidateDisplayName checks a display name for inappropriate content.
func ValidateDisplayName(name string) UsernameCheckResult {
	n := strings.ToLower(strings.TrimSpace(name))
	if len(n) == 0 || len(n) > 50 {
		return UsernameCheckResult{UsernameInvalidFormat, "Display name must be between 1 and 50 characters."}
	}
	if reason := isInappropriate(n); reason != "" {
		return UsernameCheckResult{UsernameInappropriate, "This display name is not allowed: " + reason}
	}
	return UsernameCheckResult{UsernameOK, ""}
}

var validHandleRegex = regexp.MustCompile(`^[a-z0-9_.]+$`)

// -------------------------------------------------------------------
// Inappropriate content filter
// -------------------------------------------------------------------

func isInappropriate(text string) string {
	// Remove common substitutions for bypass attempts
	normalized := normalizeUsername(text)

	for _, entry := range inappropriatePatterns {
		if entry.regex.MatchString(normalized) || entry.regex.MatchString(text) {
			return entry.reason
		}
	}
	return ""
}

type inappropriateEntry struct {
	regex  *regexp.Regexp
	reason string
}

var inappropriatePatterns []inappropriateEntry

func init() {
	type raw struct {
		pattern string
		reason  string
	}
	entries := []raw{
		// Slurs and hate speech
		{`\bn[i1!|]gg[e3a@][r]?\b`, "contains a racial slur"},
		{`\bf[a@]gg?[o0][t]?\b`, "contains a homophobic slur"},
		{`\bk[i1!]ke\b`, "contains an antisemitic slur"},
		{`\bsp[i1!]c\b`, "contains a racial slur"},
		{`\bch[i1!]nk\b`, "contains a racial slur"},
		{`\bw[e3]tb[a@]ck\b`, "contains a racial slur"},
		{`\bcoon\b`, "contains a racial slur"},
		{`\btr[a@]nn[yie]\b`, "contains a transphobic slur"},
		{`\bdyke\b`, "contains a homophobic slur"},
		{`\bretard(ed)?\b`, "contains an ableist slur"},

		// Sexually explicit
		{`\bp[o0]rn`, "contains sexually explicit content"},
		{`\bx{2,}`, "contains sexually explicit content"},
		{`\bhentai\b`, "contains sexually explicit content"},
		{`\bcum(sl[u]t|dump|bucket)\b`, "contains sexually explicit content"},
		{`\bpussy\b`, "contains sexually explicit content"},
		{`\bd[i1!]ck(head|face|sucker)`, "contains sexually explicit content"},
		{`\bc[o0]ck(sucker)?`, "contains sexually explicit content"},

		// Violent / threatening
		{`\bk[i1!]ll(er)?_(yo)?u`, "contains threatening language"},
		{`\bschool.?shoot`, "contains violent content"},
		{`\bmass.?murder`, "contains violent content"},
		{`\bgenocide\b`, "contains violent content"},
		{`\bterroris[tm]`, "contains references to terrorism"},
		{`\bisis\b`, "contains references to terrorism"},
		{`\bal.?qaeda\b`, "contains references to terrorism"},
		{`\bjihad(i|ist)?\b`, "contains references to terrorism"},

		// Drugs (hard)
		{`\bmeth(head|lab)\b`, "contains drug references"},
		{`\bcrackhead\b`, "contains drug references"},
		{`\bheroin(e)?\b`, "contains drug references"},
		{`\bfentanyl\b`, "contains drug references"},

		// Impersonation indicators
		{`\breal_?\b`, "may imply impersonation"},
		{`\bthe_?real\b`, "may imply impersonation"},
		{`\bofficial_\b`, "may imply impersonation"},
		{`\bnot_?fake\b`, "may imply impersonation"},

		// Scam / fraud
		{`\bfree.?money\b`, "suggests fraudulent activity"},
		{`\bcrypto.?scam\b`, "suggests fraudulent activity"},
		{`\bget.?rich\b`, "suggests fraudulent activity"},

		// Self-harm
		{`\bsu[i1!]c[i1!]de\b`, "contains references to self-harm"},
		{`\bkill.?myself\b`, "contains references to self-harm"},
		{`\bcut.?myself\b`, "contains references to self-harm"},

		// General profanity as usernames (strong)
		{`\bfuck`, "contains strong profanity"},
		{`\bsh[i1!]t(head|face|stain)`, "contains strong profanity"},
		{`\bass(hole|wipe|face|hat)`, "contains strong profanity"},
		{`\bbitch\b`, "contains strong profanity"},
		{`\bwhore\b`, "contains strong profanity"},
		{`\bslut\b`, "contains strong profanity"},
		{`\bcunt\b`, "contains strong profanity"},
	}

	inappropriatePatterns = make([]inappropriateEntry, 0, len(entries))
	for _, e := range entries {
		re := regexp.MustCompile("(?i)" + e.pattern)
		inappropriatePatterns = append(inappropriatePatterns, inappropriateEntry{regex: re, reason: e.reason})
	}
}

// normalizeUsername applies common leet-speak substitutions to catch bypass attempts
func normalizeUsername(s string) string {
	replacer := strings.NewReplacer(
		"0", "o",
		"1", "i",
		"3", "e",
		"4", "a",
		"5", "s",
		"7", "t",
		"@", "a",
		"$", "s",
		"!", "i",
		"|", "l",
	)
	return replacer.Replace(s)
}
