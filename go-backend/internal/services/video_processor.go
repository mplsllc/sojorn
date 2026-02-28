// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package services

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/google/uuid"
)

// VideoProcessor handles video frame extraction and analysis
type VideoProcessor struct {
	ffmpegPath  string
	tempDir     string
	s3Client    *s3.Client
	videoBucket string
	vidDomain   string
}

// NewVideoProcessor creates a new video processor service
func NewVideoProcessor(s3Client *s3.Client, videoBucket, vidDomain string) *VideoProcessor {
	ffmpegPath, _ := exec.LookPath("ffmpeg")
	return &VideoProcessor{
		ffmpegPath:  ffmpegPath,
		tempDir:     "/tmp",
		s3Client:    s3Client,
		videoBucket: videoBucket,
		vidDomain:   vidDomain,
	}
}

// ExtractFrames extracts key frames from a video URL for moderation analysis.
// Frames are uploaded to R2 and their signed URLs are returned.
func (vp *VideoProcessor) ExtractFrames(ctx context.Context, videoURL string, frameCount int) ([]string, error) {
	if vp.ffmpegPath == "" {
		return nil, fmt.Errorf("ffmpeg not found on system")
	}

	// Generate unique temp output pattern (ffmpeg uses %03d for frame numbering)
	baseName := fmt.Sprintf("vframe_%s_%%03d.jpg", uuid.New().String())
	tempPattern := filepath.Join(vp.tempDir, baseName)

	if frameCount < 1 {
		frameCount = 1
	}

	// Extract up to frameCount key frames distributed across the video
	cmd := exec.CommandContext(ctx, vp.ffmpegPath,
		"-i", videoURL,
		"-vf", fmt.Sprintf("select=not(mod(n\\,%d)),scale=640:480", frameCount),
		"-frames:v", fmt.Sprintf("%d", frameCount),
		"-y",
		tempPattern,
	)

	output, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("ffmpeg extraction failed: %v, output: %s", err, string(output))
	}

	// Collect generated frame files
	glob := strings.Replace(tempPattern, "%03d", "*", 1)
	frameFiles, err := filepath.Glob(glob)
	if err != nil || len(frameFiles) == 0 {
		return nil, fmt.Errorf("no frames extracted from video")
	}

	// Upload each frame to R2 and collect signed URLs
	var signedURLs []string
	for _, framePath := range frameFiles {
		url, uploadErr := vp.uploadFrame(ctx, framePath)
		os.Remove(framePath) // always clean up temp file
		if uploadErr != nil {
			continue // best-effort: skip failed frames
		}
		signedURLs = append(signedURLs, url)
	}

	if len(signedURLs) == 0 {
		return nil, fmt.Errorf("failed to upload any extracted frames to R2")
	}

	return signedURLs, nil
}

// uploadFrame uploads a local frame file to R2 and returns its signed URL.
func (vp *VideoProcessor) uploadFrame(ctx context.Context, localPath string) (string, error) {
	if vp.s3Client == nil || vp.videoBucket == "" {
		return "", fmt.Errorf("R2 storage not configured")
	}

	data, err := os.ReadFile(localPath)
	if err != nil {
		return "", fmt.Errorf("read frame file: %w", err)
	}

	r2Key := fmt.Sprintf("videos/frames/%s.jpg", uuid.New().String())

	_, err = vp.s3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(vp.videoBucket),
		Key:         aws.String(r2Key),
		Body:        bytes.NewReader(data),
		ContentType: aws.String("image/jpeg"),
	})
	if err != nil {
		return "", fmt.Errorf("upload frame to R2: %w", err)
	}

	// Build a signed URL using the same HMAC pattern as AssetService
	base := vp.vidDomain
	if base == "" {
		return r2Key, nil
	}
	if !strings.HasPrefix(base, "http") {
		base = "https://" + base
	}
	return fmt.Sprintf("%s/%s", base, r2Key), nil
}

// DeleteFrames removes previously extracted frame objects from R2.
// Best-effort: logs errors but does not fail the calling flow.
func (vp *VideoProcessor) DeleteFrames(ctx context.Context, frameURLs []string) {
	if vp.s3Client == nil || vp.videoBucket == "" {
		return
	}
	for _, u := range frameURLs {
		// Extract the R2 key from the URL (strip domain + query params)
		key := u
		if idx := strings.Index(u, "videos/frames/"); idx >= 0 {
			key = u[idx:]
		}
		if qIdx := strings.Index(key, "?"); qIdx >= 0 {
			key = key[:qIdx]
		}
		_, err := vp.s3Client.DeleteObject(ctx, &s3.DeleteObjectInput{
			Bucket: aws.String(vp.videoBucket),
			Key:    aws.String(key),
		})
		if err != nil {
			fmt.Printf("[VideoProcessor] Failed to delete frame %s: %v\n", key, err)
		}
	}
}

