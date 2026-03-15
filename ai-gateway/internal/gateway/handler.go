// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package gateway

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"ai-gateway/internal/config"
	"ai-gateway/internal/ollama"
	"ai-gateway/internal/queue"

	"github.com/google/uuid"
)

type Handler struct {
	cfg    *config.Config
	q      *queue.Queue
	ollama *ollama.Client
}

func New(cfg *config.Config, q *queue.Queue, oc *ollama.Client) *Handler {
	return &Handler{cfg: cfg, q: q, ollama: oc}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path
	switch {
	case path == "/healthz" && r.Method == "GET":
		h.healthz(w, r)
	case path == "/readyz" && r.Method == "GET":
		h.readyz(w, r)
	case path == "/v1/moderate" && r.Method == "POST":
		h.authMiddleware(h.moderate)(w, r)
	case path == "/v1/generate" && r.Method == "POST":
		h.authMiddleware(h.generate)(w, r)
	case strings.HasPrefix(path, "/v1/jobs/") && r.Method == "GET":
		h.authMiddleware(h.getJob)(w, r)
	default:
		jsonError(w, http.StatusNotFound, "not found")
	}
}

func (h *Handler) authMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if h.cfg.InternalToken == "" {
			next(w, r)
			return
		}
		token := r.Header.Get("X-Internal-Token")
		if token != h.cfg.InternalToken {
			jsonError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		next(w, r)
	}
}

func (h *Handler) healthz(w http.ResponseWriter, _ *http.Request) {
	jsonOK(w, map[string]any{"status": "ok", "time": time.Now().UTC()})
}

func (h *Handler) readyz(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	status := map[string]any{"time": time.Now().UTC()}
	ready := true

	if err := h.q.Ping(ctx); err != nil {
		status["redis"] = "down"
		ready = false
	} else {
		status["redis"] = "ok"
	}

	if err := h.ollama.Healthz(ctx); err != nil {
		status["ollama"] = "down"
	} else {
		status["ollama"] = "ok"
	}

	status["ollama_circuit"] = h.ollama.IsAvailable()

	writerLen, _ := h.q.QueueLen(ctx, "writer")
	judgeLen, _ := h.q.QueueLen(ctx, "judge")
	status["queue_writer"] = writerLen
	status["queue_judge"] = judgeLen

	if ready {
		status["status"] = "ready"
		jsonOK(w, status)
	} else {
		status["status"] = "not_ready"
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(status)
	}
}

type ModerateRequest struct {
	Text    string         `json:"text"`
	Context map[string]any `json:"context,omitempty"`
}

