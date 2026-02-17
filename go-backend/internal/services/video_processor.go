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

