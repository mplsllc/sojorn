// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package handlers

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/config"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
	"github.com/rs/zerolog/log"
)

type AccountHandler struct {
	repo         *repository.UserRepository
	emailService *services.EmailService
	config       *config.Config
}

func NewAccountHandler(repo *repository.UserRepository, emailService *services.EmailService, cfg *config.Config) *AccountHandler {
	return &AccountHandler{repo: repo, emailService: emailService, config: cfg}
}

// DeactivateAccount sets the user's status to deactivated.
// All data is preserved indefinitely. User can reactivate by logging in.
func (h *AccountHandler) DeactivateAccount(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID := userIDStr.(string)

	user, err := h.repo.GetUserByID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get account"})
		return
	}

	if user.Status == "deactivated" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Account is already deactivated"})
		return
	}

	if err := h.repo.DeactivateUser(c.Request.Context(), userID); err != nil {
		log.Error().Err(err).Str("user_id", userID).Msg("Failed to deactivate account")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to deactivate account"})
		return
	}

	// Revoke all tokens so they're logged out everywhere
	_ = h.repo.RevokeAllUserTokens(c.Request.Context(), userID)

	// Send notification email
	profile, _ := h.repo.GetProfileByID(c.Request.Context(), userID)
	displayName := "there"
	if profile != nil && profile.DisplayName != nil {
		displayName = *profile.DisplayName
	}
	go func() {
		if err := h.sendDeactivationEmail(user.Email, displayName); err != nil {
			log.Error().Err(err).Str("user_id", userID).Msg("Failed to send deactivation email")
		}
	}()

	log.Info().Str("user_id", userID).Msg("Account deactivated")
	c.JSON(http.StatusOK, gin.H{
		"message": "Your account has been deactivated. All your data is preserved. You can reactivate at any time by logging back in.",
		"status":  "deactivated",
	})
}

// DeleteAccount schedules the account for deletion after 14 days.
// During the grace period, the user can cancel by logging back in.
func (h *AccountHandler) DeleteAccount(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID := userIDStr.(string)

	if err := h.repo.ScheduleDeletion(c.Request.Context(), userID); err != nil {
		log.Error().Err(err).Str("user_id", userID).Msg("Failed to schedule account deletion")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to schedule deletion"})
		return
	}

	// Revoke all tokens
	_ = h.repo.RevokeAllUserTokens(c.Request.Context(), userID)

	deletionDate := time.Now().Add(14 * 24 * time.Hour).Format("January 2, 2006")

	// Send notification email
	user, err := h.repo.GetUserByID(c.Request.Context(), userID)
	if err == nil {
		profile, _ := h.repo.GetProfileByID(c.Request.Context(), userID)
		displayName := "there"
		if profile != nil && profile.DisplayName != nil {
			displayName = *profile.DisplayName
		}
		go func() {
			if err := h.sendDeletionScheduledEmail(user.Email, displayName, deletionDate); err != nil {
				log.Error().Err(err).Str("user_id", userID).Msg("Failed to send deletion email")
			}
		}()
	}

	log.Info().Str("user_id", userID).Msg("Account scheduled for deletion in 14 days")
	c.JSON(http.StatusOK, gin.H{
		"message":       fmt.Sprintf("Your account is scheduled for permanent deletion on %s. Log back in before then to cancel. After that date, all data will be irreversibly destroyed.", deletionDate),
		"status":        "pending_deletion",
		"deletion_date": deletionDate,
	})
}

// RequestImmediateDestroy initiates the super-delete flow.
// Sends a confirmation email with a one-time token. Nothing is deleted yet.
func (h *AccountHandler) RequestImmediateDestroy(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID := userIDStr.(string)

	user, err := h.repo.GetUserByID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get account"})
		return
	}

	profile, _ := h.repo.GetProfileByID(c.Request.Context(), userID)
	displayName := "there"
	if profile != nil && profile.DisplayName != nil {
		displayName = *profile.DisplayName
	}

	// Generate a secure one-time token
	rawToken, err := generateDestroyToken()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate confirmation token"})
		return
	}

	hash := sha256.Sum256([]byte(rawToken))
	hashString := hex.EncodeToString(hash[:])

	// Store as auth_token with type 'destroy_confirm', expires in 1 hour
	if err := h.repo.CreateVerificationToken(c.Request.Context(), hashString, userID, 1*time.Hour); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to store confirmation token"})
		return
	}

	// Send the confirmation email with strong language
	go func() {
		if err := h.sendDestroyConfirmationEmail(user.Email, displayName, rawToken); err != nil {
			log.Error().Err(err).Str("user_id", userID).Msg("Failed to send destroy confirmation email")
		}
	}()

	log.Warn().Str("user_id", userID).Msg("Immediate destroy requested — confirmation email sent")
	c.JSON(http.StatusOK, gin.H{
		"message": "A confirmation email has been sent. You must click the link in that email to permanently and immediately destroy your account. This action cannot be undone.",
	})
}

