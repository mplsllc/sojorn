// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package utils

import (
	"regexp"
	"strings"
)

var hashtagRegex = regexp.MustCompile(`#(\w+)`)

func ExtractHashtags(body string) []string {
	matches := hashtagRegex.FindAllStringSubmatch(body, -1)
	if len(matches) == 0 {
		return []string{}
	}

	tags := make([]string, 0, len(matches))
	seen := make(map[string]bool)

	for _, match := range matches {
		tag := strings.ToLower(match[1])
		if !seen[tag] {
			tags = append(tags, tag)
			seen[tag] = true
		}
	}

	return tags
}
