// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package services

import (
	"bytes"
	"context"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"html"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"
)

// OfficialAccountConfig represents a row in official_account_configs
type OfficialAccountConfig struct {
	ID                  string          `json:"id"`
	ProfileID           string          `json:"profile_id"`
	AccountType         string          `json:"account_type"`
	Enabled             bool            `json:"enabled"`
	ModelID             string          `json:"model_id"`
	SystemPrompt        string          `json:"system_prompt"`
	Temperature         float64         `json:"temperature"`
	MaxTokens           int             `json:"max_tokens"`
	PostIntervalMinutes int             `json:"post_interval_minutes"`
	MaxPostsPerDay      int             `json:"max_posts_per_day"`
	PostsToday          int             `json:"posts_today"`
	PostsTodayResetAt   time.Time       `json:"posts_today_reset_at"`
	LastPostedAt        *time.Time      `json:"last_posted_at"`
	NewsSources         json.RawMessage `json:"news_sources"`
	LastFetchedAt       *time.Time      `json:"last_fetched_at"`
	CreatedAt           time.Time       `json:"created_at"`
	UpdatedAt           time.Time       `json:"updated_at"`

	// Joined fields
	Handle      string `json:"handle,omitempty"`
	DisplayName string `json:"display_name,omitempty"`
	AvatarURL   string `json:"avatar_url,omitempty"`
}

// NewsSource represents a single news feed configuration.
// If Site is set, SearXNG is used to find news articles for that site.
// If RSSURL is set directly, the RSS feed is fetched as-is.
type NewsSource struct {
	Name    string `json:"name"`
	Site    string `json:"site,omitempty"`
	RSSURL  string `json:"rss_url,omitempty"`
	Enabled bool   `json:"enabled"`
}

// SearXNGResponse represents the JSON response from SearXNG /search endpoint.
type SearXNGResponse struct {
	Results []SearXNGResult `json:"results"`
}

// SearXNGResult represents a single search result from SearXNG.
type SearXNGResult struct {
	URL           string `json:"url"`
	Title         string `json:"title"`
	Content       string `json:"content"`
	PublishedDate string `json:"publishedDate"`
	Thumbnail     string `json:"thumbnail"`
	Engine        string `json:"engine"`
	Category      string `json:"category"`
}

// UseSearXNG returns true if this source should use SearXNG (has a Site configured).
func (ns *NewsSource) UseSearXNG() bool {
	return ns.Site != ""
}

// EffectiveRSSURL returns the direct RSS URL if set, empty string otherwise.
func (ns *NewsSource) EffectiveRSSURL() string {
	return ns.RSSURL
}

// RSSFeed represents a parsed RSS feed
type RSSFeed struct {
	Channel struct {
		Title string    `xml:"title"`
		Items []RSSItem `xml:"item"`
	} `xml:"channel"`
}

// RSSItem represents a single RSS item
type RSSItem struct {
	Title       string    `xml:"title" json:"title"`
	Link        string    `xml:"link" json:"link"`
	Description string    `xml:"description" json:"description"`
	PubDate     string    `xml:"pubDate" json:"pub_date"`
	GUID        string    `xml:"guid" json:"guid"`
	Source      RSSSource `xml:"source" json:"source"`
}

// RSSSource represents the <source> element in Google News RSS items.
type RSSSource struct {
	URL  string `xml:"url,attr" json:"url"`
	Name string `xml:",chardata" json:"name"`
}

// CachedArticle represents a row in official_account_articles (the article pipeline).
// Status flow: discovered → posted | failed | skipped
type CachedArticle struct {
	ID           string     `json:"id"`
	ConfigID     string     `json:"config_id"`
	GUID         string     `json:"guid"`
	Title        string     `json:"title"`
	Link         string     `json:"link"`
	SourceName   string     `json:"source_name"`
	SourceURL    string     `json:"source_url"`
	Description  string     `json:"description"`
	PubDate      *time.Time `json:"pub_date,omitempty"`
	Status       string     `json:"status"`
	PostID       *string    `json:"post_id,omitempty"`
	ErrorMessage *string    `json:"error_message,omitempty"`
	DiscoveredAt time.Time  `json:"discovered_at"`
	PostedAt     *time.Time `json:"posted_at,omitempty"`
}

// OfficialAccountsService manages official account automation
type OfficialAccountsService struct {
	pool               *pgxpool.Pool
	localAIService     *LocalAIService
	linkPreviewService *LinkPreviewService
	httpClient         *http.Client
	stopCh             chan struct{}
	wg                 sync.WaitGroup
	searxngURL         string
	ollamaURL          string
}

func NewOfficialAccountsService(pool *pgxpool.Pool, localAIService *LocalAIService, linkPreviewService *LinkPreviewService, searxngURL, ollamaURL string) *OfficialAccountsService {
	return &OfficialAccountsService{
		pool:               pool,
		localAIService:     localAIService,
		linkPreviewService: linkPreviewService,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		stopCh:     make(chan struct{}),
		searxngURL: searxngURL,
		ollamaURL:  ollamaURL,
	}
}

// ── CRUD ─────────────────────────────────────────────

