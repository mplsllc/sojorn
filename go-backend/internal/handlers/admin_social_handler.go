// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package handlers

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog/log"
)

const socialCookiesDir = "/opt/sojorn/data/social-cookies"

// cookiesPathForPlatform returns the path to the cookies file for a given platform.
func cookiesPathForPlatform(platform string) string {
	return filepath.Join(socialCookiesDir, platform+"_cookies.txt")
}

// SocialCookieStatus represents the status of cookies for a platform.
type SocialCookieStatus struct {
	Platform  string  `json:"platform"`
	HasCookie bool    `json:"has_cookie"`
	FileName  string  `json:"file_name,omitempty"`
	FileSize  int64   `json:"file_size,omitempty"`
	UpdatedAt *string `json:"updated_at,omitempty"`
}

// ListSocialCookies returns which platforms have cookies configured.
func (h *AdminHandler) ListSocialCookies(c *gin.Context) {
	platforms := []string{"youtube", "tiktok", "facebook", "instagram"}
	statuses := make([]SocialCookieStatus, 0, len(platforms))

	for _, p := range platforms {
		status := SocialCookieStatus{Platform: p}
		path := cookiesPathForPlatform(p)
		if info, err := os.Stat(path); err == nil {
			status.HasCookie = true
			status.FileName = info.Name()
			status.FileSize = info.Size()
			modTime := info.ModTime().Format(time.RFC3339)
			status.UpdatedAt = &modTime
		}
		statuses = append(statuses, status)
	}

	c.JSON(http.StatusOK, gin.H{"cookies": statuses})
}

// UploadSocialCookies accepts a cookies.txt file upload for a specific platform.
func (h *AdminHandler) UploadSocialCookies(c *gin.Context) {
	platform := c.Param("platform")
	validPlatforms := map[string]bool{"youtube": true, "tiktok": true, "facebook": true, "instagram": true}
	if !validPlatforms[platform] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid platform. Supported: youtube, tiktok, facebook, instagram"})
		return
	}

	file, header, err := c.Request.FormFile("cookies")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No cookies file provided. Upload a Netscape-format cookies.txt file."})
		return
	}
	defer file.Close()

	// Limit to 1MB
	if header.Size > 1<<20 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cookies file too large (max 1MB)"})
		return
	}

	// Read and validate it looks like a Netscape cookies file
	data, err := io.ReadAll(io.LimitReader(file, 1<<20+1))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read uploaded file"})
		return
	}

	if !isValidCookiesFile(data) {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid cookies file format. Must be Netscape/Mozilla cookies.txt format. Use a browser extension like 'Get cookies.txt LOCALLY' to export.",
		})
		return
	}

	// Ensure directory exists
	if err := os.MkdirAll(socialCookiesDir, 0700); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create cookies directory"})
		return
	}

	path := cookiesPathForPlatform(platform)
	if err := os.WriteFile(path, data, 0600); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save cookies file"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":  fmt.Sprintf("Cookies uploaded for %s", platform),
		"platform": platform,
		"size":     len(data),
	})
}

// DeleteSocialCookies removes the cookies file for a platform.
func (h *AdminHandler) DeleteSocialCookies(c *gin.Context) {
	platform := c.Param("platform")
	path := cookiesPathForPlatform(platform)

	if _, err := os.Stat(path); os.IsNotExist(err) {
		c.JSON(http.StatusNotFound, gin.H{"error": fmt.Sprintf("No cookies file found for %s", platform)})
		return
	}

	if err := os.Remove(path); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete cookies file"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": fmt.Sprintf("Cookies removed for %s", platform)})
}

