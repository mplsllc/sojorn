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
		"--extractor-args", "youtube:player_skip=webpage",
	}

	// For TikTok, add cookies workaround
	if platform == "tiktok" {
		args = append(args, "--cookies-from-browser", "none")
	}

	args = append(args, req.ProfileURL)

	ctx := c.Request.Context()
	cmd := exec.CommandContext(ctx, "yt-dlp", args...)

	// Set a timeout
	done := make(chan error, 1)
	var output []byte
	var cmdErr error

	go func() {
		output, cmdErr = cmd.CombinedOutput()
		done <- cmdErr
	}()

	select {
	case <-time.After(60 * time.Second):
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
		c.JSON(http.StatusGatewayTimeout, gin.H{"error": "Fetching timed out after 60 seconds"})
		return
	case <-done:
	}

	if cmdErr != nil {
		errMsg := string(output)
		// Trim to a reasonable length
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

	// Download to a temp file then upload to R2
	tmpDir := "/tmp/sojorn-social-import"
	exec.Command("mkdir", "-p", tmpDir).Run()

	outputTemplate := tmpDir + "/%(id)s.%(ext)s"
	args := []string{
		"-o", outputTemplate,
		"--no-warnings",
		"--no-playlist",
		"-f", "mp4/best[ext=mp4]/best",
		"--max-filesize", "100M",
		req.URL,
	}

	ctx := c.Request.Context()
	cmd := exec.CommandContext(ctx, "yt-dlp", args...)

	outputBytes, err := cmd.CombinedOutput()
	if err != nil {
		errMsg := string(outputBytes)
		if len(errMsg) > 500 {
			errMsg = errMsg[:500]
		}
		c.JSON(http.StatusBadGateway, gin.H{
			"error":   "Failed to download content",
			"details": strings.TrimSpace(errMsg),
		})
		return
	}

	// Find the downloaded file
	findCmd := exec.Command("find", tmpDir, "-type", "f", "-newer", "/tmp", "-name", "*.mp4", "-o", "-name", "*.webm", "-o", "-name", "*.mkv")
	findOutput, _ := findCmd.Output()
	files := strings.Split(strings.TrimSpace(string(findOutput)), "\n")

	if len(files) == 0 || files[0] == "" {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Download completed but no file found"})
		return
	}

	filePath := strings.TrimSpace(files[0])

	// Upload to R2 via S3 client
	if h.s3Client == nil {
		c.JSON(http.StatusOK, gin.H{
			"local_path": filePath,
			"message":    "Downloaded but R2/S3 not configured. File saved locally.",
		})
		return
	}

	fileName := strings.TrimPrefix(filePath, tmpDir+"/")
	bucket := h.videoBucket
	r2Key := fmt.Sprintf("imports/social/%d/%s", time.Now().Unix(), fileName)

	fileData, err := os.ReadFile(filePath)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read downloaded file"})
		return
	}

	contentType := "video/mp4"
	if strings.HasSuffix(filePath, ".webm") {
		contentType = "video/webm"
	}

	_, err = h.s3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      &bucket,
		Key:         &r2Key,
		Body:        bytes.NewReader(fileData),
		ContentType: &contentType,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":      "Downloaded but failed to upload to R2",
			"local_path": filePath,
		})
		return
	}

	mediaURL := fmt.Sprintf("https://%s/%s", h.vidDomain, r2Key)

	// Clean up temp file
	exec.Command("rm", "-f", filePath).Run()

	c.JSON(http.StatusOK, gin.H{
		"media_url": mediaURL,
		"r2_key":    r2Key,
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
