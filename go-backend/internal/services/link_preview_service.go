package services

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"html"
	"io"
	"net"
	"net/http"
	"net/url"
	"path"
	"regexp"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"
)

// formatTime formats a time.Time to a string for JSON output.
func formatTime(t time.Time) string {
	return t.Format(time.RFC3339)
}

// LinkPreview represents the OG metadata extracted from a URL.
type LinkPreview struct {
	URL         string `json:"link_preview_url"`
	Title       string `json:"link_preview_title"`
	Description string `json:"link_preview_description"`
	ImageURL    string `json:"link_preview_image_url"`
	SiteName    string `json:"link_preview_site_name"`
}

// LinkPreviewService fetches and parses OpenGraph metadata from URLs.
type LinkPreviewService struct {
	pool        *pgxpool.Pool
	httpClient  *http.Client
	s3Client    *s3.Client
	mediaBucket string
	imgDomain   string
}

func NewLinkPreviewService(pool *pgxpool.Pool, s3Client *s3.Client, mediaBucket string, imgDomain string) *LinkPreviewService {
	return &LinkPreviewService{
		pool:        pool,
		s3Client:    s3Client,
		mediaBucket: mediaBucket,
		imgDomain:   imgDomain,
		httpClient: &http.Client{
			Timeout: 8 * time.Second,
			CheckRedirect: func(req *http.Request, via []*http.Request) error {
				if len(via) >= 5 {
					return fmt.Errorf("too many redirects")
				}
				return nil
			},
		},
	}
}

// blockedIPRanges are private/internal IP ranges that untrusted URLs must not resolve to.
var blockedIPRanges = []string{
	"127.0.0.0/8",
	"10.0.0.0/8",
	"172.16.0.0/12",
	"192.168.0.0/16",
	"169.254.0.0/16",
	"::1/128",
	"fc00::/7",
	"fe80::/10",
}

var blockedNets []*net.IPNet

func init() {
	for _, cidr := range blockedIPRanges {
		_, ipNet, err := net.ParseCIDR(cidr)
		if err == nil {
			blockedNets = append(blockedNets, ipNet)
		}
	}
}

func isPrivateIP(ip net.IP) bool {
	for _, n := range blockedNets {
		if n.Contains(ip) {
			return true
		}
	}
	return false
}

// ExtractFirstURL finds the first http/https URL in a text string.
func ExtractFirstURL(text string) string {
	re := regexp.MustCompile(`https?://[^\s<>"')\]]+`)
	match := re.FindString(text)
	// Clean trailing punctuation that's not part of the URL
	match = strings.TrimRight(match, ".,;:!?")
	return match
}

// FetchPreview fetches OG metadata from a URL.
// If trusted is false, performs safety checks (no internal IPs, domain validation).
func (s *LinkPreviewService) FetchPreview(ctx context.Context, rawURL string, trusted bool) (*LinkPreview, error) {
	if rawURL == "" {
		return nil, fmt.Errorf("empty URL")
	}

	parsed, err := url.Parse(rawURL)
	if err != nil {
		return nil, fmt.Errorf("invalid URL: %w", err)
	}

	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return nil, fmt.Errorf("unsupported scheme: %s", parsed.Scheme)
	}

	// Safety checks for untrusted URLs
	if !trusted {
		if err := s.validateURL(parsed); err != nil {
			return nil, fmt.Errorf("unsafe URL: %w", err)
		}
	}

	req, err := http.NewRequestWithContext(ctx, "GET", rawURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Accept", "text/html")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	ct := resp.Header.Get("Content-Type")
	if !strings.Contains(ct, "text/html") && !strings.Contains(ct, "application/xhtml") {
		return nil, fmt.Errorf("not HTML: %s", ct)
	}

	// Read max 1MB
	limited := io.LimitReader(resp.Body, 1*1024*1024)
	body, err := io.ReadAll(limited)
	if err != nil {
		return nil, err
	}

	preview := s.parseOGTags(string(body), rawURL)
	if preview.Title == "" && preview.Description == "" && preview.ImageURL == "" {
		return nil, fmt.Errorf("no OG metadata found")
	}

	preview.URL = rawURL
	if preview.SiteName == "" {
		preview.SiteName = parsed.Hostname()
	}

	return preview, nil
}