// ConfirmImmediateDestroy is the endpoint hit from the email confirmation link.
// It verifies the token and permanently purges all user data.
func (h *AccountHandler) ConfirmImmediateDestroy(c *gin.Context) {
	token := c.Query("token")
	if token == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Missing confirmation token"})
		return
	}

	hash := sha256.Sum256([]byte(token))
	hashString := hex.EncodeToString(hash[:])

	userID, expiresAt, err := h.repo.GetVerificationToken(c.Request.Context(), hashString)
	if err != nil {
		c.Redirect(http.StatusFound, h.config.AppBaseURL+"/verify-error?reason=invalid")
		return
	}

	if time.Now().After(expiresAt) {
		_ = h.repo.DeleteVerificationToken(c.Request.Context(), hashString)
		c.Redirect(http.StatusFound, h.config.AppBaseURL+"/verify-error?reason=expired")
		return
	}

	// Clean up the token
	_ = h.repo.DeleteVerificationToken(c.Request.Context(), hashString)

	// Revoke all tokens first
	_ = h.repo.RevokeAllUserTokens(c.Request.Context(), userID)

	// CASCADE PURGE — point of no return
	if err := h.repo.CascadePurgeUser(c.Request.Context(), userID); err != nil {
		log.Error().Err(err).Str("user_id", userID).Msg("CRITICAL: Cascade purge failed")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Account destruction failed. Please contact support."})
		return
	}

	log.Warn().Str("user_id", userID).Msg("ACCOUNT DESTROYED — all data permanently purged")

	c.Redirect(http.StatusFound, h.config.AppBaseURL+"/destroyed")
}

// GetAccountStatus returns the current account lifecycle status
func (h *AccountHandler) GetAccountStatus(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID := userIDStr.(string)

	user, err := h.repo.GetUserByID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get account"})
		return
	}

	result := gin.H{
		"status": user.Status,
	}

	if user.DeletedAt != nil {
		result["deletion_scheduled"] = user.DeletedAt.Format(time.RFC3339)
	}

	c.JSON(http.StatusOK, result)
}

// CancelDeletion allows a user to cancel a pending deletion
func (h *AccountHandler) CancelDeletion(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID := userIDStr.(string)

	user, err := h.repo.GetUserByID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get account"})
		return
	}

	if string(user.Status) != "pending_deletion" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Account is not pending deletion"})
		return
	}

	if err := h.repo.CancelDeletion(c.Request.Context(), userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to cancel deletion"})
		return
	}

	log.Info().Str("user_id", userID).Msg("Account deletion cancelled, reactivated")
	c.JSON(http.StatusOK, gin.H{
		"message": "Deletion cancelled. Your account is active again.",
		"status":  "active",
	})
}

// --- helpers ---

func generateDestroyToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func (h *AccountHandler) sendDeactivationEmail(toEmail, toName string) error {
	return h.emailService.SendDeactivationEmail(toEmail, toName)
}

func (h *AccountHandler) sendDeletionScheduledEmail(toEmail, toName, deletionDate string) error {
	return h.emailService.SendDeletionScheduledEmail(toEmail, toName, deletionDate)
}

func (h *AccountHandler) sendDestroyConfirmationEmail(toEmail, toName, token string) error {
	confirmURL := fmt.Sprintf("%s/api/v1/account/destroy/confirm?token=%s",
		h.config.APIBaseURL, token)
	return h.emailService.SendDestroyConfirmationEmail(toEmail, toName, confirmURL)
}
