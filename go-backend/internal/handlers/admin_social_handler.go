// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/gin-gonic/gin"
)

// SocialMediaItem represents a single piece of content fetched from a social platform.
type SocialMediaItem struct {
	ID           string `json:"id"`
	Title        string `json:"title"`
	Description  string `json:"description"`
	URL          string `json:"url"`
	ThumbnailURL string `json:"thumbnail_url"`
	MediaType    string `json:"media_type"` // video, image
	Duration     int    `json:"duration"`   // seconds
	UploadDate   string `json:"upload_date"`
	ViewCount    int    `json:"view_count"`
	LikeCount    int    `json:"like_count"`
	Platform     string `json:"platform"`
}

// FetchSocialContent uses yt-dlp to list public content from a social media profile.
func (h *AdminHandler) FetchSocialContent(c *gin.Context) {
	var req struct {
		ProfileURL string `json:"profile_url" binding:"required"`
		Limit      int    `json:"limit"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Limit <= 0 || req.Limit > 50 {
		req.Limit = 20
	}

	// Detect platform from URL
	platform := detectPlatform(req.ProfileURL)
	if platform == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Unsupported platform. Supported: YouTube, TikTok, Facebook, Instagram"})
		return
	}

	// Check yt-dlp is available
	if _, err := exec.LookPath("yt-dlp"); err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": "yt-dlp is not installed on the server. Install with: sudo pip install yt-dlp",
		})
		return
	}

	// Use yt-dlp to dump JSON metadata (no download)
	args := []string{
		"--flat-playlist",
		"--dump-json",
		"--no-warnings",
		"--no-download",
		"--playlist-end", fmt.Sprintf("%d", req.Limit),
	}

	// Platform-specific flags
	switch platform {
	case "youtube":
		args = append(args, "--extractor-args", "youtube:player_skip=webpage")
	case "tiktok":
		args = append(args, "--cookies-from-browser", "none")
	case "facebook":
		// Facebook may require different extraction strategy
		args = append(args, "--cookies-from-browser", "none")
	}

	args = append(args, req.ProfileURL)

	ctx := c.Request.Context()
	cmd := exec.CommandContext(ctx, "yt-dlp", args...)

	done := make(chan error, 1)
	var output []byte
	var cmdErr error

	go func() {
		output, cmdErr = cmd.CombinedOutput()
		done <- cmdErr
	}()

	select {
	case <-time.After(90 * time.Second):
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
		c.JSON(http.StatusGatewayTimeout, gin.H{"error": "Fetching timed out after 90 seconds"})
		return
	case <-done:
	}

	if cmdErr != nil {
		errMsg := string(output)
		if len(errMsg) > 500 {
			errMsg = errMsg[:500]
		}
		c.JSON(http.StatusBadGateway, gin.H{
			"error":   "Failed to fetch content from platform",
			"details": strings.TrimSpace(errMsg),
		})
		return
	}

	// Parse JSONL output (one JSON object per line)
	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	items := make([]SocialMediaItem, 0, len(lines))

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		var entry map[string]any
		if err := json.Unmarshal([]byte(line), &entry); err != nil {
			continue
		}

		item := SocialMediaItem{
			ID:       getString(entry, "id"),
			Title:    getString(entry, "title"),
			URL:      getString(entry, "url"),
			Platform: platform,
		}

		// Description
		if desc := getString(entry, "description"); desc != "" {
			item.Description = desc
		}

		// Thumbnail
		if thumb := getString(entry, "thumbnail"); thumb != "" {
			item.ThumbnailURL = thumb
		}
		if item.ThumbnailURL == "" {
			// Try thumbnails array
			if thumbs, ok := entry["thumbnails"].([]any); ok && len(thumbs) > 0 {
				if last, ok := thumbs[len(thumbs)-1].(map[string]any); ok {
					item.ThumbnailURL = getString(last, "url")
				}
			}
		}

		// Duration
		if dur, ok := entry["duration"].(float64); ok {
			item.Duration = int(dur)
		}

		// Upload date
		if d := getString(entry, "upload_date"); d != "" {
			item.UploadDate = d
		}

		// Counts
		if vc, ok := entry["view_count"].(float64); ok {
			item.ViewCount = int(vc)
		}
		if lc, ok := entry["like_count"].(float64); ok {
			item.LikeCount = int(lc)
		}

		// Media type inference
		if item.Duration > 0 {
			item.MediaType = "video"
		} else {
			item.MediaType = "video" // most social content is video
		}

		// Build proper URL if missing
		if item.URL == "" {
			switch platform {
			case "youtube":
				item.URL = "https://www.youtube.com/watch?v=" + item.ID
			case "tiktok":
				item.URL = getString(entry, "webpage_url")
			}
		}

		items = append(items, item)
	}

	c.JSON(http.StatusOK, gin.H{
		"platform": platform,
		"items":    items,
		"total":    len(items),
	})
}

// DownloadSocialMedia downloads a single piece of content and uploads to R2.
func (h *AdminHandler) DownloadSocialMedia(c *gin.Context) {
	var req struct {
		URL       string `json:"url" binding:"required"`
		Platform  string `json:"platform"`
		MediaType string `json:"media_type"` // video or image
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if _, err := exec.LookPath("yt-dlp"); err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": "yt-dlp is not installed on the server",
		})
		return
	}

	// Create a unique temp directory per download to avoid collisions
	tmpDir := fmt.Sprintf("/tmp/sojorn-social-import/%d", time.Now().UnixNano())
	if err := os.MkdirAll(tmpDir, 0755); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create temp directory"})
		return
	}
	defer os.RemoveAll(tmpDir) // Clean up entire temp dir after we're done

	outputTemplate := tmpDir + "/%(id)s.%(ext)s"
	args := []string{
		"-o", outputTemplate,
		"--no-warnings",
		"--no-playlist",
		"-f", "mp4/best[ext=mp4]/best",
		"--max-filesize", "100M",
		"--print", "after_move:filepath", // Print the final filename to stdout
	}

	// Platform-specific workarounds
	if req.Platform == "tiktok" {
		args = append(args, "--cookies-from-browser", "none")
	}

	args = append(args, req.URL)

	ctx := c.Request.Context()
	cmd := exec.CommandContext(ctx, "yt-dlp", args...)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	done := make(chan error, 1)
	go func() { done <- cmd.Run() }()

	select {
	case <-time.After(120 * time.Second):
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
		c.JSON(http.StatusGatewayTimeout, gin.H{"error": "Download timed out after 120 seconds"})
		return
	case err := <-done:
		if err != nil {
			errMsg := stderr.String()
			if errMsg == "" {
				errMsg = stdout.String()
			}
			if len(errMsg) > 500 {
				errMsg = errMsg[:500]
			}
			c.JSON(http.StatusBadGateway, gin.H{
				"error":   "Failed to download content",
				"details": strings.TrimSpace(errMsg),
			})
			return
		}
	}

	// Get the file path from yt-dlp's --print output
	filePath := strings.TrimSpace(stdout.String())
	// --print may output multiple lines if there are metadata lines; take the last non-empty line
	if lines := strings.Split(filePath, "\n"); len(lines) > 0 {
		for i := len(lines) - 1; i >= 0; i-- {
			l := strings.TrimSpace(lines[i])
			if l != "" && strings.HasPrefix(l, tmpDir) {
				filePath = l
				break
			}
		}
	}

	if filePath == "" || !strings.HasPrefix(filePath, tmpDir) {
		// Fallback: scan the temp directory for any file
		entries, _ := os.ReadDir(tmpDir)
		for _, e := range entries {
			if !e.IsDir() {
				filePath = tmpDir + "/" + e.Name()
				break
			}
		}
	}

	if filePath == "" {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Download completed but no file found"})
		return
	}

	// Upload to R2 via S3 client
	if h.s3Client == nil {
		c.JSON(http.StatusOK, gin.H{
			"local_path": filePath,
			"message":    "Downloaded but R2/S3 not configured. File saved locally.",
		})
		return
	}

	fileName := filePath[strings.LastIndex(filePath, "/")+1:]
	bucket := h.videoBucket
	r2Key := fmt.Sprintf("imports/social/%d/%s", time.Now().Unix(), fileName)

	fileData, err := os.ReadFile(filePath)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read downloaded file"})
		return
	}

	contentType := "video/mp4"
	switch {
	case strings.HasSuffix(filePath, ".webm"):
		contentType = "video/webm"
	case strings.HasSuffix(filePath, ".mkv"):
		contentType = "video/x-matroska"
	case strings.HasSuffix(filePath, ".jpg"), strings.HasSuffix(filePath, ".jpeg"):
		contentType = "image/jpeg"
	case strings.HasSuffix(filePath, ".png"):
		contentType = "image/png"
	}

	_, err = h.s3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      &bucket,
		Key:         &r2Key,
		Body:        bytes.NewReader(fileData),
		ContentType: &contentType,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Downloaded but failed to upload to R2",
			"details": err.Error(),
		})
		return
	}

	mediaURL := fmt.Sprintf("https://%s/%s", h.vidDomain, r2Key)

	c.JSON(http.StatusOK, gin.H{
		"media_url": mediaURL,
		"r2_key":    r2Key,
		"size":      len(fileData),
	})
}

func detectPlatform(url string) string {
	lower := strings.ToLower(url)
	switch {
	case strings.Contains(lower, "youtube.com") || strings.Contains(lower, "youtu.be"):
		return "youtube"
	case strings.Contains(lower, "tiktok.com"):
		return "tiktok"
	case strings.Contains(lower, "facebook.com") || strings.Contains(lower, "fb.com") || strings.Contains(lower, "fb.watch"):
		return "facebook"
	case strings.Contains(lower, "instagram.com"):
		return "instagram"
	default:
		return ""
	}
}

func getString(m map[string]any, key string) string {
	if v, ok := m[key]; ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return ""
}