// validateURL checks that an untrusted URL doesn't point to internal resources.
func (s *LinkPreviewService) validateURL(u *url.URL) error {
	host := u.Hostname()

	// Block bare IPs for untrusted requests
	if ip := net.ParseIP(host); ip != nil {
		if isPrivateIP(ip) {
			return fmt.Errorf("private IP not allowed")
		}
	}

	// Resolve DNS and check all IPs
	ips, err := net.LookupIP(host)
	if err != nil {
		return fmt.Errorf("DNS lookup failed: %w", err)
	}
	for _, ip := range ips {
		if isPrivateIP(ip) {
			return fmt.Errorf("resolves to private IP")
		}
	}

	return nil
}

// parseOGTags extracts OpenGraph meta tags from raw HTML.
func (s *LinkPreviewService) parseOGTags(htmlStr string, sourceURL string) *LinkPreview {
	preview := &LinkPreview{}

	// Use regex to extract meta tags — lightweight, no dependency needed
	metaRe := regexp.MustCompile(`(?i)<meta\s+[^>]*>`)
	metas := metaRe.FindAllString(htmlStr, -1)

	for _, tag := range metas {
		prop := extractAttr(tag, "property")
		if prop == "" {
			prop = extractAttr(tag, "name")
		}
		content := html.UnescapeString(extractAttr(tag, "content"))
		if content == "" {
			continue
		}

		switch strings.ToLower(prop) {
		case "og:title":
			if preview.Title == "" {
				preview.Title = content
			}
		case "og:description":
			if preview.Description == "" {
				preview.Description = content
			}
		case "og:image":
			if preview.ImageURL == "" {
				preview.ImageURL = resolveImageURL(content, sourceURL)
			}
		case "og:site_name":
			if preview.SiteName == "" {
				preview.SiteName = content
			}
		case "description":
			// Fallback if no og:description
			if preview.Description == "" {
				preview.Description = content
			}
		}
	}

	// Fallback: try <title> tag if no og:title
	if preview.Title == "" {
		titleRe := regexp.MustCompile(`(?i)<title[^>]*>(.*?)</title>`)
		if m := titleRe.FindStringSubmatch(htmlStr); len(m) > 1 {
			preview.Title = html.UnescapeString(strings.TrimSpace(m[1]))
		}
	}

	// Truncate long fields
	if len(preview.Title) > 300 {
		preview.Title = preview.Title[:300]
	}
	if len(preview.Description) > 500 {
		preview.Description = preview.Description[:500]
	}

	return preview
}

// extractAttr pulls a named attribute value from a raw HTML tag string.
func extractAttr(tag string, name string) string {
	// Match name="value" or name='value'
	re := regexp.MustCompile(`(?i)\b` + regexp.QuoteMeta(name) + `\s*=\s*["']([^"']*?)["']`)
	m := re.FindStringSubmatch(tag)
	if len(m) > 1 {
		return strings.TrimSpace(m[1])
	}
	return ""
}

// resolveImageURL makes relative image URLs absolute.
func resolveImageURL(imgURL string, sourceURL string) string {
	if strings.HasPrefix(imgURL, "http://") || strings.HasPrefix(imgURL, "https://") {
		return imgURL
	}
	base, err := url.Parse(sourceURL)
	if err != nil {
		return imgURL
	}
	ref, err := url.Parse(imgURL)
	if err != nil {
		return imgURL
	}
	return base.ResolveReference(ref).String()
}

// EnrichPostsWithLinkPreviews does a batch query to populate link_preview fields
// on a slice of posts. This avoids modifying every existing SELECT query.
func (s *LinkPreviewService) EnrichPostsWithLinkPreviews(ctx context.Context, postIDs []string) (map[string]*LinkPreview, error) {
	if len(postIDs) == 0 {
		return nil, nil
	}

	query := `
		SELECT id::text, link_preview_url, link_preview_title, 
		       link_preview_description, link_preview_image_url, link_preview_site_name
		FROM public.posts
		WHERE id = ANY($1::uuid[]) AND link_preview_url IS NOT NULL AND link_preview_url != ''
	`
	rows, err := s.pool.Query(ctx, query, postIDs)
	if err != nil {
		log.Warn().Err(err).Msg("Failed to fetch link previews for posts")
		return nil, err
	}
	defer rows.Close()

	result := make(map[string]*LinkPreview)
	for rows.Next() {
		var postID string
		var lp LinkPreview
		var title, desc, imgURL, siteName *string
		if err := rows.Scan(&postID, &lp.URL, &title, &desc, &imgURL, &siteName); err != nil {
			continue
		}
		if title != nil {
			lp.Title = *title
		}
		if desc != nil {
			lp.Description = *desc
		}
		if imgURL != nil {
			lp.ImageURL = *imgURL
		}
		if siteName != nil {
			lp.SiteName = *siteName
		}
		result[postID] = &lp
	}
	return result, nil
}

