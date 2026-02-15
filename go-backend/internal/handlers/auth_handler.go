package handlers

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"net/http"
	"time"

	"log"

	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/patbritton/sojorn-backend/internal/config"
	"github.com/patbritton/sojorn-backend/internal/models"
	"github.com/patbritton/sojorn-backend/internal/repository"
	"github.com/patbritton/sojorn-backend/internal/services"
	"golang.org/x/crypto/bcrypt"
)

type AuthHandler struct {
	repo             *repository.UserRepository
	config           *config.Config
	emailService     *services.EmailService
	sendPulseService *services.SendPulseService
}

func NewAuthHandler(repo *repository.UserRepository, cfg *config.Config, emailService *services.EmailService, sendPulseService *services.SendPulseService) *AuthHandler {
	return &AuthHandler{repo: repo, config: cfg, emailService: emailService, sendPulseService: sendPulseService}
}

type RegisterRequest struct {
	Email           string `json:"email" binding:"required,email"`
	Password        string `json:"password" binding:"required,min=6"`
	Handle          string `json:"handle" binding:"required,min=3"`
	DisplayName     string `json:"display_name" binding:"required"`
	TurnstileToken  string `json:"turnstile_token" binding:"required"`
	AcceptTerms     bool   `json:"accept_terms" binding:"required,eq=true"`
	AcceptPrivacy   bool   `json:"accept_privacy" binding:"required,eq=true"`
	EmailNewsletter bool   `json:"email_newsletter"`
	EmailContact    bool   `json:"email_contact"`
	BirthMonth      int    `json:"birth_month" binding:"required,min=1,max=12"`
	BirthYear       int    `json:"birth_year" binding:"required,min=1900,max=2025"`
}

type LoginRequest struct {
	Email          string `json:"email" binding:"required,email"`
	Password       string `json:"password" binding:"required"`
	TurnstileToken string `json:"turnstile_token" binding:"required"`
}

