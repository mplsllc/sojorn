// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
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
