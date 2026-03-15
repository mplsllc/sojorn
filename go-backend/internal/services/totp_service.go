// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package services

import (
	"crypto/rand"
	"encoding/base32"
	"fmt"
	"strings"
	"time"

	"github.com/pquerna/otp/totp"
	"golang.org/x/crypto/bcrypt"
)

// TOTPService handles TOTP secret generation, code validation, and recovery codes.
type TOTPService struct{}

func NewTOTPService() *TOTPService {
	return &TOTPService{}
}

// GenerateSecret creates a new TOTP secret for the given user email.
// Returns the base32-encoded secret and the otpauth:// provisioning URI.
func (s *TOTPService) GenerateSecret(email string) (secret string, provisioningURI string, err error) {
	key, err := totp.Generate(totp.GenerateOpts{
		Issuer:      "Sojorn",
		AccountName: email,
		Period:      30,
		Digits:      6,
	})
	if err != nil {
		return "", "", fmt.Errorf("generate TOTP key: %w", err)
	}
	return key.Secret(), key.URL(), nil
}

// ValidateCode checks a 6-digit TOTP code against the secret.
// Allows ±1 time step skew (30s window).
func (s *TOTPService) ValidateCode(secret, code string) bool {
	return totp.Validate(code, secret)
}

// ValidateCodeWithSkew checks a TOTP code with configurable time skew.
func (s *TOTPService) ValidateCodeWithSkew(secret, code string, skew uint) bool {
	valid, _ := totp.ValidateCustom(code, secret, time.Now().UTC(), totp.ValidateOpts{
		Period:    30,
		Skew:     skew,
		Digits:   6,
		Algorithm: 0, // SHA1 (default, most compatible)
	})
	return valid
}

const recoveryCodeCount = 8
const recoveryCodeLength = 10

// GenerateRecoveryCodes creates a set of random recovery codes.
func (s *TOTPService) GenerateRecoveryCodes() ([]string, error) {
	codes := make([]string, recoveryCodeCount)
	for i := range codes {
		b := make([]byte, recoveryCodeLength)
		if _, err := rand.Read(b); err != nil {
			return nil, fmt.Errorf("generate recovery code: %w", err)
		}
		raw := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(b)
		raw = strings.ToLower(raw[:recoveryCodeLength])
		// Format as xxxxx-xxxxx
		codes[i] = raw[:5] + "-" + raw[5:]
	}
	return codes, nil
}

// HashRecoveryCodes bcrypt-hashes each recovery code for safe storage.
func (s *TOTPService) HashRecoveryCodes(codes []string) ([]string, error) {
	hashed := make([]string, len(codes))
	for i, code := range codes {
		normalized := strings.ReplaceAll(code, "-", "")
		h, err := bcrypt.GenerateFromPassword([]byte(normalized), bcrypt.DefaultCost)
		if err != nil {
			return nil, fmt.Errorf("hash recovery code: %w", err)
		}
		hashed[i] = string(h)
	}
	return hashed, nil
}

// CheckRecoveryCode checks a plaintext code against a slice of hashed codes.
// Returns the index of the matched code, or -1 if none match.
func (s *TOTPService) CheckRecoveryCode(hashedCodes []string, code string) int {
	normalized := strings.ReplaceAll(strings.TrimSpace(code), "-", "")
	normalized = strings.ToLower(normalized)
	for i, h := range hashedCodes {
		if bcrypt.CompareHashAndPassword([]byte(h), []byte(normalized)) == nil {
			return i
		}
	}
	return -1
}