func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))

	// Validate Turnstile token
	turnstileService := services.NewTurnstileService(h.config.TurnstileSecretKey)
	remoteIP := c.ClientIP()
	turnstileResp, err := turnstileService.VerifyToken(req.TurnstileToken, remoteIP)
	if err != nil {
		log.Printf("[Auth] Turnstile verification failed: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "Security verification failed"})
		return
	}

	if !turnstileResp.Success {
		errorMsg := turnstileService.GetErrorMessage(turnstileResp.ErrorCodes)
		log.Printf("[Auth] Turnstile validation failed: %s", errorMsg)
		c.JSON(http.StatusBadRequest, gin.H{"error": errorMsg})
		return
	}

	// Check if this IP is banned (ban evasion prevention)
	ipBanned, _ := h.repo.IsIPBanned(c.Request.Context(), remoteIP)
	if ipBanned {
		log.Printf("[Auth] Registration blocked for banned IP: %s", remoteIP)
		c.JSON(http.StatusForbidden, gin.H{"error": "Registration is not available from this network."})
		return
	}

	// Validate handle against reserved names and inappropriate content
	handleCheck := services.ValidateUsernameWithDB(c.Request.Context(), h.repo.Pool(), req.Handle)
	if handleCheck.Violation != services.UsernameOK {
		status := http.StatusBadRequest
		if handleCheck.Violation == services.UsernameReserved {
			status = http.StatusForbidden
		}
		c.JSON(status, gin.H{"error": handleCheck.Message})
		return
	}

	// Validate display name for inappropriate content
	nameCheck := services.ValidateDisplayName(req.DisplayName)
	if nameCheck.Violation != services.UsernameOK {
		c.JSON(http.StatusBadRequest, gin.H{"error": nameCheck.Message})
		return
	}

	existingUser, err := h.repo.GetUserByEmail(c.Request.Context(), req.Email)
	if err == nil && existingUser != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "Email already registered"})
		return
	}

	existingProfile, err := h.repo.GetProfileByHandle(c.Request.Context(), req.Handle)
	if err == nil && existingProfile != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "Handle already taken"})
		return
	}

	hashedBytes, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to hash password"})
		return
	}

	userID := uuid.New()
	user := &models.User{
		ID:              userID,
		Email:           req.Email,
		PasswordHash:    string(hashedBytes),
		Status:          models.UserStatusPending,
		MFAEnabled:      false,
		EmailNewsletter: req.EmailNewsletter,
		EmailContact:    req.EmailContact,
		CreatedAt:       time.Now(),
		UpdatedAt:       time.Now(),
	}

	log.Printf("[Auth] Registering user: %s", req.Email)
	if err := h.repo.CreateUser(c.Request.Context(), user); err != nil {
		log.Printf("[Auth] Failed to create user %s: %v", req.Email, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create user: " + err.Error()})
		return
	}

	profile := &models.Profile{
		ID:          userID,
		Handle:      &req.Handle,
		DisplayName: &req.DisplayName,
		BirthMonth:  req.BirthMonth,
		BirthYear:   req.BirthYear,
	}
	if err := h.repo.CreateProfile(c.Request.Context(), profile); err != nil {
		log.Printf("[Auth] Failed to create profile for %s: %v. Rolling back user.", user.ID, err)
		_ = h.repo.DeleteUser(c.Request.Context(), user.ID)

		if strings.Contains(err.Error(), "23505") && strings.Contains(err.Error(), "profiles_handle_key") {
			c.JSON(http.StatusConflict, gin.H{"error": "Handle already taken"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create profile", "details": err.Error()})
		return
	}

	rawToken, _ := generateRandomString(32)
	tokenHash := sha256.Sum256([]byte(rawToken))
	hashString := hex.EncodeToString(tokenHash[:])

	if err := h.repo.CreateVerificationToken(c.Request.Context(), hashString, userID.String(), 24*time.Hour); err != nil {
		log.Printf("[Auth] Failed to store verification token: %v. Rolling back user.", err)
		_ = h.repo.DeleteUser(c.Request.Context(), user.ID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to prepare verification", "details": err.Error()})
		return
	}

	go func() {
		if err := h.emailService.SendVerificationEmail(req.Email, req.DisplayName, rawToken); err != nil {
			log.Printf("[Auth] Failed to send email to %s: %v", req.Email, err)
		}
	}()

	// Add to SendPulse Members list if user opted into newsletter
	if req.EmailNewsletter && h.sendPulseService != nil {
		go h.sendPulseService.AddToMembers(req.Email)
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Registration successful. Please verify your email to activate your account.",
		"state":   "verification_pending",
		"email":   req.Email,
	})
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))

	// Validate Turnstile token
	turnstileService := services.NewTurnstileService(h.config.TurnstileSecretKey)
	remoteIP := c.ClientIP()
	turnstileResp, err := turnstileService.VerifyToken(req.TurnstileToken, remoteIP)
	if err != nil {
		log.Printf("[Auth] Login Turnstile verification failed: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "Security verification failed"})
		return
	}

	if !turnstileResp.Success {
		errorMsg := turnstileService.GetErrorMessage(turnstileResp.ErrorCodes)
		log.Printf("[Auth] Login Turnstile validation failed: %s", errorMsg)
		c.JSON(http.StatusBadRequest, gin.H{"error": errorMsg})
		return
	}

	// Check if this IP is banned (ban evasion prevention)
	ipBanned, _ := h.repo.IsIPBanned(c.Request.Context(), remoteIP)
	if ipBanned {
		log.Printf("[Auth] Login blocked for banned IP: %s", remoteIP)
		c.JSON(http.StatusForbidden, gin.H{"error": "Access is not available from this network."})
		return
	}

	user, err := h.repo.GetUserByEmail(c.Request.Context(), req.Email)
	if err != nil {
		log.Printf("[Auth] Login failed for %s: user not found", req.Email)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		log.Printf("[Auth] Login failed for %s: password mismatch", req.Email)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		return
	}

	// Age gate: check if user is under 16
	var profile *models.Profile
	profile, _ = h.repo.GetProfileByID(c.Request.Context(), user.ID.String())
	if profile != nil && profile.BirthYear > 0 {
		now := time.Now()
		age := now.Year() - profile.BirthYear
		if int(now.Month()) < profile.BirthMonth {
			age--
		}
		if age < 16 {
			log.Printf("[Auth] Login blocked for underage user %s (age %d)", req.Email, age)
			c.JSON(http.StatusForbidden, gin.H{
				"error": "You must be at least 16 years old to use Sojorn. Please come back when you're older!",
				"code":  "age_restricted",
			})
			return
		}
	}

	if user.Status == models.UserStatusPending {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Email verification required", "code": "verify_email"})
		return
	}
	if user.Status == models.UserStatusBanned {
		c.JSON(http.StatusForbidden, gin.H{"error": "This account has been permanently suspended for violating our community guidelines.", "code": "banned"})
		return
	}
	if user.Status == models.UserStatusSuspended {
		c.JSON(http.StatusForbidden, gin.H{"error": "Your account is temporarily suspended. Please try again later.", "code": "suspended"})
		return
	}

	// Auto-reactivate deactivated or pending-deletion accounts on login
	var reactivated bool
	var previousStatus string
	if user.Status == models.UserStatusDeactivated || user.Status == models.UserStatusPendingDeletion {
		previousStatus = string(user.Status)
		log.Printf("[Auth] Reactivating %s account for %s", user.Status, req.Email)
		_ = h.repo.ReactivateUser(c.Request.Context(), user.ID.String())
		user.Status = models.UserStatusActive
		reactivated = true

		// Send reactivation confirmation email
		displayName := req.Email
		if p, _ := h.repo.GetProfileByID(c.Request.Context(), user.ID.String()); p != nil && p.DisplayName != nil && *p.DisplayName != "" {
			displayName = *p.DisplayName
		}
		go func() {
			var note string
			if previousStatus == "pending_deletion" {
				note = "Your scheduled account deletion has been cancelled."
			} else {
				note = "Your account has been reactivated and is fully visible again."
			}
			_ = h.emailService.SendAccountRestoredEmail(req.Email, displayName, note)
		}()
	}

	if user.MFAEnabled {
		tempToken, _ := generateRandomString(32)
		c.JSON(http.StatusOK, gin.H{
			"mfa_required": true,
			"user_id":      user.ID,
			"temp_token":   tempToken,
		})
		return
	}

	_ = h.repo.UpdateLastLogin(c.Request.Context(), user.ID.String())

	token, err := h.generateToken(user.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token", "details": err.Error()})
		return
	}

	refreshToken, _ := generateRandomString(32)
	_ = h.repo.StoreRefreshToken(c.Request.Context(), user.ID.String(), refreshToken, 30*24*time.Hour)

	// Re-fetch profile if not already loaded from age check
	if profile == nil {
		profile, _ = h.repo.GetProfileByID(c.Request.Context(), user.ID.String())
	}
	if profile == nil {
		log.Printf("[Auth] Failed to get profile for %s", user.ID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch profile"})
		return
	}

	response := gin.H{
		"token":         token,
		"access_token":  token,
		"refresh_token": refreshToken,
		"user":          user,
		"profile":       profile, // Includes HasCompletedOnboarding
	}
	if reactivated {
		response["reactivated"] = true
		response["previous_status"] = previousStatus
	}
	c.JSON(http.StatusOK, response)
}

func (h *AuthHandler) CompleteOnboarding(c *gin.Context) {
	userId := c.MustGet("user_id").(string)

	if err := h.repo.MarkOnboardingComplete(c.Request.Context(), userId); err != nil {
		log.Printf("[Auth] Failed to complete onboarding for %s: %v", userId, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update onboarding status", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Onboarding completed"})
}

func (h *AuthHandler) VerifyEmail(c *gin.Context) {
	rawToken := c.Query("token")
	if rawToken == "" {
		c.Redirect(http.StatusFound, h.config.AppBaseURL+"/verify-error?reason=invalid_token")
		return
	}

	tokenHash := sha256.Sum256([]byte(rawToken))
	hashString := hex.EncodeToString(tokenHash[:])

	userID, expiresAt, err := h.repo.GetVerificationToken(c.Request.Context(), hashString)
	if err != nil {
		c.Redirect(http.StatusFound, h.config.AppBaseURL+"/verify-error?reason=invalid_token")
		return
	}

	if time.Now().After(expiresAt) {
		h.repo.DeleteVerificationToken(c.Request.Context(), hashString)
		c.Redirect(http.StatusFound, h.config.AppBaseURL+"/verify-error?reason=expired")
		return
	}

	// Activate user
	if err := h.repo.UpdateUserStatus(c.Request.Context(), userID, models.UserStatusActive); err != nil {
		c.Redirect(http.StatusFound, h.config.AppBaseURL+"/verify-error?reason=server_error")
		return
	}

	// Add to Subscriber list
	go func() {
		user, err := h.repo.GetUserByID(c.Request.Context(), userID)
		if err == nil {
			profile, _ := h.repo.GetProfileByID(c.Request.Context(), userID)
			name := ""
			if profile != nil && profile.DisplayName != nil {
				name = *profile.DisplayName
			}
			h.emailService.AddSubscriber(user.Email, name)
		}
	}()

	// Cleanup
	_ = h.repo.DeleteVerificationToken(c.Request.Context(), hashString)

	c.Redirect(http.StatusFound, h.config.AppBaseURL+"/verified?status=success")
}

func (h *AuthHandler) ResendVerificationEmail(c *gin.Context) {
	var req struct {
		Email string `json:"email" binding:"required,email"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.repo.GetUserByEmail(c.Request.Context(), req.Email)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"message": "If the account exists and is not verified, a new link has been sent."})
		return
	}

	if user.Status != models.UserStatusPending {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Account is already verified"})
		return
	}

	rawToken, _ := generateRandomString(32)
	tokenHash := sha256.Sum256([]byte(rawToken))
	hashString := hex.EncodeToString(tokenHash[:])

	if err := h.repo.CreateVerificationToken(c.Request.Context(), hashString, user.ID.String(), 24*time.Hour); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to prepare verification", "details": err.Error()})
		return
	}

	go func() {
		name := ""
		profile, err := h.repo.GetProfileByID(c.Request.Context(), user.ID.String())
		if err == nil && profile != nil && profile.DisplayName != nil {
			name = *profile.DisplayName
		}
		if err := h.emailService.SendVerificationEmail(user.Email, name, rawToken); err != nil {
			log.Printf("[Auth] Failed to send email to %s: %v", user.Email, err)
		}
	}()

	log.Printf("[Auth] Resent Verification Token for %s: %s", user.Email, rawToken)

	c.JSON(http.StatusOK, gin.H{
		"message": "A new verification link has been sent.",
		"state":   "verification_pending",
	})
}

func (h *AuthHandler) RefreshSession(c *gin.Context) {
	var req struct {
		RefreshToken string `json:"refresh_token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Refresh token required"})
		return
	}

	rt, err := h.repo.ValidateRefreshToken(c.Request.Context(), req.RefreshToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired session"})
		return
	}

	// Check if user is banned/suspended before issuing new tokens
	rtUser, err := h.repo.GetUserByID(c.Request.Context(), rt.UserID.String())
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not found"})
		return
	}
	if rtUser.Status == models.UserStatusBanned {
		_ = h.repo.RevokeAllUserTokens(c.Request.Context(), rt.UserID.String())
		c.JSON(http.StatusForbidden, gin.H{"error": "This account has been permanently suspended.", "code": "banned"})
		return
	}
	if rtUser.Status == models.UserStatusSuspended {
		c.JSON(http.StatusForbidden, gin.H{"error": "Your account is temporarily suspended.", "code": "suspended"})
		return
	}

	_ = h.repo.RevokeRefreshToken(c.Request.Context(), req.RefreshToken)

	newAccessToken, err := h.generateToken(rt.UserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token", "details": err.Error()})
		return
	}

	newRefreshToken, _ := generateRandomString(32)
	err = h.repo.StoreRefreshToken(c.Request.Context(), rt.UserID.String(), newRefreshToken, 30*24*time.Hour)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save session", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, models.TokenPair{
		AccessToken:  newAccessToken,
		RefreshToken: newRefreshToken,
	})
}