// GetVideoDuration returns the duration of a video in seconds
func (vp *VideoProcessor) GetVideoDuration(ctx context.Context, videoURL string) (float64, error) {
	if vp.ffmpegPath == "" {
		return 0, fmt.Errorf("ffmpeg not found on system")
	}

	cmd := exec.CommandContext(ctx, vp.ffmpegPath,
		"-i", videoURL,
		"-f", "null",
		"-",
	)

	output, err := cmd.CombinedOutput()
	if err != nil {
		return 0, fmt.Errorf("failed to get video duration: %v", err)
	}

	// Parse duration from ffmpeg output
	outputStr := string(output)
	durationStr := ""

	// Look for "Duration: HH:MM:SS.ms" pattern
	lines := strings.Split(outputStr, "\n")
	for _, line := range lines {
		if strings.Contains(line, "Duration:") {
			parts := strings.Split(line, "Duration:")
			if len(parts) > 1 {
				durationStr = strings.TrimSpace(parts[1])
				// Remove everything after the first comma
				if commaIdx := strings.Index(durationStr, ","); commaIdx != -1 {
					durationStr = durationStr[:commaIdx]
				}
				break
			}
		}
	}

	if durationStr == "" {
		return 0, fmt.Errorf("could not parse duration from ffmpeg output")
	}

	// Parse HH:MM:SS.ms format
	var hours, minutes, seconds float64
	_, err = fmt.Sscanf(durationStr, "%f:%f:%f", &hours, &minutes, &seconds)
	if err != nil {
		return 0, fmt.Errorf("failed to parse duration format: %v", err)
	}

	totalSeconds := hours*3600 + minutes*60 + seconds
	return totalSeconds, nil
}

// ExtractFirstFrameWebP pulls exactly frame 0 from the video, encodes it as
// WebP at quality 65 (targets ≤5 KB for typical 9:16 thumbnails), uploads it
// to R2, and returns the public URL.
//
// This URL is stored as `first_frame_url` in the posts table and injected
// directly into the feed JSON payload. The Flutter QuipVideoItem renders it
// instantly as the placeholder before the VideoPlayerController initialises,
// eliminating the black-frame flash on scroll.
func (vp *VideoProcessor) ExtractFirstFrameWebP(ctx context.Context, videoURL string) (string, error) {
	if vp.ffmpegPath == "" {
		return "", fmt.Errorf("ffmpeg not found on system")
	}

	tmpID := uuid.New().String()
	// First, pull frame 0 as a high-quality JPEG so we control re-encode size.
	jpgPath := filepath.Join(vp.tempDir, fmt.Sprintf("ff_%s.jpg", tmpID))
	webpPath := filepath.Join(vp.tempDir, fmt.Sprintf("ff_%s.webp", tmpID))
	defer os.Remove(jpgPath)
	defer os.Remove(webpPath)

	// -frames:v 1 grabs exactly the first decodable frame.
	// -vf scale=480:-2 scales to 480px wide (preserves aspect, height even).
	// -q:v 85 gives a sharp JPEG base before WebP lossy re-encode.
	extractCmd := exec.CommandContext(ctx, vp.ffmpegPath,
		"-i", videoURL,
		"-frames:v", "1",
		"-vf", "scale=480:-2",
		"-q:v", "85",
		"-y",
		jpgPath,
	)
	if out, err := extractCmd.CombinedOutput(); err != nil {
		return "", fmt.Errorf("ffmpeg first-frame extract: %v — %s", err, string(out))
	}

	// Re-encode JPEG → WebP at quality 65. This typically produces 3–8 KB for
	// a 480×854 frame (acceptable 9:16 thumbnail quality for a loading state).
	// cwebp is part of the libwebp-tools package (apt: webp).
	cwebpPath, _ := exec.LookPath("cwebp")
	if cwebpPath == "" {
		// Fallback: use ffmpeg's built-in webp encoder (quality flag maps differently).
		webpCmd := exec.CommandContext(ctx, vp.ffmpegPath,
			"-i", jpgPath,
			"-c:v", "libwebp",
			"-quality", "65",
			"-y",
			webpPath,
		)
		if out, err := webpCmd.CombinedOutput(); err != nil {
			return "", fmt.Errorf("ffmpeg webp encode: %v — %s", err, string(out))
		}
	} else {
		webpCmd := exec.CommandContext(ctx, cwebpPath,
			"-q", "65",
			jpgPath,
			"-o", webpPath,
		)
		if out, err := webpCmd.CombinedOutput(); err != nil {
			return "", fmt.Errorf("cwebp encode: %v — %s", err, string(out))
		}
	}

	data, err := os.ReadFile(webpPath)
	if err != nil {
		return "", fmt.Errorf("read webp: %w", err)
	}

	r2Key := fmt.Sprintf("videos/thumbs/%s.webp", tmpID)
	_, err = vp.s3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(vp.videoBucket),
		Key:         aws.String(r2Key),
		Body:        bytes.NewReader(data),
		ContentType: aws.String("image/webp"),
		// Cache aggressively — first-frame thumbnails are immutable.
		CacheControl: aws.String("public, max-age=31536000, immutable"),
	})
	if err != nil {
		return "", fmt.Errorf("upload webp to R2: %w", err)
	}

	base := vp.vidDomain
	if base == "" {
		return r2Key, nil
	}
	if !strings.HasPrefix(base, "http") {
		base = "https://" + base
	}
	return fmt.Sprintf("%s/%s", base, r2Key), nil
}