func (s *OfficialAccountsService) ListConfigs(ctx context.Context) ([]OfficialAccountConfig, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT c.id, c.profile_id, c.account_type, c.enabled,
		       c.model_id, c.system_prompt, c.temperature, c.max_tokens,
		       c.post_interval_minutes, c.max_posts_per_day, c.posts_today, c.posts_today_reset_at,
		       c.last_posted_at, c.news_sources, c.last_fetched_at,
		       c.created_at, c.updated_at,
		       p.handle, p.display_name, COALESCE(p.avatar_url, '')
		FROM official_account_configs c
		JOIN public.profiles p ON p.id = c.profile_id
		ORDER BY c.created_at DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var configs []OfficialAccountConfig
	for rows.Next() {
		var c OfficialAccountConfig
		if err := rows.Scan(
			&c.ID, &c.ProfileID, &c.AccountType, &c.Enabled,
			&c.ModelID, &c.SystemPrompt, &c.Temperature, &c.MaxTokens,
			&c.PostIntervalMinutes, &c.MaxPostsPerDay, &c.PostsToday, &c.PostsTodayResetAt,
			&c.LastPostedAt, &c.NewsSources, &c.LastFetchedAt,
			&c.CreatedAt, &c.UpdatedAt,
			&c.Handle, &c.DisplayName, &c.AvatarURL,
		); err != nil {
			return nil, err
		}
		configs = append(configs, c)
	}
	return configs, nil
}