func (h *AuthHandler) generateToken(userID uuid.UUID) (string, error) {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":  userID.String(),
		"exp":  time.Now().Add(time.Hour * 24 * 7).Unix(), // 7 days (Access token life)
		"role": "authenticated",
	})
	return token.SignedString([]byte(h.config.JWTSecret))
}

func generateRandomString(n int) (string, error) {
	b := make([]byte, n)
	_, err := rand.Read(b)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func (h *AuthHandler) ForgotPassword(c *gin.Context) {
	var req struct {
		Email string `json:"email" binding:"required,email"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.repo.GetUserByEmail(c.Request.Context(), req.Email)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"message": "If the account exists, a password reset link has been sent."})
		return
	}

	rawToken, _ := generateRandomString(32)
	tokenHash := sha256.Sum256([]byte(rawToken))
	hashString := hex.EncodeToString(tokenHash[:])

	if err := h.repo.CreatePasswordResetToken(c.Request.Context(), hashString, user.ID.String(), 1*time.Hour); err != nil {
		log.Printf("[Auth] Failed to create reset token: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"message": "Internal error", "details": err.Error()})
		return
	}

	go func() {
		name := ""
		profile, err := h.repo.GetProfileByID(c.Request.Context(), user.ID.String())
		if err == nil && profile != nil && profile.DisplayName != nil {
			name = *profile.DisplayName
		}
		if err := h.emailService.SendPasswordResetEmail(user.Email, name, rawToken); err != nil {
			log.Printf("[Auth] Failed to send reset email to %s: %v", user.Email, err)
		}
	}()

	c.JSON(http.StatusOK, gin.H{"message": "If the account exists, a password reset link has been sent."})
}

func (h *AuthHandler) ResetPassword(c *gin.Context) {
	var req struct {
		Token       string `json:"token" binding:"required"`
		NewPassword string `json:"new_password" binding:"required,min=6"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tokenHash := sha256.Sum256([]byte(req.Token))
	hashString := hex.EncodeToString(tokenHash[:])

	userID, expiresAt, err := h.repo.GetPasswordResetToken(c.Request.Context(), hashString)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Invalid or expired token"})
		return
	}

	if time.Now().After(expiresAt) {
		h.repo.DeletePasswordResetToken(c.Request.Context(), hashString)
		c.JSON(http.StatusBadRequest, gin.H{"error": "Token expired"})
		return
	}

	hashedBytes, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to reset password"})
		return
	}

	if err := h.repo.UpdateUserPassword(c.Request.Context(), userID, string(hashedBytes)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update password", "details": err.Error()})
		return
	}

	_ = h.repo.DeletePasswordResetToken(c.Request.Context(), hashString)

	c.JSON(http.StatusOK, gin.H{"message": "Password reset successfully"})
}