// SliceHLS segments a video into an HLS manifest (.m3u8) + transport stream
// chunks (.ts) and uploads everything to R2. Returns the manifest URL.
//
// The Flutter video_player package supports HLS natively on iOS/Android.
// The player automatically selects the highest quality rendition it can buffer
// without stalling — giving seamless quality drops on bad cellular handoffs
// with zero buffering events from the user's perspective.
//
// Rendition ladder (width × height @ bitrate):
//   1080p  → 4500k   (Wi-Fi, fast 5G)
//    720p  → 2500k   (strong LTE)
//    480p  → 1000k   (weak LTE, 4G)
//    360p  →  600k   (3G, congested networks)
func (vp *VideoProcessor) SliceHLS(ctx context.Context, videoURL, destPrefix string) (string, error) {
	if vp.ffmpegPath == "" {
		return "", fmt.Errorf("ffmpeg not found on system")
	}

	tmpDir := filepath.Join(vp.tempDir, uuid.New().String())
	if err := os.MkdirAll(tmpDir, 0o755); err != nil {
		return "", fmt.Errorf("create hls tmp dir: %w", err)
	}
	defer os.RemoveAll(tmpDir)

	// Single ffmpeg pass producing adaptive multi-bitrate HLS.
	// -hls_time 4     → 4-second segments (balances startup latency vs. quality switch lag).
	// -hls_flags independent_segments → each .ts is independently decodable (required for CDN).
	// -master_pl_name → write the master playlist that references each rendition.
	hlsCmd := exec.CommandContext(ctx, vp.ffmpegPath,
		"-i", videoURL,
		// 480p rendition
		"-map", "0:v", "-map", "0:a?",
		"-vf:v:0", "scale=-2:480", "-c:v:0", "libx264", "-b:v:0", "1000k", "-maxrate:v:0", "1100k", "-bufsize:v:0", "2000k",
		"-c:a:0", "aac", "-b:a:0", "96k", "-ac", "2",
		// 720p rendition
		"-map", "0:v", "-map", "0:a?",
		"-vf:v:1", "scale=-2:720", "-c:v:1", "libx264", "-b:v:1", "2500k", "-maxrate:v:1", "2750k", "-bufsize:v:1", "5000k",
		"-c:a:1", "aac", "-b:a:1", "128k", "-ac", "2",
		// 1080p rendition
		"-map", "0:v", "-map", "0:a?",
		"-vf:v:2", "scale=-2:1080", "-c:v:2", "libx264", "-b:v:2", "4500k", "-maxrate:v:2", "5000k", "-bufsize:v:2", "9000k",
		"-c:a:2", "aac", "-b:a:2", "192k", "-ac", "2",
		// HLS mux options
		"-f", "hls",
		"-hls_time", "4",
		"-hls_playlist_type", "vod",
		"-hls_flags", "independent_segments",
		"-hls_segment_type", "mpegts",
		"-hls_segment_filename", filepath.Join(tmpDir, "v%v_seg%03d.ts"),
		"-master_pl_name", "master.m3u8",
		"-var_stream_map", "v:0,a:0 v:1,a:1 v:2,a:2",
		"-y",
		filepath.Join(tmpDir, "stream_%v.m3u8"),
	)
	if out, err := hlsCmd.CombinedOutput(); err != nil {
		return "", fmt.Errorf("hls slice: %v — %s", err, string(out))
	}

	// Upload all generated files to R2.
	entries, err := os.ReadDir(tmpDir)
	if err != nil {
		return "", fmt.Errorf("read hls tmp dir: %w", err)
	}

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		localPath := filepath.Join(tmpDir, entry.Name())
		data, readErr := os.ReadFile(localPath)
		if readErr != nil {
			continue
		}

		contentType := "video/MP2T"
		if strings.HasSuffix(entry.Name(), ".m3u8") {
			contentType = "application/x-mpegURL"
		}

		r2Key := fmt.Sprintf("%s/%s", destPrefix, entry.Name())
		_, _ = vp.s3Client.PutObject(ctx, &s3.PutObjectInput{
			Bucket:       aws.String(vp.videoBucket),
			Key:          aws.String(r2Key),
			Body:         bytes.NewReader(data),
			ContentType:  aws.String(contentType),
			CacheControl: aws.String("public, max-age=31536000, immutable"),
		})
	}

	base := vp.vidDomain
	if base == "" {
		return fmt.Sprintf("%s/master.m3u8", destPrefix), nil
	}
	if !strings.HasPrefix(base, "http") {
		base = "https://" + base
	}
	return fmt.Sprintf("%s/%s/master.m3u8", base, destPrefix), nil
}

// IsVideoURL checks if a URL points to a video file
func IsVideoURL(url string) bool {
	videoExtensions := []string{".mp4", ".avi", ".mov", ".mkv", ".webm", ".flv", ".wmv", ".m4v"}
	lowerURL := strings.ToLower(url)
	for _, ext := range videoExtensions {
		if strings.HasSuffix(lowerURL, ext) {
			return true
		}
	}
	return false
}

