package services

import (
	"context"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// VideoProcessor handles video frame extraction and analysis
type VideoProcessor struct {
	ffmpegPath string
	tempDir    string
}

// NewVideoProcessor creates a new video processor service
func NewVideoProcessor() *VideoProcessor {
	ffmpegPath, _ := exec.LookPath("ffmpeg")
	return &VideoProcessor{
		ffmpegPath: ffmpegPath,
		tempDir:    "/tmp", // Could be configurable
	}
}

// ExtractFrames extracts key frames from a video URL for moderation analysis
// Returns URLs to extracted frame images
func (vp *VideoProcessor) ExtractFrames(ctx context.Context, videoURL string, frameCount int) ([]string, error) {
	if vp.ffmpegPath == "" {
		return nil, fmt.Errorf("ffmpeg not found on system")
	}

	// Generate unique temp filename
	tempFile := filepath.Join(vp.tempDir, fmt.Sprintf("video_frames_%d.jpg", time.Now().UnixNano()))

	// Extract 3 key frames: beginning, middle, end
	cmd := exec.CommandContext(ctx, vp.ffmpegPath,
		"-i", videoURL,
		"-vf", fmt.Sprintf("select=not(mod(n\\,%d)),scale=640:480", frameCount),
		"-frames:v", "3",
		"-y",
		tempFile,
	)

	output, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("ffmpeg extraction failed: %v, output: %s", err, string(output))
	}

	// For now, return the temp file path
	// In production, this should upload to R2 and return public URLs
	return []string{tempFile}, nil
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
