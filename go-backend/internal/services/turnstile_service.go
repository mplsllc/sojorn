package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

type TurnstileService struct {
	secretKey string
	client    *http.Client
}

type TurnstileResponse struct {
	Success     bool     `json:"success"`
	ErrorCodes  []string `json:"error-codes,omitempty"`
	ChallengeTS string   `json:"challenge_ts,omitempty"`
	Hostname    string   `json:"hostname,omitempty"`
	Action      string   `json:"action,omitempty"`
	Cdata       string   `json:"cdata,omitempty"`
}

func NewTurnstileService(secretKey string) *TurnstileService {
	return &TurnstileService{
		secretKey: secretKey,
		client: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// VerifyToken validates a Turnstile token with Cloudflare
func (s *TurnstileService) VerifyToken(token, remoteIP string) (*TurnstileResponse, error) {
	if s.secretKey == "" {
		// If no secret key is configured, skip verification (for development)
		return &TurnstileResponse{Success: true}, nil
	}

	// Prepare the request data
	data := fmt.Sprintf(
		"secret=%s&response=%s",
		s.secretKey,
		token,
	)
	
	if remoteIP != "" {
		data += fmt.Sprintf("&remoteip=%s", remoteIP)
	}

	// Make the request to Cloudflare
	resp, err := s.client.Post(
		"https://challenges.cloudflare.com/turnstile/v0/siteverify",
		"application/x-www-form-urlencoded",
		bytes.NewBufferString(data),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to verify turnstile token: %w", err)
	}
	defer resp.Body.Close()

	// Read the response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read turnstile response: %w", err)
	}

	// Parse the response
	var result TurnstileResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("failed to parse turnstile response: %w", err)
	}

	return &result, nil
}

// GetErrorMessage returns a user-friendly error message for error codes
func (s *TurnstileService) GetErrorMessage(errorCodes []string) string {
	errorMessages := map[string]string{
		"missing-input-secret":     "Server configuration error",
		"invalid-input-secret":     "Server configuration error", 
		"missing-input-response":    "Please complete the security check",
		"invalid-input-response":    "Security check failed, please try again",
		"bad-request":               "Invalid request format",
		"timeout-or-duplicate":      "Security check expired, please try again",
		"internal-error":            "Verification service unavailable",
	}

	for _, code := range errorCodes {
		if msg, exists := errorMessages[code]; exists {
			return msg
		}
	}
	return "Security verification failed"
}