func (s *OfficialAccountsService) GetConfig(ctx context.Context, id string) (*OfficialAccountConfig, error) {
	var c OfficialAccountConfig
	err := s.pool.QueryRow(ctx, `
		SELECT c.id, c.profile_id, c.account_type, c.enabled,
		       c.model_id, c.system_prompt, c.temperature, c.max_tokens,
		       c.post_interval_minutes, c.max_posts_per_day, c.posts_today, c.posts_today_reset_at,
		       c.last_posted_at, c.news_sources, c.last_fetched_at,
		       c.created_at, c.updated_at,
		       p.handle, p.display_name, COALESCE(p.avatar_url, '')
		FROM official_account_configs c
		JOIN public.profiles p ON p.id = c.profile_id
		WHERE c.id = $1
	`, id).Scan(
		&c.ID, &c.ProfileID, &c.AccountType, &c.Enabled,
		&c.ModelID, &c.SystemPrompt, &c.Temperature, &c.MaxTokens,
		&c.PostIntervalMinutes, &c.MaxPostsPerDay, &c.PostsToday, &c.PostsTodayResetAt,
		&c.LastPostedAt, &c.NewsSources, &c.LastFetchedAt,
		&c.CreatedAt, &c.UpdatedAt,
		&c.Handle, &c.DisplayName, &c.AvatarURL,
	)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

func (s *OfficialAccountsService) UpsertConfig(ctx context.Context, cfg OfficialAccountConfig) (*OfficialAccountConfig, error) {
	newsJSON, err := json.Marshal(cfg.NewsSources)
	if err != nil {
		newsJSON = []byte("[]")
	}

	var id string
	err = s.pool.QueryRow(ctx, `
		INSERT INTO official_account_configs
			(profile_id, account_type, enabled, model_id, system_prompt, temperature, max_tokens,
			 post_interval_minutes, max_posts_per_day, news_sources, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW())
		ON CONFLICT (profile_id)
		DO UPDATE SET
			account_type = EXCLUDED.account_type,
			enabled = EXCLUDED.enabled,
			model_id = EXCLUDED.model_id,
			system_prompt = EXCLUDED.system_prompt,
			temperature = EXCLUDED.temperature,
			max_tokens = EXCLUDED.max_tokens,
			post_interval_minutes = EXCLUDED.post_interval_minutes,
			max_posts_per_day = EXCLUDED.max_posts_per_day,
			news_sources = EXCLUDED.news_sources,
			updated_at = NOW()
		RETURNING id
	`, cfg.ProfileID, cfg.AccountType, cfg.Enabled, cfg.ModelID, cfg.SystemPrompt,
		cfg.Temperature, cfg.MaxTokens, cfg.PostIntervalMinutes, cfg.MaxPostsPerDay, newsJSON,
	).Scan(&id)
	if err != nil {
		return nil, err
	}
	return s.GetConfig(ctx, id)
}

func (s *OfficialAccountsService) DeleteConfig(ctx context.Context, id string) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM official_account_configs WHERE id = $1`, id)
	return err
}

func (s *OfficialAccountsService) ToggleEnabled(ctx context.Context, id string, enabled bool) error {
	_, err := s.pool.Exec(ctx, `UPDATE official_account_configs SET enabled = $2, updated_at = NOW() WHERE id = $1`, id, enabled)
	return err
}

// ── News Fetching (SearXNG + RSS) ───────────────────

// FetchSearXNGNews queries the local SearXNG instance for news about a site.
// Returns results as RSSItems for uniform handling in the pipeline.
func (s *OfficialAccountsService) FetchSearXNGNews(ctx context.Context, site string) ([]RSSItem, error) {
	searchURL := fmt.Sprintf("%s/search?q=site:%s&categories=news&format=json&language=en", s.searxngURL, site)

	req, err := http.NewRequestWithContext(ctx, "GET", searchURL, nil)
	if err != nil {
		return nil, err
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("SearXNG request failed for site %s: %w", site, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("SearXNG returned status %d for site %s", resp.StatusCode, site)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var sxResp SearXNGResponse
	if err := json.Unmarshal(body, &sxResp); err != nil {
		return nil, fmt.Errorf("failed to parse SearXNG response: %w", err)
	}

	// Convert SearXNG results to RSSItems
	var items []RSSItem
	for _, r := range sxResp.Results {
		if r.URL == "" || r.Title == "" {
			continue
		}
		item := RSSItem{
			Title:       html.UnescapeString(r.Title),
			Link:        r.URL,
			Description: html.UnescapeString(r.Content),
			GUID:        r.URL, // use the actual URL as GUID for dedup
		}
		if r.PublishedDate != "" {
			item.PubDate = r.PublishedDate
		}
		items = append(items, item)
	}

	log.Debug().Int("results", len(items)).Str("site", site).Msg("[SearXNG] Fetched news articles")
	return items, nil
}

// FetchRSS fetches and parses a standard RSS/XML feed.
func (s *OfficialAccountsService) FetchRSS(ctx context.Context, rssURL string) ([]RSSItem, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", rssURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (compatible; Sojorn/1.0)")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch RSS %s: %w", rssURL, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("RSS feed %s returned status %d", rssURL, resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var feed RSSFeed
	if err := xml.Unmarshal(body, &feed); err != nil {
		return nil, fmt.Errorf("failed to parse RSS from %s: %w", rssURL, err)
	}

	return feed.Channel.Items, nil
}

// ── Article Pipeline ─────────────────────────────────

// DiscoverArticles fetches RSS feeds and caches all new articles in the DB as 'discovered'.
// Returns the number of newly discovered articles.
func (s *OfficialAccountsService) DiscoverArticles(ctx context.Context, configID string) (int, error) {
	cfg, err := s.GetConfig(ctx, configID)
	if err != nil {
		return 0, err
	}

	var sources []NewsSource
	if err := json.Unmarshal(cfg.NewsSources, &sources); err != nil {
		return 0, fmt.Errorf("failed to parse news sources: %w", err)
	}

	newCount := 0
	for _, src := range sources {
		if !src.Enabled {
			continue
		}

		// Fetch articles: SearXNG for site-based sources, RSS for direct feed URLs.
		// Falls back to Google News RSS when SearXNG is unavailable.
		var items []RSSItem
		var fetchErr error
		if src.UseSearXNG() {
			items, fetchErr = s.FetchSearXNGNews(ctx, src.Site)
			if fetchErr != nil {
				log.Warn().Err(fetchErr).Str("source", src.Name).Msg("SearXNG failed, falling back to Google News RSS")
				googleRSS := fmt.Sprintf("https://news.google.com/rss/search?q=site:%s&hl=en-US&gl=US&ceid=US:en", src.Site)
				items, fetchErr = s.FetchRSS(ctx, googleRSS)
			}
		} else if rssURL := src.EffectiveRSSURL(); rssURL != "" {
			items, fetchErr = s.FetchRSS(ctx, rssURL)
		} else {
			continue
		}
		if fetchErr != nil {
			log.Warn().Err(fetchErr).Str("source", src.Name).Msg("Failed to fetch articles")
			continue
		}

		for _, item := range items {
			guid := item.GUID
			if guid == "" {
				guid = item.Link
			}
			if guid == "" {
				continue
			}

			// Parse pub date — support multiple formats
			var pubDate *time.Time
			if item.PubDate != "" {
				for _, layout := range []string{
					time.RFC1123Z, time.RFC1123, time.RFC822Z, time.RFC822,
					"Mon, 2 Jan 2006 15:04:05 -0700",
					"2006-01-02T15:04:05Z",
					"2006-01-02T15:04:05", // SearXNG format
					"2006-01-02 15:04:05", // SearXNG alt format
					time.RFC3339,
				} {
					if t, err := time.Parse(layout, item.PubDate); err == nil {
						pubDate = &t
						break
					}
				}
			}

			// Strip HTML from description
			desc := stripHTMLTags(item.Description)
			if len(desc) > 1000 {
				desc = desc[:1000]
			}

			// Source URL: use RSS source element if present, otherwise build from site
			sourceURL := item.Source.URL
			if sourceURL == "" && src.Site != "" {
				sourceURL = "https://" + src.Site
			}

			// Insert into pipeline — ON CONFLICT means we already know about this article
			tag, err := s.pool.Exec(ctx, `
				INSERT INTO official_account_articles
					(config_id, guid, title, link, source_name, source_url, description, pub_date, status)
				VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'discovered')
				ON CONFLICT (config_id, guid) DO NOTHING
			`, configID, guid, item.Title, item.Link, src.Name, sourceURL, desc, pubDate)
			if err != nil {
				log.Warn().Err(err).Str("guid", guid).Msg("Failed to cache article")
				continue
			}
			if tag.RowsAffected() > 0 {
				newCount++
			}
		}
	}

	// Update last_fetched_at
	_, _ = s.pool.Exec(ctx, `UPDATE official_account_configs SET last_fetched_at = NOW() WHERE id = $1`, configID)

	if newCount > 0 {
		log.Info().Int("new", newCount).Str("config", configID).Msg("[OfficialAccounts] Discovered new articles")
	}
	return newCount, nil
}

// PostNextArticle picks the oldest 'discovered' article and posts it.
// For RSS accounts: posts the link directly.
// For news accounts: generates AI commentary then posts.
// Returns the CachedArticle and post ID, or nil if nothing to post.
func (s *OfficialAccountsService) PostNextArticle(ctx context.Context, configID string) (*CachedArticle, string, error) {
	cfg, err := s.GetConfig(ctx, configID)
	if err != nil {
		return nil, "", err
	}

	// Pick the oldest discovered article
	var art CachedArticle
	err = s.pool.QueryRow(ctx, `
		SELECT id, config_id, guid, title, link, source_name, source_url, description, pub_date,
		       status, post_id, error_message, discovered_at, posted_at
		FROM official_account_articles
		WHERE config_id = $1 AND status = 'discovered'
		ORDER BY discovered_at ASC
		LIMIT 1
	`, configID).Scan(
		&art.ID, &art.ConfigID, &art.GUID, &art.Title, &art.Link, &art.SourceName, &art.SourceURL,
		&art.Description, &art.PubDate, &art.Status, &art.PostID, &art.ErrorMessage,
		&art.DiscoveredAt, &art.PostedAt,
	)
	if err == pgx.ErrNoRows {
		return nil, "", nil // nothing to post
	}
	if err != nil {
		return nil, "", fmt.Errorf("failed to query next article: %w", err)
	}

	// Build the post body
	var body string
	switch cfg.AccountType {
	case "rss":
		// Empty body — the link preview card handles all display
		body = ""
	case "news":
		// Generate AI commentary
		rssItem := &RSSItem{
			Title:       art.Title,
			Link:        art.Link,
			Description: art.Description,
		}
		generated, err := s.GeneratePost(ctx, configID, rssItem, art.SourceName)
		if err != nil {
			// Mark as failed
			_, _ = s.pool.Exec(ctx,
				`UPDATE official_account_articles SET status = 'failed', error_message = $2 WHERE id = $1`,
				art.ID, err.Error())
			return &art, "", fmt.Errorf("AI generation failed: %w", err)
		}
		body = generated
	default:
		body = art.Title
	}

	// Create the post
	postID, err := s.CreatePostForArticle(ctx, configID, body, &art)
	if err != nil {
		// Mark as failed
		_, _ = s.pool.Exec(ctx,
			`UPDATE official_account_articles SET status = 'failed', error_message = $2 WHERE id = $1`,
			art.ID, err.Error())
		return &art, "", err
	}

	// Mark as posted
	_, _ = s.pool.Exec(ctx,
		`UPDATE official_account_articles SET status = 'posted', post_id = $2, posted_at = NOW() WHERE id = $1`,
		art.ID, postID)

	return &art, postID, nil
}

// ReconcilePostedArticles checks for articles marked 'posted' whose post no longer
// exists in the posts table, and reverts them to 'discovered' so they can be re-posted.
func (s *OfficialAccountsService) ReconcilePostedArticles(ctx context.Context, configID string) (int, error) {
	tag, err := s.pool.Exec(ctx, `
		UPDATE official_account_articles a
		SET status = 'discovered', post_id = NULL, posted_at = NULL
		WHERE a.config_id = $1
		  AND a.status = 'posted'
		  AND a.post_id IS NOT NULL
		  AND NOT EXISTS (SELECT 1 FROM public.posts p WHERE p.id::text = a.post_id AND p.deleted_at IS NULL AND p.status = 'active')
	`, configID)
	if err != nil {
		return 0, err
	}
	reverted := int(tag.RowsAffected())
	if reverted > 0 {
		log.Info().Int("reverted", reverted).Str("config", configID).Msg("[OfficialAccounts] Reconciled orphaned articles back to discovered")
	}
	return reverted, nil
}

// GetArticleQueue returns articles for a config filtered by status.
// For 'posted' status, only returns articles whose post still exists in the posts table.
func (s *OfficialAccountsService) GetArticleQueue(ctx context.Context, configID string, status string, limit int) ([]CachedArticle, error) {
	if limit <= 0 {
		limit = 50
	}
	orderDir := "DESC"
	if status == "discovered" {
		orderDir = "ASC" // oldest first (next to be posted)
	}

	// For 'posted', reconcile first to catch deleted posts, then query
	if status == "posted" {
		_, _ = s.ReconcilePostedArticles(ctx, configID)
	}

	query := fmt.Sprintf(`
		SELECT a.id, a.config_id, a.guid, a.title, a.link, a.source_name, a.source_url, a.description, a.pub_date,
		       a.status, a.post_id, a.error_message, a.discovered_at, a.posted_at
		FROM official_account_articles a
		WHERE a.config_id = $1 AND a.status = $2
		ORDER BY a.discovered_at %s
		LIMIT $3
	`, orderDir)

	rows, err := s.pool.Query(ctx, query, configID, status, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var articles []CachedArticle
	for rows.Next() {
		var a CachedArticle
		if err := rows.Scan(
			&a.ID, &a.ConfigID, &a.GUID, &a.Title, &a.Link, &a.SourceName, &a.SourceURL,
			&a.Description, &a.PubDate, &a.Status, &a.PostID, &a.ErrorMessage,
			&a.DiscoveredAt, &a.PostedAt,
		); err != nil {
			continue
		}
		articles = append(articles, a)
	}
	return articles, nil
}

// ArticleStats holds counts by status for the admin UI.
type ArticleStats struct {
	Discovered int `json:"discovered"`
	Posted     int `json:"posted"`
	Failed     int `json:"failed"`
	Skipped    int `json:"skipped"`
	Total      int `json:"total"`
}

// GetArticleStats returns article counts by status for a config.
// Reconciles orphaned articles first so counts reflect reality.
func (s *OfficialAccountsService) GetArticleStats(ctx context.Context, configID string) (*ArticleStats, error) {
	// Reconcile first — revert articles whose posts were deleted
	_, _ = s.ReconcilePostedArticles(ctx, configID)

	rows, err := s.pool.Query(ctx, `
		SELECT status, COUNT(*) FROM official_account_articles
		WHERE config_id = $1
		GROUP BY status
	`, configID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	stats := &ArticleStats{}
	for rows.Next() {
		var status string
		var count int
		if err := rows.Scan(&status, &count); err != nil {
			continue
		}
		switch status {
		case "discovered":
			stats.Discovered = count
		case "posted":
			stats.Posted = count
		case "failed":
			stats.Failed = count
		case "skipped":
			stats.Skipped = count
		}
		stats.Total += count
	}
	return stats, nil
}

// FetchNewArticles is a backward-compatible wrapper that discovers articles
// and returns the pending ones. Used by admin handlers.
func (s *OfficialAccountsService) FetchNewArticles(ctx context.Context, configID string) ([]RSSItem, []string, error) {
	// Discover first
	_, _ = s.DiscoverArticles(ctx, configID)

	// Return pending articles as RSSItems
	articles, err := s.GetArticleQueue(ctx, configID, "discovered", 50)
	if err != nil {
		return nil, nil, err
	}

	var items []RSSItem
	var sourceNames []string
	for _, a := range articles {
		items = append(items, RSSItem{
			Title:       a.Title,
			Link:        a.Link,
			Description: a.Description,
			GUID:        a.GUID,
			Source:      RSSSource{URL: a.SourceURL, Name: a.SourceName},
		})
		sourceNames = append(sourceNames, a.SourceName)
	}
	return items, sourceNames, nil
}

// ── AI Post Generation ───────────────────────────────

// GeneratePost creates a post using AI for a given official account config.
// For news accounts, it takes an article and generates a commentary/summary.
// For general accounts, it generates an original post.
func (s *OfficialAccountsService) GeneratePost(ctx context.Context, configID string, article *RSSItem, sourceName string) (string, error) {
	cfg, err := s.GetConfig(ctx, configID)
	if err != nil {
		return "", err
	}

	var userPrompt string
	if article != nil {
		// News mode: generate a post about this article
		desc := article.Description
		// Strip HTML tags from description
		desc = stripHTMLTags(desc)
		if len(desc) > 500 {
			desc = desc[:500] + "..."
		}
		userPrompt = fmt.Sprintf(
			"Write a social media post about this news article. Include the link.\n\nSource: %s\nTitle: %s\nDescription: %s\nLink: %s",
			sourceName, article.Title, desc, article.Link,
		)
	} else {
		// General mode: generate an original post
		userPrompt = "Generate a new social media post. Be creative and engaging."
	}

	generated, err := s.routeGenerateText(ctx, cfg.ModelID, cfg.SystemPrompt, userPrompt, cfg.Temperature, cfg.MaxTokens)
	if err != nil {
		return "", fmt.Errorf("AI generation failed: %w", err)
	}

	return generated, nil
}

// routeGenerateText routes text generation to the local Ollama instance.
// The "local/" prefix is optional — all generation uses local AI.
func (s *OfficialAccountsService) routeGenerateText(ctx context.Context, modelID, systemPrompt, userPrompt string, temperature float64, maxTokens int) (string, error) {
	actualModel := strings.TrimPrefix(modelID, "local/")
	// Also strip legacy "openai/" prefix — route to local model instead
	actualModel = strings.TrimPrefix(actualModel, "openai/")
	return s.generateTextLocal(ctx, actualModel, systemPrompt, userPrompt, temperature, maxTokens)
}

// generateTextLocal sends a chat completion request to the local Ollama instance via the AI gateway.
func (s *OfficialAccountsService) generateTextLocal(ctx context.Context, modelID, systemPrompt, userPrompt string, temperature float64, maxTokens int) (string, error) {
	if s.localAIService == nil {
		return "", fmt.Errorf("local AI service not configured")
	}

	// Call Ollama directly via its OpenAI-compatible endpoint (localhost:11434)
	reqBody := map[string]any{
		"model": modelID,
		"messages": []map[string]string{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": userPrompt},
		},
		"temperature": temperature,
		"stream":      false,
	}
	if maxTokens > 0 {
		reqBody["max_tokens"] = maxTokens
	}

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("marshal error: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", s.ollamaURL+"/v1/chat/completions", bytes.NewReader(jsonBody))
	if err != nil {
		return "", fmt.Errorf("request error: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("local Ollama request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("local Ollama error %d: %s", resp.StatusCode, string(body))
	}

	var chatResp struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&chatResp); err != nil {
		return "", fmt.Errorf("decode error: %w", err)
	}
	if len(chatResp.Choices) == 0 {
		return "", fmt.Errorf("no response from local model")
	}
	return strings.TrimSpace(chatResp.Choices[0].Message.Content), nil
}

// CreatePostForAccount creates a post in the database for the official account
func (s *OfficialAccountsService) CreatePostForAccount(ctx context.Context, configID string, body string, article *RSSItem, sourceName string) (string, error) {
	cfg, err := s.GetConfig(ctx, configID)
	if err != nil {
		return "", err
	}

	// Check daily limit
	if cfg.PostsToday >= cfg.MaxPostsPerDay {
		// Reset if it's a new day
		if time.Since(cfg.PostsTodayResetAt) > 24*time.Hour {
			_, _ = s.pool.Exec(ctx, `UPDATE official_account_configs SET posts_today = 0, posts_today_reset_at = NOW() WHERE id = $1`, configID)
		} else {
			return "", fmt.Errorf("daily post limit reached (%d/%d)", cfg.PostsToday, cfg.MaxPostsPerDay)
		}
	}

	// profile_id IS the author_id (profiles.id = users.id in this schema)
	authorUUID, _ := uuid.Parse(cfg.ProfileID)
	postID := uuid.New()

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		INSERT INTO public.posts (id, author_id, body, status, body_format, is_beacon, allow_chain, visibility, is_nsfw, confidence_score, created_at)
		VALUES ($1, $2, $3, 'active', 'plain', false, true, 'public', false, 1.0, $4)
	`, postID, authorUUID, body, time.Now())
	if err != nil {
		return "", fmt.Errorf("failed to insert post: %w", err)
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO public.post_metrics (post_id, like_count, save_count, view_count, comment_count, updated_at)
		VALUES ($1, 0, 0, 0, 0, $2) ON CONFLICT DO NOTHING
	`, postID, time.Now())
	if err != nil {
		return "", fmt.Errorf("failed to insert post_metrics: %w", err)
	}

	// Track article if this was a news post
	if article != nil {
		// Use GUID (original Google News URL) for dedup tracking, not Link (may be source homepage)
		link := article.GUID
		if link == "" {
			link = article.Link
		}
		postIDStr := postID.String()
		_, _ = tx.Exec(ctx, `
			INSERT INTO official_account_posted_articles (config_id, article_url, article_title, source_name, post_id)
			VALUES ($1, $2, $3, $4, $5)
			ON CONFLICT (config_id, article_url) DO NOTHING
		`, configID, link, article.Title, sourceName, postIDStr)
	}

	// Update counters
	_, _ = tx.Exec(ctx, `
		UPDATE official_account_configs
		SET posts_today = posts_today + 1, last_posted_at = NOW(), updated_at = NOW()
		WHERE id = $1
	`, configID)

	if err := tx.Commit(ctx); err != nil {
		return "", err
	}

	// Fetch and store link preview for posts with URLs (trusted — official account)
	go func() {
		bgCtx := context.Background()
		linkURL := ExtractFirstURL(body)
		if linkURL == "" && article != nil {
			linkURL = article.Link
		}
		if linkURL != "" {
			lp, lpErr := s.linkPreviewService.FetchPreview(bgCtx, linkURL, true)
			if lpErr != nil {
				log.Warn().Err(lpErr).Str("post_id", postID.String()).Str("url", linkURL).Msg("[OfficialAccounts] Link preview fetch failed")
				return
			}
			if lp != nil {
				s.linkPreviewService.ProxyImageToR2(bgCtx, lp)
				if saveErr := s.linkPreviewService.SaveLinkPreview(bgCtx, postID.String(), lp); saveErr != nil {
					log.Warn().Err(saveErr).Str("post_id", postID.String()).Msg("[OfficialAccounts] Link preview save failed")
				} else {
					log.Info().Str("post_id", postID.String()).Str("url", linkURL).Str("title", lp.Title).Msg("[OfficialAccounts] Link preview saved")
				}
			}
		}
	}()

	return postID.String(), nil
}

// CreatePostForArticle creates a post in the database from a pipeline CachedArticle.
// This is the new pipeline version — article status is updated by the caller (PostNextArticle).
func (s *OfficialAccountsService) CreatePostForArticle(ctx context.Context, configID string, body string, article *CachedArticle) (string, error) {
	cfg, err := s.GetConfig(ctx, configID)
	if err != nil {
		return "", err
	}

	// Check daily limit
	if cfg.PostsToday >= cfg.MaxPostsPerDay {
		if time.Since(cfg.PostsTodayResetAt) > 24*time.Hour {
			_, _ = s.pool.Exec(ctx, `UPDATE official_account_configs SET posts_today = 0, posts_today_reset_at = NOW() WHERE id = $1`, configID)
		} else {
			return "", fmt.Errorf("daily post limit reached (%d/%d)", cfg.PostsToday, cfg.MaxPostsPerDay)
		}
	}

	authorUUID, _ := uuid.Parse(cfg.ProfileID)
	postID := uuid.New()

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		INSERT INTO public.posts (id, author_id, body, status, body_format, is_beacon, allow_chain, visibility, is_nsfw, confidence_score, created_at)
		VALUES ($1, $2, $3, 'active', 'plain', false, true, 'public', false, 1.0, $4)
	`, postID, authorUUID, body, time.Now())
	if err != nil {
		return "", fmt.Errorf("failed to insert post: %w", err)
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO public.post_metrics (post_id, like_count, save_count, view_count, comment_count, updated_at)
		VALUES ($1, 0, 0, 0, 0, $2) ON CONFLICT DO NOTHING
	`, postID, time.Now())
	if err != nil {
		return "", fmt.Errorf("failed to insert post_metrics: %w", err)
	}

	// Update counters
	_, _ = tx.Exec(ctx, `
		UPDATE official_account_configs
		SET posts_today = posts_today + 1, last_posted_at = NOW(), updated_at = NOW()
		WHERE id = $1
	`, configID)

	if err := tx.Commit(ctx); err != nil {
		return "", err
	}

	// Fetch and store link preview in background
	go func() {
		bgCtx := context.Background()
		linkURL := ExtractFirstURL(body)
		if linkURL == "" && article != nil {
			linkURL = article.Link
		}
		if linkURL != "" {
			lp, lpErr := s.linkPreviewService.FetchPreview(bgCtx, linkURL, true)
			if lpErr != nil {
				log.Warn().Err(lpErr).Str("post_id", postID.String()).Str("url", linkURL).Msg("[OfficialAccounts] Link preview fetch failed")
				return
			}
			if lp != nil {
				s.linkPreviewService.ProxyImageToR2(bgCtx, lp)
				if saveErr := s.linkPreviewService.SaveLinkPreview(bgCtx, postID.String(), lp); saveErr != nil {
					log.Warn().Err(saveErr).Str("post_id", postID.String()).Msg("[OfficialAccounts] Link preview save failed")
				} else {
					log.Info().Str("post_id", postID.String()).Str("url", linkURL).Str("title", lp.Title).Msg("[OfficialAccounts] Link preview saved")
				}
			}
		}
	}()

	return postID.String(), nil
}

// GenerateAndPost generates an AI post and creates it in the database
func (s *OfficialAccountsService) GenerateAndPost(ctx context.Context, configID string, article *RSSItem, sourceName string) (string, string, error) {
	body, err := s.GeneratePost(ctx, configID, article, sourceName)
	if err != nil {
		return "", "", err
	}

	postID, err := s.CreatePostForAccount(ctx, configID, body, article, sourceName)
	if err != nil {
		return "", "", err
	}

	return postID, body, nil
}

// ── Scheduled Auto-Posting ───────────────────────────

func (s *OfficialAccountsService) StartScheduler() {
	s.wg.Add(1)
	go func() {
		defer s.wg.Done()
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()

		log.Info().Msg("[OfficialAccounts] Scheduler started (5-min tick)")

		for {
			select {
			case <-s.stopCh:
				log.Info().Msg("[OfficialAccounts] Scheduler stopped")
				return
			case <-ticker.C:
				s.runScheduledPosts()
			}
		}
	}()
}

func (s *OfficialAccountsService) StopScheduler() {
	close(s.stopCh)
	s.wg.Wait()
}

func (s *OfficialAccountsService) runScheduledPosts() {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	// Find enabled configs that are due for a post
	rows, err := s.pool.Query(ctx, `
		SELECT id, account_type, post_interval_minutes, last_posted_at, posts_today, max_posts_per_day, posts_today_reset_at
		FROM official_account_configs
		WHERE enabled = true
	`)
	if err != nil {
		log.Error().Err(err).Msg("[OfficialAccounts] Failed to query configs")
		return
	}
	defer rows.Close()

	type candidate struct {
		ID                  string
		AccountType         string
		PostIntervalMinutes int
		LastPostedAt        *time.Time
		PostsToday          int
		MaxPostsPerDay      int
		PostsTodayResetAt   time.Time
	}

	var candidates []candidate
	for rows.Next() {
		var c candidate
		if err := rows.Scan(&c.ID, &c.AccountType, &c.PostIntervalMinutes, &c.LastPostedAt, &c.PostsToday, &c.MaxPostsPerDay, &c.PostsTodayResetAt); err != nil {
			continue
		}
		candidates = append(candidates, c)
	}

	for _, c := range candidates {
		// Reset daily counter if needed
		if time.Since(c.PostsTodayResetAt) > 24*time.Hour {
			_, _ = s.pool.Exec(ctx, `UPDATE official_account_configs SET posts_today = 0, posts_today_reset_at = NOW() WHERE id = $1`, c.ID)
			c.PostsToday = 0
		}

		// Check daily limit
		if c.PostsToday >= c.MaxPostsPerDay {
			continue
		}

		// Check interval
		if c.LastPostedAt != nil && time.Since(*c.LastPostedAt) < time.Duration(c.PostIntervalMinutes)*time.Minute {
			continue
		}

		// Time to post!
		switch c.AccountType {
		case "news", "rss":
			s.scheduleArticlePost(ctx, c.ID)
		default:
			s.scheduleGeneralPost(ctx, c.ID)
		}
	}
}

// scheduleArticlePost handles the two-phase pipeline for news/rss accounts:
// Phase 1: Discover new articles from RSS feeds → cache in DB
// Phase 2: Post the next pending article from the queue
func (s *OfficialAccountsService) scheduleArticlePost(ctx context.Context, configID string) {
	// Phase 1: Discover
	newCount, err := s.DiscoverArticles(ctx, configID)
	if err != nil {
		log.Error().Err(err).Str("config", configID).Msg("[OfficialAccounts] Failed to discover articles")
		// Continue to Phase 2 — there may be previously discovered articles to post
	}

	// Phase 2: Post next pending article
	article, postID, err := s.PostNextArticle(ctx, configID)
	if err != nil {
		log.Error().Err(err).Str("config", configID).Msg("[OfficialAccounts] Failed to post article")
		return
	}
	if article == nil {
		if newCount == 0 {
			log.Debug().Str("config", configID).Msg("[OfficialAccounts] No pending articles to post")
		}
		return
	}

	log.Info().
		Str("config", configID).
		Str("post_id", postID).
		Str("source", article.SourceName).
		Str("title", article.Title).
		Str("link", article.Link).
		Msg("[OfficialAccounts] Article posted")
}

func (s *OfficialAccountsService) scheduleGeneralPost(ctx context.Context, configID string) {
	postID, body, err := s.GenerateAndPost(ctx, configID, nil, "")
	if err != nil {
		log.Error().Err(err).Str("config", configID).Msg("[OfficialAccounts] Failed to generate post")
		return
	}

	log.Info().Str("config", configID).Str("post_id", postID).Msg("[OfficialAccounts] General post created")
	_ = body
}

// ── Article Management ───────────────────────────────

// SkipArticle marks a single article as 'skipped'.
func (s *OfficialAccountsService) SkipArticle(ctx context.Context, articleID string) error {
	tag, err := s.pool.Exec(ctx, `UPDATE official_account_articles SET status = 'skipped' WHERE id = $1 AND status = 'discovered'`, articleID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("article not found or not in discovered state")
	}
	return nil
}

// DeleteArticle permanently removes an article from the pipeline.
func (s *OfficialAccountsService) DeleteArticle(ctx context.Context, articleID string) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM official_account_articles WHERE id = $1`, articleID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("article not found")
	}
	return nil
}

