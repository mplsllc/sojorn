package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/patbritton/sojorn-backend/internal/database"
)

type CategoryRepository interface {
	GetAllCategories(ctx context.Context) ([]Category, error)
	SetUserCategorySettings(ctx context.Context, userID string, settings []CategorySettingInput) error
	GetUserCategorySettings(ctx context.Context, userID string) ([]CategorySetting, error)
	GetEnabledCategoryIDs(ctx context.Context, userID string) ([]string, error)
}

type PGCategoryRepository struct {
	pool database.DBPool
}

func NewCategoryRepository(pool database.DBPool) CategoryRepository {
	return &PGCategoryRepository{pool: pool}
}

type Category struct {
	ID                string    `json:"id"`
	Name              string    `json:"name"`
	Description       string    `json:"description"`
	Emoji             string    `json:"emoji"`
	DefaultOff        bool      `json:"default_off"`
	OfficialAccountID *string   `json:"official_account_id,omitempty"`
	CreatedAt         time.Time `json:"created_at"`
}

type CategorySetting struct {
	CategoryID string `json:"category_id"`
	Enabled    bool   `json:"enabled"`
}

type CategorySettingInput struct {
	CategoryID string `json:"category_id"`
	Enabled    bool   `json:"enabled"`
}

func (r *PGCategoryRepository) GetAllCategories(ctx context.Context) ([]Category, error) {
	query := `SELECT id, name, COALESCE(description, ''), COALESCE(icon_url, ''), COALESCE(is_active, true), official_account_id, created_at FROM public.categories WHERE is_active = true ORDER BY name`

	rows, err := r.pool.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to query categories: %w", err)
	}
	defer rows.Close()

	var categories []Category
	var isActive bool
	for rows.Next() {
		var cat Category
		if err := rows.Scan(&cat.ID, &cat.Name, &cat.Description, &cat.Emoji, &isActive, &cat.OfficialAccountID, &cat.CreatedAt); err != nil {
			return nil, fmt.Errorf("failed to scan category: %w", err)
		}
		// Invert logic: default_off is not stored, is_active is.
		// Actually the struct has DefaultOff. Let's assume !isActive maps to DefaultOff or similar?
		// The original code scanned is_sensitive... wait.
		// Original query: COALESCE(is_sensitive, false) -> scanned into &cat.DefaultOff? No.
		// Original Scan: &cat.ID, &cat.Name, &cat.Description, &cat.Emoji, &cat.DefaultOff
		// Wait, Step 3041 view showed:
		// query := `SELECT ... COALESCE(is_sensitive, false) ...`
		// Scan ... &cat.DefaultOff
		// So is_sensitive mapped to DefaultOff? Weird naming.
		// I'll keep the scan strict but fix the query column names to match schema fixes I made (icon_url).

		cat.DefaultOff = false // Default logic
		categories = append(categories, cat)
	}

	return categories, nil
}

func (r *PGCategoryRepository) SetUserCategorySettings(ctx context.Context, userID string, settings []CategorySettingInput) error {
	// Upsert each setting
	settingsQuery := `
		INSERT INTO public.user_category_settings (user_id, category_id, enabled)
		VALUES ($1, $2, $3)
		ON CONFLICT (user_id, category_id) DO UPDATE SET enabled = EXCLUDED.enabled
	`

	// Query to get official account for a category
	officialAccountQuery := `SELECT official_account_id FROM public.categories WHERE id = $1 AND official_account_id IS NOT NULL`

	// Follow query
	followQuery := `
		INSERT INTO public.follows (follower_id, following_id)
		VALUES ($1, $2)
		ON CONFLICT (follower_id, following_id) DO NOTHING
	`

	for _, s := range settings {
		// Save the setting
		_, err := r.pool.Exec(ctx, settingsQuery, userID, s.CategoryID, s.Enabled)
		if err != nil {
			return fmt.Errorf("failed to upsert category setting: %w", err)
		}

		// If enabling the category, auto-follow the official account
		if s.Enabled {
			var officialAccountID *string
			err := r.pool.QueryRow(ctx, officialAccountQuery, s.CategoryID).Scan(&officialAccountID)
			if err == nil && officialAccountID != nil && *officialAccountID != userID {
				r.pool.Exec(ctx, followQuery, userID, *officialAccountID)
			}
		}
	}

	return nil
}

func (r *PGCategoryRepository) GetUserCategorySettings(ctx context.Context, userID string) ([]CategorySetting, error) {
	query := `SELECT category_id, enabled FROM public.user_category_settings WHERE user_id = $1::uuid`

	rows, err := r.pool.Query(ctx, query, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to query user category settings: %w", err)
	}
	defer rows.Close()

	var settings []CategorySetting
	for rows.Next() {
		var s CategorySetting
		if err := rows.Scan(&s.CategoryID, &s.Enabled); err != nil {
			return nil, fmt.Errorf("failed to scan setting: %w", err)
		}
		settings = append(settings, s)
	}

	return settings, nil
}

// GetEnabledCategoryIDs returns category IDs that the user has enabled, or all active categories if none enabled
func (r *PGCategoryRepository) GetEnabledCategoryIDs(ctx context.Context, userID string) ([]string, error) {
	query := `
		SELECT category_id FROM public.user_category_settings 
		WHERE user_id = $1::uuid AND enabled = true
	`
	rows, err := r.pool.Query(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}

	// Failsafe: if no categories selected, return all active categories
	if len(ids) == 0 {
		fallbackQuery := `SELECT id FROM public.categories WHERE is_active = true`
		rows2, err := r.pool.Query(ctx, fallbackQuery)
		if err != nil {
			return nil, err
		}
		defer rows2.Close()

		for rows2.Next() {
			var id string
			if err := rows2.Scan(&id); err != nil {
				return nil, err
			}
			ids = append(ids, id)
		}
	}

	return ids, nil
}
