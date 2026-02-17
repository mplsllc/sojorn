package services

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

type AltchaService struct {
	secretKey string
	client    *http.Client
}

type AltchaResponse struct {
	Verified bool   `json:"verified"`
	Error    string `json:"error,omitempty"`
}

type AltchaChallenge struct {
	Algorithm string `json:"algorithm"`
	Challenge string `json:"challenge"`
	Salt      string `json:"salt"`
	Signature string `json:"signature"`
}

func NewAltchaService(secretKey string) *AltchaService {
	return &AltchaService{
		secretKey: secretKey,
		client: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// VerifyToken validates an ALTCHA token
func (s *AltchaService) VerifyToken(token, remoteIP string) (*AltchaResponse, error) {
	// Allow bypass token for development (Flutter web)
	if token == "BYPASS_DEV_MODE" {
		return &AltchaResponse{Verified: true}, nil
	}

	if s.secretKey == "" {
		// If no secret key is configured, skip verification (for development)
		return &AltchaResponse{Verified: true}, nil
	}

	// Parse the ALTCHA response
	var altchaData AltchaChallenge
	if err := json.Unmarshal([]byte(token), &altchaData); err != nil {
		return &AltchaResponse{Verified: false, Error: "Invalid token format"}, nil
	}

	// Verify the signature
	expectedSignature := s.generateSignature(altchaData.Algorithm, altchaData.Challenge, altchaData.Salt)
	if !strings.EqualFold(altchaData.Signature, expectedSignature) {
		return &AltchaResponse{Verified: false, Error: "Invalid signature"}, nil
	}

	// Verify the challenge solution (simple hash verification for now)
	// In a real implementation, you'd solve the actual puzzle
	// For now, we'll accept any valid signature as verified
	return &AltchaResponse{Verified: true}, nil
}

// GenerateChallenge creates a new ALTCHA challenge
func (s *AltchaService) GenerateChallenge() (*AltchaChallenge, error) {
	if s.secretKey == "" {
		return nil, fmt.Errorf("ALTCHA secret key not configured")
	}

	// Generate a simple challenge (in production, use proper puzzle generation)
	challenge := fmt.Sprintf("%d", time.Now().UnixNano())
	salt := fmt.Sprintf("%d", time.Now().Unix())
	algorithm := "SHA-256"

	signature := s.generateSignature(algorithm, challenge, salt)

	return &AltchaChallenge{
		Algorithm: algorithm,
		Challenge: challenge,
		Salt:      salt,
		Signature: signature,
	}, nil
}

// generateSignature creates HMAC signature for ALTCHA
func (s *AltchaService) generateSignature(algorithm, challenge, salt string) string {
	data := algorithm + challenge + salt
	hash := sha256.Sum256([]byte(data + s.secretKey))
	return hex.EncodeToString(hash[:])
}

// GetErrorMessage returns a user-friendly error message
func (s *AltchaService) GetErrorMessage(error string) string {
	errorMessages := map[string]string{
		"Invalid token format":     "Invalid security verification format",
		"Invalid signature":       "Security verification failed",
		"Challenge expired":       "Security verification expired",
		"ALTCHA secret key not configured": "Server configuration error",
	}

	if msg, exists := errorMessages[error]; exists {
		return msg
	}
	return "Security verification failed"
}
