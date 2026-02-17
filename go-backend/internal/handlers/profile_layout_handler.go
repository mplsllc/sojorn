package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

type ProfileLayoutHandler struct {
	db *pgxpool.Pool
}

func NewProfileLayoutHandler(db *pgxpool.Pool) *ProfileLayoutHandler {
	return &ProfileLayoutHandler{db: db}
}

// GetProfileLayout — GET /profile/layout
func (h *ProfileLayoutHandler) GetProfileLayout(c *gin.Context) {
	userID, _ := c.Get("user_id")
	userIDStr := userID.(string)

	var widgetsJSON []byte
	var theme string
	var accentColor, bannerImageURL *string
	var updatedAt time.Time

	err := h.db.QueryRow(c.Request.Context(), `
		SELECT widgets, theme, accent_color, banner_image_url, updated_at
		FROM profile_layouts
		WHERE user_id = $1
	`, userIDStr).Scan(&widgetsJSON, &theme, &accentColor, &bannerImageURL, &updatedAt)

	if err != nil {
		// No layout yet — return empty default
		c.JSON(http.StatusOK, gin.H{
			"widgets":          []interface{}{},
			"theme":            "default",
			"accent_color":     nil,
			"banner_image_url": nil,
			"updated_at":       time.Now().Format(time.RFC3339),
		})
		return
	}

	var widgets interface{}
	if err := json.Unmarshal(widgetsJSON, &widgets); err != nil {
		widgets = []interface{}{}
	}

	c.JSON(http.StatusOK, gin.H{
		"widgets":          widgets,
		"theme":            theme,
		"accent_color":     accentColor,
		"banner_image_url": bannerImageURL,
		"updated_at":       updatedAt.Format(time.RFC3339),
	})
}

// SaveProfileLayout — PUT /profile/layout
func (h *ProfileLayoutHandler) SaveProfileLayout(c *gin.Context) {
	userID, _ := c.Get("user_id")
	userIDStr := userID.(string)

	var req struct {
		Widgets         interface{} `json:"widgets"`
		Theme           string      `json:"theme"`
		AccentColor     *string     `json:"accent_color"`
		BannerImageURL  *string     `json:"banner_image_url"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Theme == "" {
		req.Theme = "default"
	}

	widgetsJSON, err := json.Marshal(req.Widgets)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid widgets format"})
		return
	}

	now := time.Now()
	_, err = h.db.Exec(c.Request.Context(), `
		INSERT INTO profile_layouts (user_id, widgets, theme, accent_color, banner_image_url, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (user_id) DO UPDATE SET
			widgets          = EXCLUDED.widgets,
			theme            = EXCLUDED.theme,
			accent_color     = EXCLUDED.accent_color,
			banner_image_url = EXCLUDED.banner_image_url,
			updated_at       = EXCLUDED.updated_at
	`, userIDStr, widgetsJSON, req.Theme, req.AccentColor, req.BannerImageURL, now)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save layout"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"widgets":          req.Widgets,
		"theme":            req.Theme,
		"accent_color":     req.AccentColor,
		"banner_image_url": req.BannerImageURL,
		"updated_at":       now.Format(time.RFC3339),
	})
}
