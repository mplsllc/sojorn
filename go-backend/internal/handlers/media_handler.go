package handlers

import (
	"bytes"
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
	"github.com/google/uuid"
	"github.com/rs/zerolog/log"
)

// MediaHandler uploads media to Cloudflare R2. If s3Client is provided, it uses
// the S3-compatible API. Otherwise, it falls back to Cloudflare R2 HTTP API
// using account ID + API token from the config.
type MediaHandler struct {
	s3Client     *s3.Client
	useS3        bool
	accountID    string
	apiToken     string
	bucket       string
	videoBucket  string
	publicDomain string
	videoDomain  string
}

func NewMediaHandler(s3Client *s3.Client, accountID string, apiToken string, bucket string, videoBucket string, publicDomain string, videoDomain string) *MediaHandler {
	return &MediaHandler{
		s3Client:     s3Client,
		useS3:        s3Client != nil,
		accountID:    accountID,
		apiToken:     apiToken,
		bucket:       bucket,
		videoBucket:  videoBucket,
		publicDomain: publicDomain,
		videoDomain:  videoDomain,
	}
}

func (h *MediaHandler) Upload(c *gin.Context) {
	fileHeader, err := c.FormFile("media")
	if err != nil {
		fileHeader, err = c.FormFile("image")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "No media file found"})
			return
		}
	}

	mediaType := c.PostForm("type")
	if mediaType == "" {
		if strings.HasPrefix(fileHeader.Header.Get("Content-Type"), "video/") {
			mediaType = "video"
		} else {
			mediaType = "image"
		}
	}

	ext := filepath.Ext(fileHeader.Filename)
	if ext == "" {
		if mediaType == "video" {
			ext = ".mp4"
		} else {
			ext = ".jpg"
		}
	}

	contentType := fileHeader.Header.Get("Content-Type")

	userID := c.GetString("user_id")
	if userID == "" {
		userID = "anon"
	}

	objectKey := fmt.Sprintf("uploads/%s/%s%s", userID, uuid.New().String(), ext)

	targetBucket := h.bucket
	targetDomain := h.publicDomain
	if mediaType == "video" {
		if h.videoBucket != "" {
			targetBucket = h.videoBucket
		}
		if h.videoDomain != "" {
			targetDomain = h.videoDomain
		}
	}

	// Read the uploaded file into memory
	src, err := fileHeader.Open()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read uploaded file"})
		return
	}
	rawBytes, err := io.ReadAll(src)
	src.Close()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read uploaded file"})
		return
	}

	// Strip metadata (EXIF/GPS from images, all metadata from videos)
	cleanBytes, stripErr := stripMetadata(rawBytes, mediaType, ext)
	if stripErr != nil {
		log.Warn().Err(stripErr).Str("type", mediaType).Msg("metadata strip failed, uploading original")
		cleanBytes = rawBytes
	}

	var publicURL string
	reader := bytes.NewReader(cleanBytes)
	if h.useS3 {
		publicURL, err = h.putObjectS3(c, reader, int64(len(cleanBytes)), contentType, targetBucket, objectKey, targetDomain)
	} else {
		publicURL, err = h.putObjectR2API(c, cleanBytes, contentType, targetBucket, objectKey, targetDomain)
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to upload media: %v", err)})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"url":       publicURL,
		"publicUrl": publicURL,
		"signedUrl": publicURL,
		"fileName":  objectKey,
		"file_name": objectKey,
		"fileSize":  len(cleanBytes),
		"file_size": len(cleanBytes),
		"type":      mediaType,
	})
}