// SaveLinkPreview stores the link preview data for a post.
func (s *LinkPreviewService) SaveLinkPreview(ctx context.Context, postID string, lp *LinkPreview) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE public.posts 
		SET link_preview_url = $2, link_preview_title = $3, link_preview_description = $4, 
		    link_preview_image_url = $5, link_preview_site_name = $6
		WHERE id = $1
	`, postID, lp.URL, lp.Title, lp.Description, lp.ImageURL, lp.SiteName)
	return err
}

// ProxyImageToR2 downloads an external OG image and uploads it to R2.
// On success, lp.ImageURL is replaced with the R2 object key (e.g. "og/abc123.jpg").
// If S3 is not configured or the download fails, the original URL is left unchanged.
func (s *LinkPreviewService) ProxyImageToR2(ctx context.Context, lp *LinkPreview) {
	if s.s3Client == nil || s.mediaBucket == "" || lp == nil || lp.ImageURL == "" {
		return
	}

	// Only proxy external http(s) URLs
	if !strings.HasPrefix(lp.ImageURL, "http://") && !strings.HasPrefix(lp.ImageURL, "https://") {
		return
	}

	// Download the image with a short timeout
	dlCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(dlCtx, "GET", lp.ImageURL, nil)
	if err != nil {
		log.Warn().Err(err).Str("url", lp.ImageURL).Msg("[LinkPreview] Failed to create image download request")
		return
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		log.Warn().Err(err).Str("url", lp.ImageURL).Msg("[LinkPreview] Failed to download OG image")
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		log.Warn().Int("status", resp.StatusCode).Str("url", lp.ImageURL).Msg("[LinkPreview] OG image download returned non-200")
		return
	}

	// Read max 5MB
	imgBytes, err := io.ReadAll(io.LimitReader(resp.Body, 5*1024*1024))
	if err != nil || len(imgBytes) == 0 {
		log.Warn().Err(err).Str("url", lp.ImageURL).Msg("[LinkPreview] Failed to read OG image bytes")
		return
	}

	// Determine content type and extension
	ct := resp.Header.Get("Content-Type")
	ext := ".jpg"
	switch {
	case strings.Contains(ct, "png"):
		ext = ".png"
	case strings.Contains(ct, "gif"):
		ext = ".gif"
	case strings.Contains(ct, "webp"):
		ext = ".webp"
	case strings.Contains(ct, "svg"):
		ext = ".svg"
	}

	// Generate a deterministic key from the source URL hash
	hash := sha256.Sum256([]byte(lp.ImageURL))
	hashStr := hex.EncodeToString(hash[:12])
	objectKey := path.Join("og", hashStr+ext)

	// Upload to R2
	contentType := ct
	if contentType == "" {
		contentType = "image/jpeg"
	}
	reader := bytes.NewReader(imgBytes)
	_, err = s.s3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      &s.mediaBucket,
		Key:         &objectKey,
		Body:        reader,
		ContentType: &contentType,
	})
	if err != nil {
		log.Warn().Err(err).Str("key", objectKey).Msg("[LinkPreview] Failed to upload OG image to R2")
		return
	}

	log.Info().Str("key", objectKey).Str("original", lp.ImageURL).Msg("[LinkPreview] OG image proxied to R2")
	lp.ImageURL = objectKey
}

// ── Safe Domains ─────────────────────────────────────

// SafeDomain represents a row in the safe_domains table.
type SafeDomain struct {
	ID         string    `json:"id"`
	Domain     string    `json:"domain"`
	Category   string    `json:"category"`
	IsApproved bool      `json:"is_approved"`
	Notes      *string   `json:"notes"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