// PostSpecificArticle posts a specific article by its ID (must be 'discovered').
func (s *OfficialAccountsService) PostSpecificArticle(ctx context.Context, articleID string) (*CachedArticle, string, error) {
	var art CachedArticle
	err := s.pool.QueryRow(ctx, `
		SELECT id, config_id, guid, title, link, source_name, source_url, description, pub_date,
		       status, post_id, error_message, discovered_at, posted_at
		FROM official_account_articles
		WHERE id = $1 AND status = 'discovered'
	`, articleID).Scan(
		&art.ID, &art.ConfigID, &art.GUID, &art.Title, &art.Link, &art.SourceName, &art.SourceURL,
		&art.Description, &art.PubDate, &art.Status, &art.PostID, &art.ErrorMessage,
		&art.DiscoveredAt, &art.PostedAt,
	)
	if err != nil {
		return nil, "", fmt.Errorf("article not found or not pending: %w", err)
	}

	cfg, err := s.GetConfig(ctx, art.ConfigID)
	if err != nil {
		return nil, "", err
	}

	// Build the post body
	var body string
	switch cfg.AccountType {
	case "rss":
		body = ""
	case "news":
		rssItem := &RSSItem{Title: art.Title, Link: art.Link, Description: art.Description}
		generated, err := s.GeneratePost(ctx, art.ConfigID, rssItem, art.SourceName)
		if err != nil {
			_, _ = s.pool.Exec(ctx, `UPDATE official_account_articles SET status = 'failed', error_message = $2 WHERE id = $1`, art.ID, err.Error())
			return &art, "", fmt.Errorf("AI generation failed: %w", err)
		}
		body = generated
	default:
		body = art.Title
	}

	postID, err := s.CreatePostForArticle(ctx, art.ConfigID, body, &art)
	if err != nil {
		_, _ = s.pool.Exec(ctx, `UPDATE official_account_articles SET status = 'failed', error_message = $2 WHERE id = $1`, art.ID, err.Error())
		return &art, "", err
	}

	_, _ = s.pool.Exec(ctx, `UPDATE official_account_articles SET status = 'posted', post_id = $2, posted_at = NOW() WHERE id = $1`, art.ID, postID)
	return &art, postID, nil
}

