package services

import (
	"encoding/json"

	altcha "github.com/altcha-org/altcha-lib-go"
)

type AltchaService struct {
	secretKey string
}

type AltchaResponse struct {
	Verified bool   `json:"verified"`
	Error    string `json:"error,omitempty"`
}

func NewAltchaService(secretKey string) *AltchaService {
	return &AltchaService{
		secretKey: secretKey,
	}
}

// VerifyToken validates an ALTCHA token using the official library
func (s *AltchaService) VerifyToken(token, remoteIP string) (*AltchaResponse, error) {
	// Allow bypass token for development
	if token == "BYPASS_DEV_MODE" {
		return &AltchaResponse{Verified: true}, nil
	}

	if s.secretKey == "" {
		// If no secret key is configured, skip verification (for development)
		return &AltchaResponse{Verified: true}, nil
	}

	// Verify using official ALTCHA library
	ok, err := altcha.VerifySolution(token, s.secretKey, true)
	if err != nil {
		return &AltchaResponse{Verified: false, Error: err.Error()}, nil
	}

	if !ok {
		return &AltchaResponse{Verified: false, Error: "Invalid solution"}, nil
	}

	return &AltchaResponse{Verified: true}, nil
}

// GenerateChallenge creates a new ALTCHA challenge using the official library
func (s *AltchaService) GenerateChallenge() (map[string]interface{}, error) {
	// Generate challenge using official ALTCHA library
	options := altcha.ChallengeOptions{
		Algorithm:  altcha.AlgorithmSHA256,
		MaxNumber:  100000,
		SaltLength: 12,
		HMACKey:    s.secretKey,
	}

	challenge, err := altcha.CreateChallenge(options)
	if err != nil {
		return nil, err
	}

	// Convert to map for JSON response
	var result map[string]interface{}
	data, err := json.Marshal(challenge)
	if err != nil {
		return nil, err
	}

	if err := json.Unmarshal(data, &result); err != nil {
		return nil, err
	}

	return result, nil
}

// GetErrorMessage returns a user-friendly error message
func (s *AltchaService) GetErrorMessage(error string) string {
	errorMessages := map[string]string{
		"Invalid token format":             "Invalid security verification format",
		"Invalid signature":                "Security verification failed",
		"Challenge expired":                "Security verification expired",
		"Invalid solution":                 "Security verification failed",
		"ALTCHA secret key not configured": "Server configuration error",
	}

	if msg, exists := errorMessages[error]; exists {
		return msg
	}
	return "Security verification failed"
}
