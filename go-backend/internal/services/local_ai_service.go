// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/rs/zerolog/log"
)

// LocalAIService communicates with the on-server AI Gateway (localhost:8099).
// It provides text moderation via llama-guard and content generation via qwen2.5.
// Runs alongside SightEngine — both engines are available simultaneously.
type LocalAIService struct {
	baseURL    string
	token      string
	httpClient *http.Client

	mu            sync.RWMutex
	circuitOpen   bool
	circuitUntil  time.Time
	circuitWindow time.Duration
}

// LocalAIModerationResult is the response from the local AI gateway /v1/moderate endpoint.
type LocalAIModerationResult struct {
	Allowed    bool     `json:"allowed"`
	Categories []string `json:"categories"`
	Severity   string   `json:"severity"`
	Reason     string   `json:"reason"`
	Cached     bool     `json:"cached"`
	Error      string   `json:"error,omitempty"`
}

// LocalAIJobResponse is returned when a job is submitted asynchronously.
type LocalAIJobResponse struct {
	JobID  string `json:"job_id"`
	Status string `json:"status"`
}

// LocalAIJob is the full job object returned when polling.
type LocalAIJob struct {
	ID        string          `json:"id"`
	Type      string          `json:"type"`
	CreatedAt time.Time       `json:"created_at"`
	Status    string          `json:"status"`
	Result    json.RawMessage `json:"result,omitempty"`
	Error     string          `json:"error,omitempty"`
}

// LocalAIHealthStatus is returned by the /readyz endpoint.
type LocalAIHealthStatus struct {
	Status        string `json:"status"`
	Redis         string `json:"redis"`
	Ollama        string `json:"ollama"`
	OllamaCircuit bool   `json:"ollama_circuit"`
	QueueWriter   int64  `json:"queue_writer"`
	QueueJudge    int64  `json:"queue_judge"`
}

func NewLocalAIService(baseURL, token string) *LocalAIService {
	if baseURL == "" {
		return nil
	}
	return &LocalAIService{
		baseURL: strings.TrimRight(baseURL, "/"),
		token:   token,
		httpClient: &http.Client{
			Timeout: 90 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        5,
				MaxIdleConnsPerHost: 5,
				IdleConnTimeout:     60 * time.Second,
			},
		},
		circuitWindow: 30 * time.Second,
	}
}

func (s *LocalAIService) isAvailable() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if s.circuitOpen && time.Now().Before(s.circuitUntil) {
		return false
	}
	return true
}

func (s *LocalAIService) tripCircuit() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.circuitOpen = true
	s.circuitUntil = time.Now().Add(s.circuitWindow)
	log.Warn().Msg("[local-ai] circuit breaker tripped")
}

func (s *LocalAIService) resetCircuit() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.circuitOpen {
		s.circuitOpen = false
		log.Info().Msg("[local-ai] circuit breaker reset")
	}
}

// ModerateText sends text to the local AI gateway for moderation.
// Returns nil result (not an error) if the service is unavailable — caller should fall through to SightEngine.
func (s *LocalAIService) ModerateText(ctx context.Context, text string) (*LocalAIModerationResult, error) {
	if !s.isAvailable() {
		return nil, fmt.Errorf("local_ai_unavailable: circuit breaker open")
	}

	body, _ := json.Marshal(map[string]string{"text": text})

	req, err := http.NewRequestWithContext(ctx, "POST", s.baseURL+"/v1/moderate", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("request error: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	if s.token != "" {
		req.Header.Set("X-Internal-Token", s.token)
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		s.tripCircuit()
		return nil, fmt.Errorf("local_ai_unavailable: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusTooManyRequests {
		return nil, fmt.Errorf("local_ai_rate_limited")
	}

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusAccepted {
		respBody, _ := io.ReadAll(resp.Body)
		s.tripCircuit()
		return nil, fmt.Errorf("local_ai error %d: %s", resp.StatusCode, string(respBody))
	}

	s.resetCircuit()

	// Async response (long text)
	if resp.StatusCode == http.StatusAccepted {
		var jobResp LocalAIJobResponse
		json.NewDecoder(resp.Body).Decode(&jobResp)
		log.Info().Str("job_id", jobResp.JobID).Msg("[local-ai] moderation queued async")
		// For async jobs, return allowed=true (fail open) — the job can be polled later
		return &LocalAIModerationResult{Allowed: true, Reason: "async_queued", Severity: "pending"}, nil
	}

	var result LocalAIModerationResult
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode error: %w", err)
	}

	return &result, nil
}

// SubmitGeneration submits a content generation job to the local AI gateway.
// Returns the job ID for polling.
func (s *LocalAIService) SubmitGeneration(ctx context.Context, task string, input map[string]any) (*LocalAIJobResponse, error) {
	if !s.isAvailable() {
		return nil, fmt.Errorf("local_ai_unavailable: circuit breaker open")
	}

	body, _ := json.Marshal(map[string]any{"task": task, "input": input})

	req, err := http.NewRequestWithContext(ctx, "POST", s.baseURL+"/v1/generate", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("request error: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	if s.token != "" {
		req.Header.Set("X-Internal-Token", s.token)
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		s.tripCircuit()
		return nil, fmt.Errorf("local_ai_unavailable: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusAccepted {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("local_ai generate error %d: %s", resp.StatusCode, string(respBody))
	}

	s.resetCircuit()

	var result LocalAIJobResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode error: %w", err)
	}

	return &result, nil
}

// GetJob polls a job status from the local AI gateway.
func (s *LocalAIService) GetJob(ctx context.Context, jobID string) (*LocalAIJob, error) {
	if !s.isAvailable() {
		return nil, fmt.Errorf("local_ai_unavailable: circuit breaker open")
	}

	req, err := http.NewRequestWithContext(ctx, "GET", s.baseURL+"/v1/jobs/"+jobID, nil)
	if err != nil {
		return nil, fmt.Errorf("request error: %w", err)
	}
	if s.token != "" {
		req.Header.Set("X-Internal-Token", s.token)
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("local_ai_unavailable: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("job not found")
	}

	var job LocalAIJob
	if err := json.NewDecoder(resp.Body).Decode(&job); err != nil {
		return nil, fmt.Errorf("decode error: %w", err)
	}

	return &job, nil
}

// Healthz checks if the local AI gateway is healthy.
func (s *LocalAIService) Healthz(ctx context.Context) (*LocalAIHealthStatus, error) {
	if s == nil {
		return nil, fmt.Errorf("local AI service not configured")
	}

	req, err := http.NewRequestWithContext(ctx, "GET", s.baseURL+"/readyz", nil)
	if err != nil {
		return nil, err
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var status LocalAIHealthStatus
	json.NewDecoder(resp.Body).Decode(&status)
	return &status, nil
}