// CleanupPendingByDate skips or deletes all 'discovered' articles older than the given date.
// action must be "skip" or "delete".
func (s *OfficialAccountsService) CleanupPendingByDate(ctx context.Context, configID string, before time.Time, action string) (int, error) {
	var tag pgconn.CommandTag
	var err error

	switch action {
	case "skip":
		tag, err = s.pool.Exec(ctx, `
			UPDATE official_account_articles SET status = 'skipped'
			WHERE config_id = $1 AND status = 'discovered' AND discovered_at < $2
		`, configID, before)
	case "delete":
		tag, err = s.pool.Exec(ctx, `
			DELETE FROM official_account_articles
			WHERE config_id = $1 AND status = 'discovered' AND discovered_at < $2
		`, configID, before)
	default:
		return 0, fmt.Errorf("invalid action: %s (must be 'skip' or 'delete')", action)
	}

	if err != nil {
		return 0, err
	}
	return int(tag.RowsAffected()), nil
}

// ── Recent Articles ──────────────────────────────────

func (s *OfficialAccountsService) GetRecentArticles(ctx context.Context, configID string, limit int) ([]CachedArticle, error) {
	if limit <= 0 {
		limit = 20
	}
	return s.GetArticleQueue(ctx, configID, "posted", limit)
}

