package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/patbritton/sojorn-backend/internal/services"
)

func (h *AdminHandler) GetAltchaChallenge(c *gin.Context) {
	altchaService := services.NewAltchaService(h.jwtSecret) // Use JWT secret as ALTCHA secret for now
	
	challenge, err := altchaService.GenerateChallenge()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate challenge"})
		return
	}

	c.JSON(http.StatusOK, challenge)
}

func (h *AuthHandler) GetAltchaChallenge(c *gin.Context) {
	altchaService := services.NewAltchaService(h.config.JWTSecret)
	
	challenge, err := altchaService.GenerateChallenge()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate challenge"})
		return
	}

	c.JSON(http.StatusOK, challenge)
}
