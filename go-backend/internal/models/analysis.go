// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package models

type ToneCheckRequest struct {
	Text     string  `json:"text"`
	ImageURL *string `json:"image_url,omitempty"`
}

type ToneCheckResult struct {
	Flagged  bool     `json:"flagged"`
	Category *string  `json:"category"`
	Flags    []string `json:"flags"`
	Reason   string   `json:"reason"`
}
