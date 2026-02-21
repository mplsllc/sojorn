// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package worker

import (
	"context"
	"encoding/json"
	"log"
	"strings"
	"time"

	"ai-gateway/internal/ollama"
	"ai-gateway/internal/queue"
)

type JudgeWorker struct {
	q           *queue.Queue
	ollama      *ollama.Client
	concurrency int
}

func NewJudge(q *queue.Queue, oc *ollama.Client, concurrency int) *JudgeWorker {
	return &JudgeWorker{q: q, ollama: oc, concurrency: concurrency}
}

func (w *JudgeWorker) Run(ctx context.Context) {
	for i := 0; i < w.concurrency; i++ {
		go w.loop(ctx, i)
	}
	<-ctx.Done()
}

func (w *JudgeWorker) loop(ctx context.Context, workerID int) {
	log.Printf("[judge-worker-%d] started", workerID)
	for {
		select {
		case <-ctx.Done():
			log.Printf("[judge-worker-%d] shutting down", workerID)
			return
		default:
		}

		job, err := w.q.Dequeue(ctx, "judge", 5*time.Second)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			continue
		}

		log.Printf("[judge-worker-%d] processing job %s", workerID, job.ID)
		w.process(ctx, job)
	}
}

func (w *JudgeWorker) process(ctx context.Context, job *queue.Job) {
	job.Status = "running"
	w.q.UpdateJob(ctx, job)

	var req struct {
		Text    string         `json:"text"`
		Context map[string]any `json:"context,omitempty"`
	}
	if err := json.Unmarshal(job.Input, &req); err != nil {
		job.Status = "failed"
		job.Error = "invalid input: " + err.Error()
		w.q.UpdateJob(ctx, job)
		return
	}

	timeoutCtx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()

	result, err := w.judge(timeoutCtx, req.Text)
	if err != nil {
		job.Status = "failed"
		job.Error = err.Error()
		w.q.UpdateJob(ctx, job)
		log.Printf("[judge-worker] job %s failed: %v", job.ID, err)
		return
	}

	resultJSON, _ := json.Marshal(result)
	job.Status = "succeeded"
	job.Result = resultJSON
	w.q.UpdateJob(ctx, job)

	// Cache result
	if data, err := json.Marshal(result); err == nil {
		w.q.SetModCache(ctx, req.Text, data)
	}

	log.Printf("[judge-worker] job %s succeeded", job.ID)
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

var highSeverityCodes = map[string]bool{"S1": true, "S3": true, "S4": true, "S9": true}

func parseGuardOutput(raw string) map[string]any {
	content := strings.TrimSpace(raw)
	lower := strings.ToLower(content)

	if lower == "safe" || strings.HasPrefix(lower, "safe\n") || strings.HasPrefix(lower, "safe ") {
		return map[string]any{"allowed": true, "categories": []string{}, "severity": "low", "reason": ""}
	}

	categories := []string{}
	codes := []string{}
	severity := "medium"

	lines := strings.Split(content, "\n")
	if len(lines) > 1 {
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

func (w *JudgeWorker) judge(ctx context.Context, text string) (map[string]any, error) {
	resp, err := w.ollama.Chat(ctx, &ollama.ChatRequest{
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
