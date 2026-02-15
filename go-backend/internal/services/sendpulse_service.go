package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/rs/zerolog/log"
)

const (
	SendPulseWaitlistBookID = 568090
	SendPulseMembersBookID  = 568122
)

type SendPulseService struct {
	ClientID     string
	ClientSecret string
}

func NewSendPulseService(clientID, clientSecret string) *SendPulseService {
	return &SendPulseService{ClientID: clientID, ClientSecret: clientSecret}
}

func (s *SendPulseService) getToken() (string, error) {
	tokenBody, _ := json.Marshal(map[string]string{
		"grant_type":    "client_credentials",
		"client_id":     s.ClientID,
		"client_secret": s.ClientSecret,
	})
	resp, err := http.Post("https://api.sendpulse.com/oauth/access_token", "application/json", bytes.NewReader(tokenBody))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var data struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return "", err
	}
	if data.AccessToken == "" {
		return "", fmt.Errorf("empty access token")
	}
	return data.AccessToken, nil
}

func (s *SendPulseService) AddSubscriber(bookID int, email string) {
	if s.ClientID == "" || s.ClientSecret == "" {
		return
	}

	token, err := s.getToken()
	if err != nil {
		log.Error().Err(err).Msg("SendPulse: failed to get token")
		return
	}

	subBody, _ := json.Marshal(map[string]interface{}{
		"emails": []map[string]string{
			{"email": email},
		},
	})
	url := fmt.Sprintf("https://api.sendpulse.com/addressbooks/%d/emails", bookID)
	req, _ := http.NewRequest("POST", url, bytes.NewReader(subBody))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		log.Error().Err(err).Int("book_id", bookID).Msg("SendPulse: failed to add subscriber")
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		log.Error().Int("status", resp.StatusCode).Str("body", string(body)).Int("book_id", bookID).Msg("SendPulse: add subscriber failed")
		return
	}

	log.Info().Str("email", email).Int("book_id", bookID).Msg("SendPulse: subscriber added")
}

// AddToWaitlist adds an email to the Sojorn Waitlist
func (s *SendPulseService) AddToWaitlist(email string) {
	s.AddSubscriber(SendPulseWaitlistBookID, email)
}

// AddToMembers adds an email to the Sojorn Members list
func (s *SendPulseService) AddToMembers(email string) {
	s.AddSubscriber(SendPulseMembersBookID, email)
}