func (h *Handler) moderate(w http.ResponseWriter, r *http.Request) {
	if h.cfg.AIDisabled {
		jsonOK(w, map[string]any{"allowed": true, "reason": "ai_disabled", "cached": false})
		return
	}

	var req ModerateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if req.Text == "" {
		jsonError(w, http.StatusBadRequest, "text required")
		return
	}

	// Rate limit
	ok, err := h.q.CheckRate(r.Context(), "global", "moderate", h.cfg.ModerateRateLimit)
	if err != nil || !ok {
		jsonError(w, http.StatusTooManyRequests, "rate limit exceeded")
		return
	}

	// Check cache
	if cached, err := h.q.GetModCache(r.Context(), req.Text); err == nil {
		var result map[string]any
		if json.Unmarshal(cached, &result) == nil {
			result["cached"] = true
			jsonOK(w, result)
			return
		}
	}

	// Synchronous fast path for short texts
	if len(req.Text) <= h.cfg.SyncMaxChars && h.ollama.IsAvailable() {
		result, err := h.runJudge(r.Context(), req.Text)
		if err != nil {
			log.Printf("[moderate] sync judge error: %v", err)
			// Fail open
			jsonOK(w, map[string]any{"allowed": true, "reason": "judge_error", "error": err.Error()})
			return
		}
		if data, err := json.Marshal(result); err == nil {
			h.q.SetModCache(r.Context(), req.Text, data)
		}
		result["cached"] = false
		jsonOK(w, result)
		return
	}

	// Async path for long texts
	jobID := uuid.New().String()
	input, _ := json.Marshal(req)
	job := &queue.Job{
		ID:        jobID,
		Type:      "judge",
		CreatedAt: time.Now().UTC(),
		Input:     input,
		Status:    "queued",
	}
	if err := h.q.Enqueue(r.Context(), job); err != nil {
		jsonError(w, http.StatusInternalServerError, "queue error")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	json.NewEncoder(w).Encode(map[string]any{"job_id": jobID, "status": "queued"})
}

// guardCategories maps LLaMA Guard 3 S-codes to human-readable category names.
var guardCategories = map[string]string{
	"S1":  "violent_crimes",
	"S2":  "non_violent_crimes",
	"S3":  "sex_related_crimes",
	"S4":  "child_sexual_exploitation",
	"S5":  "defamation",
	"S6":  "specialized_advice",
	"S7":  "privacy",
	"S8":  "intellectual_property",
	"S9":  "indiscriminate_weapons",
	"S10": "hate",
	"S11": "suicide_self_harm",
	"S12": "sexual_content",
	"S13": "elections",
	"S14": "code_interpreter_abuse",
}

// highSeverityCodes are categories that should always be severity "high".
var highSeverityCodes = map[string]bool{"S1": true, "S3": true, "S4": true, "S9": true}

// parseGuardOutput parses LLaMA Guard 3's native output format.
// Safe output:   "safe"
// Unsafe output: "unsafe\nS1,S4" or "unsafe\nS1"
func parseGuardOutput(raw string) map[string]any {
	content := strings.TrimSpace(raw)
	lower := strings.ToLower(content)

	if lower == "safe" || strings.HasPrefix(lower, "safe\n") || strings.HasPrefix(lower, "safe ") {
		return map[string]any{"allowed": true, "categories": []string{}, "severity": "low", "reason": ""}
	}

	// Parse "unsafe\nS1,S2,..."
	categories := []string{}
	codes := []string{}
	severity := "medium"

	lines := strings.Split(content, "\n")
	if len(lines) > 1 {
		// Second line has comma-separated S-codes
		parts := strings.Split(strings.TrimSpace(lines[1]), ",")
		for _, p := range parts {
			code := strings.TrimSpace(p)
			if code == "" {
				continue
			}
			codes = append(codes, code)
			if name, ok := guardCategories[code]; ok {
				categories = append(categories, name)
			} else {
				categories = append(categories, code)
			}
			if highSeverityCodes[code] {
				severity = "high"
			}
		}
	}

	if len(categories) == 0 {
		categories = []string{"policy_violation"}
	}

	return map[string]any{
		"allowed":    false,
		"categories": categories,
		"codes":      codes,
		"severity":   severity,
		"reason":     strings.Join(categories, ", "),
	}
}

func (h *Handler) runJudge(ctx context.Context, text string) (map[string]any, error) {
	resp, err := h.ollama.Chat(ctx, &ollama.ChatRequest{
		Model: "llama-guard3:1b",
		Messages: []ollama.ChatMessage{
			{Role: "user", Content: text},
		},
		Stream: false,
		Options: &ollama.ModelOptions{
			Temperature: 0.0,
			NumPredict:  64,
		},
	})
	if err != nil {
		return nil, err
	}

	return parseGuardOutput(resp.Message.Content), nil
}

type GenerateRequest struct {
	Task  string         `json:"task"`
	Input map[string]any `json:"input"`
}

func (h *Handler) generate(w http.ResponseWriter, r *http.Request) {
	if h.cfg.AIDisabled {
		jsonError(w, http.StatusServiceUnavailable, "ai_disabled")
		return
	}

	var req GenerateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if req.Task == "" {
		jsonError(w, http.StatusBadRequest, "task required")
		return
	}

	ok, err := h.q.CheckRate(r.Context(), "global", "generate", h.cfg.GenerateRateLimit)
	if err != nil || !ok {
		jsonError(w, http.StatusTooManyRequests, "rate limit exceeded")
		return
	}

	jobID := uuid.New().String()
	input, _ := json.Marshal(req)
	job := &queue.Job{
		ID:        jobID,
		Type:      "writer",
		CreatedAt: time.Now().UTC(),
		Input:     input,
		Status:    "queued",
	}
	if err := h.q.Enqueue(r.Context(), job); err != nil {
		jsonError(w, http.StatusInternalServerError, "queue error")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	json.NewEncoder(w).Encode(map[string]any{"job_id": jobID, "status": "queued"})
}

func (h *Handler) getJob(w http.ResponseWriter, r *http.Request) {
	jobID := strings.TrimPrefix(r.URL.Path, "/v1/jobs/")
	if jobID == "" {
		jsonError(w, http.StatusBadRequest, "job_id required")
		return
	}
	job, err := h.q.GetJob(r.Context(), jobID)
	if err != nil {
		jsonError(w, http.StatusNotFound, "job not found")
		return
	}
	jsonOK(w, job)
}

func jsonOK(w http.ResponseWriter, data any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(data)
}

func jsonError(w http.ResponseWriter, code int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]string{"error": msg})
}

func init() {
	// Ensure fmt is used (prevent import error in case)
	_ = fmt.Sprintf
}