// stripMetadata uses ffmpeg to remove all metadata (EXIF, GPS, camera info)
// from uploaded media before it goes to R2. Returns the cleaned bytes.
func stripMetadata(raw []byte, mediaType string, ext string) ([]byte, error) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		return nil, fmt.Errorf("ffmpeg not found: %w", err)
	}

	tmpDir, err := os.MkdirTemp("", "sojorn-media-*")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(tmpDir)

	inPath := filepath.Join(tmpDir, "input"+ext)
	outPath := filepath.Join(tmpDir, "output"+ext)

	if err := os.WriteFile(inPath, raw, 0644); err != nil {
		return nil, err
	}

	// Run ffmpeg: strip all metadata
	var args []string
	if mediaType == "video" {
		// Copy streams without re-encoding, just drop metadata
		args = []string{"-i", inPath, "-map_metadata", "-1", "-c", "copy", "-y", outPath}
	} else {
		// For images: re-encode to strip EXIF (ffmpeg decodes + encodes, drops metadata)
		args = []string{"-i", inPath, "-map_metadata", "-1", "-y", outPath}
	}

	cmd := exec.Command("ffmpeg", args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		log.Warn().Str("stderr", stderr.String()).Msg("ffmpeg metadata strip stderr")
		return nil, fmt.Errorf("ffmpeg failed: %w", err)
	}

	cleanBytes, err := os.ReadFile(outPath)
	if err != nil {
		return nil, err
	}

	log.Info().
		Str("type", mediaType).
		Int("original_size", len(raw)).
		Int("stripped_size", len(cleanBytes)).
		Msg("metadata stripped from upload")

	return cleanBytes, nil
}

func (h *MediaHandler) putObjectS3(c *gin.Context, body io.ReadSeeker, contentLength int64, contentType string, bucket string, key string, publicDomain string) (string, error) {
	ctx := c.Request.Context()
	_, err := h.s3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      &bucket,
		Key:         &key,
		Body:        body,
		ContentType: &contentType,
	})
	if err != nil {
		return "", err
	}

	if publicDomain != "" {
		return fmt.Sprintf("https://%s/%s", publicDomain, key), nil
	}

	// Fallback to path (relative); AssetService can sign it later.
	return key, nil
}

// GetSignedMediaURL resolves a relative R2 path to a fully-qualified URL.
// Flutter calls GET /media/sign?path=<key> for any path that was stored as a relative key.
func (h *MediaHandler) GetSignedMediaURL(c *gin.Context) {
	path := c.Query("path")
	if path == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "path query parameter is required"})
		return
	}
	if strings.HasPrefix(path, "http") {
		c.JSON(http.StatusOK, gin.H{"url": path})
		return
	}
	domain := h.publicDomain
	if strings.Contains(path, "videos/") {
		domain = h.videoDomain
	}
	if domain == "" {
		c.JSON(http.StatusOK, gin.H{"url": path})
		return
	}
	if !strings.HasPrefix(domain, "http") {
		domain = "https://" + domain
	}
	c.JSON(http.StatusOK, gin.H{"url": fmt.Sprintf("%s/%s", domain, path)})
}

func (h *MediaHandler) putObjectR2API(c *gin.Context, fileBytes []byte, contentType string, bucket string, key string, publicDomain string) (string, error) {
	if h.accountID == "" || h.apiToken == "" {
		return "", fmt.Errorf("R2 API credentials missing")
	}

	endpoint := fmt.Sprintf("https://api.cloudflare.com/client/v4/accounts/%s/r2/buckets/%s/objects/%s",
		h.accountID, bucket, key)

	req, err := http.NewRequestWithContext(c.Request.Context(), "PUT", endpoint, bytes.NewReader(fileBytes))
	if err != nil {
		return "", err
	}

	req.Header.Set("Authorization", "Bearer "+h.apiToken)
	req.Header.Set("Content-Type", contentType)

	client := &http.Client{Timeout: 60 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		return "", fmt.Errorf("R2 upload failed (%d): %s", resp.StatusCode, string(body))
	}

	if publicDomain != "" {
		return fmt.Sprintf("https://%s/%s", publicDomain, key), nil
	}

	return fmt.Sprintf("https://%s.r2.cloudflarestorage.com/%s/%s", h.accountID, bucket, key), nil
}
