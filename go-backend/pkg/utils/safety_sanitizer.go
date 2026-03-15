// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package utils

import (
	"regexp"
	"strings"
)

// SafetySanitizer replaces specific agency/enforcement terms with neutral
// alternatives for App Store compliance and community safety.
// Zero Specificity: never use specific agency names.
var replacements = []struct {
	pattern     *regexp.Regexp
	replacement string
}{
	{regexp.MustCompile(`(?i)\b(ICE)\b`), "Official Presence"},
	{regexp.MustCompile(`(?i)\b(immigration\s*(and\s*)?customs?\s*enforcement)\b`), "Official Presence"},
	{regexp.MustCompile(`(?i)\b(border\s*patrol)\b`), "Official Presence"},
	{regexp.MustCompile(`(?i)\b(CBP|DEA|ATF|FBI)\b`), "Official Presence"},
	{regexp.MustCompile(`(?i)\b(police)\s*(raid|raids|raiding)\b`), "Official Activity"},
	{regexp.MustCompile(`(?i)\b(raid|raids|raiding)\b`), "Activity"},
	{regexp.MustCompile(`(?i)\b(cops?)\b`), "Officers"},
	{regexp.MustCompile(`(?i)\b(swat)\b`), "Task Force"},
	{regexp.MustCompile(`(?i)\b(sting\s*operation)\b`), "Operation"},
	{regexp.MustCompile(`(?i)\b(deportation|deporting|deported)\b`), "Enforcement Action"},
	{regexp.MustCompile(`(?i)\b(detention\s*center)\b`), "Processing Facility"},
	{regexp.MustCompile(`(?i)\b(warrant)\b`), "Authorization"},
}

// SanitizeBeaconText applies neutral-language replacements to user-submitted
// beacon text. Returns the sanitized string and whether any replacements were made.
func SanitizeBeaconText(input string) (string, bool) {
	result := input
	changed := false
	for _, r := range replacements {
		if r.pattern.MatchString(result) {
			result = r.pattern.ReplaceAllString(result, r.replacement)
			changed = true
		}
	}
	// Collapse multiple spaces that may result from replacements
	result = strings.Join(strings.Fields(result), " ")
	return result, changed
}