// ── Helpers ──────────────────────────────────────────

// StripHTMLTagsPublic is the exported version for use by handlers
func StripHTMLTagsPublic(s string) string {
	return stripHTMLTags(s)
}

func stripHTMLTags(s string) string {
	var result strings.Builder
	inTag := false
	for _, r := range s {
		if r == '<' {
			inTag = true
			continue
		}
		if r == '>' {
			inTag = false
			continue
		}
		if !inTag {
			result.WriteRune(r)
		}
	}
	return strings.TrimSpace(result.String())
}

// OfficialProfile represents a profile with is_official = true
type OfficialProfile struct {
	ProfileID   string  `json:"profile_id"`
	Handle      string  `json:"handle"`
	DisplayName string  `json:"display_name"`
	AvatarURL   string  `json:"avatar_url"`
	Bio         string  `json:"bio"`
	IsVerified  bool    `json:"is_verified"`
	HasConfig   bool    `json:"has_config"`
	ConfigID    *string `json:"config_id,omitempty"`
}

// ListOfficialProfiles returns all profiles where is_official = true,
// along with whether they have an official_account_configs entry
func (s *OfficialAccountsService) ListOfficialProfiles(ctx context.Context) ([]OfficialProfile, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT p.id, p.handle, p.display_name, COALESCE(p.avatar_url, ''),
		       COALESCE(p.bio, ''), COALESCE(p.is_verified, false),
		       c.id AS config_id
		FROM public.profiles p
		LEFT JOIN official_account_configs c ON c.profile_id = p.id
		WHERE p.is_official = true
		ORDER BY p.handle
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var profiles []OfficialProfile
	for rows.Next() {
		var p OfficialProfile
		var configID *string
		if err := rows.Scan(&p.ProfileID, &p.Handle, &p.DisplayName, &p.AvatarURL, &p.Bio, &p.IsVerified, &configID); err != nil {
			continue
		}
		p.ConfigID = configID
		p.HasConfig = configID != nil
		profiles = append(profiles, p)
	}
	return profiles, nil
}

// LookupProfileID finds a profile ID by handle
func (s *OfficialAccountsService) LookupProfileID(ctx context.Context, handle string) (string, error) {
	var id string
	err := s.pool.QueryRow(ctx, `SELECT id FROM public.profiles WHERE handle = $1`, strings.ToLower(handle)).Scan(&id)
	if err != nil {
		if err == pgx.ErrNoRows {
			return "", fmt.Errorf("profile not found: @%s", handle)
		}
		return "", err
	}
	return id, nil
}