// ListSafeDomains returns all safe domains, optionally filtered.
func (s *LinkPreviewService) ListSafeDomains(ctx context.Context, category string, approvedOnly bool) ([]SafeDomain, error) {
	query := `SELECT id, domain, category, is_approved, notes, created_at, updated_at FROM safe_domains WHERE 1=1`
	args := []interface{}{}
	idx := 1

	if category != "" {
		query += fmt.Sprintf(" AND category = $%d", idx)
		args = append(args, category)
		idx++
	}
	if approvedOnly {
		query += fmt.Sprintf(" AND is_approved = $%d", idx)
		args = append(args, true)
		idx++
	}
	query += " ORDER BY category, domain"

	rows, err := s.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var domains []SafeDomain
	for rows.Next() {
		var d SafeDomain
		if err := rows.Scan(&d.ID, &d.Domain, &d.Category, &d.IsApproved, &d.Notes, &d.CreatedAt, &d.UpdatedAt); err != nil {
			log.Warn().Err(err).Msg("Failed to scan safe domain row")
			continue
		}
		domains = append(domains, d)
	}
	if domains == nil {
		domains = []SafeDomain{}
	}
	return domains, nil
}

// UpsertSafeDomain creates or updates a safe domain entry.
func (s *LinkPreviewService) UpsertSafeDomain(ctx context.Context, domain, category string, isApproved bool, notes string) (*SafeDomain, error) {
	domain = strings.ToLower(strings.TrimSpace(domain))
	if domain == "" {
		return nil, fmt.Errorf("domain is required")
	}

	var d SafeDomain
	err := s.pool.QueryRow(ctx, `
		INSERT INTO safe_domains (domain, category, is_approved, notes)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (domain) DO UPDATE SET
			category = EXCLUDED.category,
			is_approved = EXCLUDED.is_approved,
			notes = EXCLUDED.notes,
			updated_at = NOW()
		RETURNING id, domain, category, is_approved, notes, created_at, updated_at
	`, domain, category, isApproved, notes).Scan(&d.ID, &d.Domain, &d.Category, &d.IsApproved, &d.Notes, &d.CreatedAt, &d.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &d, nil
}

// DeleteSafeDomain removes a safe domain by ID.
func (s *LinkPreviewService) DeleteSafeDomain(ctx context.Context, id string) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM safe_domains WHERE id = $1`, id)
	return err
}

// IsDomainSafe checks if a URL's domain (or any parent domain) is in the approved list.
// Returns: (isSafe bool, isBlocked bool, category string)
// isSafe=true means explicitly approved. isBlocked=true means explicitly blocked.
// Both false means unknown (not in the list).
func (s *LinkPreviewService) IsDomainSafe(ctx context.Context, rawURL string) (bool, bool, string) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return false, false, ""
	}
	host := strings.ToLower(parsed.Hostname())

	// Check the domain and all parent domains (e.g., news.bbc.co.uk → bbc.co.uk → co.uk)
	parts := strings.Split(host, ".")
	for i := 0; i < len(parts)-1; i++ {
		candidate := strings.Join(parts[i:], ".")
		var isApproved bool
		var category string
		err := s.pool.QueryRow(ctx,
			`SELECT is_approved, category FROM safe_domains WHERE domain = $1`,
			candidate,
		).Scan(&isApproved, &category)
		if err == nil {
			return isApproved, !isApproved, category
		}
	}
	return false, false, ""
}

// CheckURLSafety returns a safety assessment for a URL (used by the Flutter app).
func (s *LinkPreviewService) CheckURLSafety(ctx context.Context, rawURL string) map[string]interface{} {
	isSafe, isBlocked, category := s.IsDomainSafe(ctx, rawURL)

	parsed, _ := url.Parse(rawURL)
	domain := ""
	if parsed != nil {
		domain = parsed.Hostname()
	}

	status := "unknown"
	if isSafe {
		status = "safe"
	} else if isBlocked {
		status = "blocked"
	}

	return map[string]interface{}{
		"url":      rawURL,
		"domain":   domain,
		"status":   status,
		"category": category,
		"safe":     isSafe,
		"blocked":  isBlocked,
	}
}
