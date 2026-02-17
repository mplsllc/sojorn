package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
)

type AnalysisHandler struct{}

func NewAnalysisHandler() *AnalysisHandler {
	return &AnalysisHandler{}
}

func (h *AnalysisHandler) CheckTone(c *gin.Context) {
	var req models.ToneCheckRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}

	// Basic native Go logic for tone analysis
	// We can expand this with AI models or sentiment libraries later
	result := models.ToneCheckResult{
		Flagged:  false,
		Category: nil,
		Flags:    []string{},
		Reason:   "Content analyzed and found safe.",
	}

	// Example: Simple keyword check
	forbidden := []string{"badword1", "badword2"}
	for _, word := range forbidden {
		if strings.Contains(strings.ToLower(req.Text), word) {
			result.Flagged = true
			category := "offensive"
			result.Category = &category
			result.Flags = append(result.Flags, "toxic")
			result.Reason = "Content contains restricted language."
			break
		}
	}

	c.JSON(http.StatusOK, result)
}