// TestSocialCookies tests whether the stored cookies for a platform are valid by running yt-dlp.
func (h *AdminHandler) TestSocialCookies(c *gin.Context) {
	platform := c.Param("platform")
	path := cookiesPathForPlatform(platform)

	if _, err := os.Stat(path); os.IsNotExist(err) {
		c.JSON(http.StatusNotFound, gin.H{"error": fmt.Sprintf("No cookies file found for %s", platform)})
		return
	}

	if _, err := exec.LookPath("yt-dlp"); err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "yt-dlp is not installed"})
		return
	}

	// Pick a test URL per platform
	var testURL string
	switch platform {
	case "facebook":
		testURL = "https://www.facebook.com/Meta"
	case "instagram":
		testURL = "https://www.instagram.com/instagram/"
	case "youtube":
		testURL = "https://www.youtube.com/@YouTube"
	case "tiktok":
		testURL = "https://www.tiktok.com/@tiktok"
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "Unknown platform"})
		return
	}

	args := []string{
		"--flat-playlist",
		"--dump-json",
		"--no-warnings",
		"--no-download",
		"--playlist-end", "1",
		"--cookies", path,
		testURL,
	}

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
	case <-time.After(30 * time.Second):
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
		c.JSON(http.StatusGatewayTimeout, gin.H{
			"valid": false,
			"error": "Test timed out",
		})
		return
	case <-done:
	}

	if cmdErr != nil {
		errMsg := string(output)
		if len(errMsg) > 500 {
			errMsg = errMsg[:500]
		}
		log.Error().Str("platform", platform).Str("output", strings.TrimSpace(errMsg)).Msg("Social cookie test failed")
		c.JSON(http.StatusOK, gin.H{
			"valid":    false,
			"platform": platform,
			"error":    "Cookies appear invalid or expired",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"valid":    true,
		"platform": platform,
		"message":  fmt.Sprintf("Cookies for %s are valid — successfully fetched content", platform),
	})
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// isValidCookiesFile does a basic check that the data looks like a Netscape cookies.txt file.
func isValidCookiesFile(data []byte) bool {
	scanner := bufio.NewScanner(bytes.NewReader(data))
	lineCount := 0
	cookieLines := 0
	for scanner.Scan() && lineCount < 50 {
		line := strings.TrimSpace(scanner.Text())
		lineCount++
		// Skip comments and empty lines
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		// Netscape cookies have tab-separated fields: domain, flag, path, secure, expiration, name, value
		fields := strings.Split(line, "\t")
		if len(fields) >= 6 {
			cookieLines++
		}
	}
	return cookieLines > 0
}

// SocialMediaItem represents a single piece of content fetched from a social platform.
type SocialMediaItem struct {
	ID           string  `json:"id"`
	Title        string  `json:"title"`
	Description  string  `json:"description"`
	URL          string  `json:"url"`
	ThumbnailURL string  `json:"thumbnail_url"`
	MediaType    string  `json:"media_type"` // video, image
	Duration     int     `json:"duration"`   // seconds
	UploadDate   string  `json:"upload_date"`
	ViewCount    int     `json:"view_count"`
	LikeCount    int     `json:"like_count"`
	Platform     string  `json:"platform"`
	Imported     bool    `json:"imported"`
	ImportedAt   *string `json:"imported_at,omitempty"`
	ImportedAsID *string `json:"imported_as_id,omitempty"`
}

// FetchSocialContent uses yt-dlp to list public content from a social media profile.
func (h *AdminHandler) FetchSocialContent(c *gin.Context) {
	var req struct {
		ProfileURL string `json:"profile_url" binding:"required"`
		Limit      int    `json:"limit"`
		DateAfter  string `json:"date_after"`  // YYYY-MM-DD
		DateBefore string `json:"date_before"` // YYYY-MM-DD
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Limit <= 0 {
		req.Limit = 20
	}
	if req.Limit > 500 {
		req.Limit = 500
	}

	// Detect platform from URL
	platform := detectPlatform(req.ProfileURL)
	if platform == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Unsupported platform. Supported: YouTube, TikTok"})
		return
	}

	// Facebook and Instagram require login cookies
	cookiesPath := cookiesPathForPlatform(platform)
	hasCookies := false
	if _, err := os.Stat(cookiesPath); err == nil {
		hasCookies = true
	}
	if (platform == "facebook" || platform == "instagram") && !hasCookies {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   fmt.Sprintf("%s requires login cookies. Upload a cookies.txt file via the cookie management panel first.", platform),
			"need_cookies": true,
		})
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

	// Date filtering is done server-side after parsing (--dateafter/--datebefore
	// don't work with --flat-playlist mode)

	// Inject cookies if available
	if hasCookies {
		args = append(args, "--cookies", cookiesPath)
	}

	// Platform-specific flags
	switch platform {
	case "youtube":
		args = append(args, "--extractor-args", "youtube:player_skip=webpage")
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
	case <-time.After(150 * time.Second):
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
		log.Error().Str("output", strings.TrimSpace(errMsg)).Msg("Failed to fetch social content")
		c.JSON(http.StatusBadGateway, gin.H{
			"error": "Failed to fetch content from platform",
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

	// Server-side date filtering (upload_date is YYYYMMDD from yt-dlp)
	if req.DateAfter != "" || req.DateBefore != "" {
		dateAfter := strings.ReplaceAll(req.DateAfter, "-", "")
		dateBefore := strings.ReplaceAll(req.DateBefore, "-", "")
		filtered := make([]SocialMediaItem, 0, len(items))
		for _, item := range items {
			d := strings.ReplaceAll(item.UploadDate, "-", "")
			if d == "" {
				filtered = append(filtered, item) // keep items without dates
				continue
			}
			if dateAfter != "" && d < dateAfter {
				continue
			}
			if dateBefore != "" && d > dateBefore {
				continue
			}
			filtered = append(filtered, item)
		}
		items = filtered
	}

	// Check which items are already imported
	if len(items) > 0 {
		extIDs := make([]string, len(items))
		for i, item := range items {
			extIDs[i] = item.ID
		}

		rows, err := h.pool.Query(ctx,
			`SELECT external_id, post_id, created_at FROM social_imports
			 WHERE platform = $1 AND external_id = ANY($2)`,
			platform, extIDs)
		if err == nil {
			defer rows.Close()
			imported := make(map[string]struct {
				postID    string
				createdAt string
			})
			for rows.Next() {
				var extID, postID string
				var createdAt time.Time
				if err := rows.Scan(&extID, &postID, &createdAt); err == nil {
					imported[extID] = struct {
						postID    string
						createdAt string
					}{postID, createdAt.Format(time.RFC3339)}
				}
			}
			for i := range items {
				if imp, ok := imported[items[i].ID]; ok {
					items[i].Imported = true
					items[i].ImportedAt = &imp.createdAt
					items[i].ImportedAsID = &imp.postID
				}
			}
		}
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
		URL          string `json:"url" binding:"required"`
		Platform     string `json:"platform"`
		MediaType    string `json:"media_type"`    // video or image
		ThumbnailURL string `json:"thumbnail_url"` // optional: mirror to R2
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

	// Detect platform for cookie injection
	dlPlatform := req.Platform
	if dlPlatform == "" {
		dlPlatform = detectPlatform(req.URL)
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

	// Inject cookies if available for this platform
	if dlPlatform != "" {
		if cp := cookiesPathForPlatform(dlPlatform); fileExists(cp) {
			args = append(args, "--cookies", cp)
		}
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
			log.Error().Str("output", strings.TrimSpace(errMsg)).Msg("Failed to download social content")
			c.JSON(http.StatusBadGateway, gin.H{
				"error": "Failed to download content",
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
		log.Error().Err(err).Msg("Failed to upload social content to R2")
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Downloaded but failed to upload to R2",
		})
		return
	}

	mediaURL := fmt.Sprintf("https://%s/%s", h.vidDomain, r2Key)

	// Mirror thumbnail to R2 so we never store third-party CDN URLs in the DB.
	thumbURL := req.ThumbnailURL
	if thumbURL != "" && !isOurDomain(thumbURL) {
		if r2Thumb, err := h.mirrorToR2(c.Request.Context(), thumbURL, "imports/thumbs"); err == nil {
			thumbURL = r2Thumb
		} else {
			log.Warn().Err(err).Str("url", thumbURL).Msg("[SocialImport] thumbnail mirror failed — using original")
		}
	}

	resp := gin.H{
		"media_url": mediaURL,
		"r2_key":    r2Key,
		"size":      len(fileData),
	}
	if thumbURL != "" {
		resp["thumbnail_url"] = thumbURL
	}
	c.JSON(http.StatusOK, resp)
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
