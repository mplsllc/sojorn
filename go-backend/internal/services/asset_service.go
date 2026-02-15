package services

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/url"
	"strings"
	"time"
)

type AssetService struct {
	r2Secret  string
	r2Base    string
	imgDomain string
	vidDomain string
}

func NewAssetService(secret, base, imgDomain, vidDomain string) *AssetService {
	// Ensure domains have http/https prefix for url.Parse
	if imgDomain != "" && !strings.HasPrefix(imgDomain, "http") {
		imgDomain = "https://" + imgDomain
	}
	if vidDomain != "" && !strings.HasPrefix(vidDomain, "http") {
		vidDomain = "https://" + vidDomain
	}

	return &AssetService{
		r2Secret:  secret,
		r2Base:    base,
		imgDomain: imgDomain,
		vidDomain: vidDomain,
	}
}

// SignURL generates an HMAC-signed URL for Cloudflare R2 assets
func (s *AssetService) SignURL(rawPath string) string {
	return s.signWithBase(rawPath, s.r2Base)
}

// SignImageURL generates an HMAC-signed URL using the image specialized domain
func (s *AssetService) SignImageURL(rawPath string) string {
	if s.imgDomain == "" {
		return s.SignURL(rawPath)
	}
	return s.signWithBase(rawPath, s.imgDomain)
}

// SignVideoURL generates an HMAC-signed URL using the video specialized domain
func (s *AssetService) SignVideoURL(rawPath string) string {
	if s.vidDomain == "" {
		return s.SignURL(rawPath)
	}
	return s.signWithBase(rawPath, s.vidDomain)
}

func (s *AssetService) signWithBase(rawPath, base string) string {
	if rawPath == "" || strings.HasPrefix(rawPath, "http") {
		return rawPath
	}

	// Remove leading slash if present
	path := strings.TrimPrefix(rawPath, "/")

	if s.r2Secret == "" {
		return fmt.Sprintf("%s/%s", base, path)
	}

	expiry := time.Now().Add(24 * time.Hour).Unix()
	mac := hmac.New(sha256.New, []byte(s.r2Secret))
	data := fmt.Sprintf("%s:%d", path, expiry)
	mac.Write([]byte(data))
	signature := hex.EncodeToString(mac.Sum(nil))

	u, err := url.Parse(fmt.Sprintf("%s/%s", base, path))
	if err != nil {
		return rawPath
	}

	q := u.Query()
	q.Set("exp", fmt.Sprintf("%d", expiry))
	q.Set("sig", signature)
	u.RawQuery = q.Encode()

	return u.String()
}
