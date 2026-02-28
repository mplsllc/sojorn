// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package handlers

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"net/http"
	"sync"
	"time"

	"strings"

	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog/log"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/config"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
	"golang.org/x/crypto/bcrypt"
)

type AuthHandler struct {
	repo             *repository.UserRepository
	config           *config.Config
	emailService     *services.EmailService
	sendPulseService *services.SendPulseService
	mfaRepo          *repository.MFARepository
	totpService      *services.TOTPService
	mfaTokens        *mfaTempStore
}

// mfaTempStore holds short-lived tokens for the MFA verification step.
type mfaTempStore struct {
	mu    sync.Mutex
	store map[string]mfaTempEntry // keyed by temp_token
}

type mfaTempEntry struct {
	userID    uuid.UUID
	expiresAt time.Time
}

func newMFATempStore() *mfaTempStore {
	s := &mfaTempStore{store: make(map[string]mfaTempEntry)}
	go s.cleanup()
	return s
}

func (s *mfaTempStore) Set(token string, userID uuid.UUID) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.store[token] = mfaTempEntry{userID: userID, expiresAt: time.Now().Add(5 * time.Minute)}
}

func (s *mfaTempStore) Get(token string) (uuid.UUID, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	entry, ok := s.store[token]
	if !ok || time.Now().After(entry.expiresAt) {
		delete(s.store, token)
		return uuid.Nil, false
	}
	return entry.userID, true
}

func (s *mfaTempStore) Delete(token string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.store, token)
}

func (s *mfaTempStore) cleanup() {
	ticker := time.NewTicker(time.Minute)
	for range ticker.C {
		s.mu.Lock()
		now := time.Now()
		for k, v := range s.store {
			if now.After(v.expiresAt) {
				delete(s.store, k)
			}
		}
		s.mu.Unlock()
	}
}

func NewAuthHandler(repo *repository.UserRepository, cfg *config.Config, emailService *services.EmailService, sendPulseService *services.SendPulseService, mfaRepo *repository.MFARepository, totpService *services.TOTPService) *AuthHandler {
	return &AuthHandler{
		repo:             repo,
		config:           cfg,
		emailService:     emailService,
		sendPulseService: sendPulseService,
		mfaRepo:          mfaRepo,
		totpService:      totpService,
		mfaTokens:        newMFATempStore(),
	}
}

type RegisterRequest struct {
	Email           string `json:"email" binding:"required,email"`
	Password        string `json:"password" binding:"required,min=6"`
	Handle          string `json:"handle" binding:"required,min=3"`
	DisplayName     string `json:"display_name" binding:"required"`
	AltchaToken     string `json:"altcha_token" binding:"required"`
	AcceptTerms     bool   `json:"accept_terms" binding:"required,eq=true"`
	AcceptPrivacy   bool   `json:"accept_privacy" binding:"required,eq=true"`
	EmailNewsletter bool   `json:"email_newsletter"`
	EmailContact    bool   `json:"email_contact"`
	BirthMonth      int    `json:"birth_month" binding:"required,min=1,max=12"`
	BirthYear       int    `json:"birth_year" binding:"required,min=1900,max=2025"`
}

type LoginRequest struct {
	Email       string `json:"email" binding:"required,email"`
	Password    string `json:"password" binding:"required"`
	AltchaToken string `json:"altcha_token"`
}

func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))

	// Validate ALTCHA token
	altchaService := services.NewAltchaService(h.config.JWTSecret)
	remoteIP := c.ClientIP()
	altchaResp, err := altchaService.VerifyToken(req.AltchaToken, remoteIP)
	if err != nil {
		log.Error().Err(err).Msg("ALTCHA verification failed")
		c.JSON(http.StatusBadRequest, gin.H{"error": "Security verification failed"})
		return
	}

	if !altchaResp.Verified {
		errorMsg := altchaService.GetErrorMessage(altchaResp.Error)
		log.Warn().Str("error_msg", errorMsg).Msg("ALTCHA validation failed")
		c.JSON(http.StatusBadRequest, gin.H{"error": errorMsg})
		return
	}

	// Check if this IP is banned (ban evasion prevention)
	ipBanned, _ := h.repo.IsIPBanned(c.Request.Context(), remoteIP)
	if ipBanned {
		log.Warn().Str("ip", remoteIP).Msg("Registration blocked for banned IP")
		c.JSON(http.StatusForbidden, gin.H{"error": "Registration is not available from this network."})
		return
	}

	// Age gate: reject under-18s at registration so no data is ever stored for minors.
	if req.BirthYear > 0 && req.BirthMonth >= 1 && req.BirthMonth <= 12 {
		now := time.Now()
		age := now.Year() - req.BirthYear
		if int(now.Month()) < req.BirthMonth {
			age--
		}
		if age < 18 {
			c.JSON(http.StatusForbidden, gin.H{
				"error": "You must be at least 18 years old to create an account on Sojorn.",
				"code":  "age_restricted",
			})
			return
		}
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

	log.Info().Str("email", req.Email).Msg("Registering user")
	if err := h.repo.CreateUser(c.Request.Context(), user); err != nil {
		log.Error().Err(err).Str("email", req.Email).Msg("Failed to create user")
		internalError(c, "Failed to create user", err)
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
		log.Error().Err(err).Str("user_id", user.ID.String()).Msg("Failed to create profile, rolling back user")
		_ = h.repo.DeleteUser(c.Request.Context(), user.ID)

		if strings.Contains(err.Error(), "23505") && strings.Contains(err.Error(), "profiles_handle_key") {
			c.JSON(http.StatusConflict, gin.H{"error": "Handle already taken"})
			return
		}
		internalError(c, "Failed to create profile", err)
		return
	}

	rawToken, _ := generateRandomString(32)
	tokenHash := sha256.Sum256([]byte(rawToken))
	hashString := hex.EncodeToString(tokenHash[:])

	if err := h.repo.CreateVerificationToken(c.Request.Context(), hashString, userID.String(), 24*time.Hour); err != nil {
		log.Error().Err(err).Msg("Failed to store verification token, rolling back user")
		_ = h.repo.DeleteUser(c.Request.Context(), user.ID)
		internalError(c, "Failed to prepare verification", err)
		return
	}

	go func() {
		if err := h.emailService.SendVerificationEmail(req.Email, req.DisplayName, rawToken); err != nil {
			log.Error().Err(err).Str("email", req.Email).Msg("Failed to send verification email")
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

	// Validate ALTCHA token
	altchaService := services.NewAltchaService(h.config.JWTSecret)
	remoteIP := c.ClientIP()
	altchaResp, err := altchaService.VerifyToken(req.AltchaToken, remoteIP)
	if err != nil {
		log.Error().Err(err).Msg("Login ALTCHA verification failed")
		c.JSON(http.StatusBadRequest, gin.H{"error": "Security verification failed"})
		return
	}

	if !altchaResp.Verified {
		errorMsg := altchaService.GetErrorMessage(altchaResp.Error)
		log.Warn().Str("error_msg", errorMsg).Msg("Login ALTCHA validation failed")
		c.JSON(http.StatusBadRequest, gin.H{"error": errorMsg})
		return
	}

	// Check if this IP is banned (ban evasion prevention)
	ipBanned, _ := h.repo.IsIPBanned(c.Request.Context(), remoteIP)
	if ipBanned {
		log.Warn().Str("ip", remoteIP).Msg("Login blocked for banned IP")
		c.JSON(http.StatusForbidden, gin.H{"error": "Access is not available from this network."})
		return
	}

	user, err := h.repo.GetUserByEmail(c.Request.Context(), req.Email)
	if err != nil {
		log.Warn().Str("email", req.Email).Msg("Login failed: user not found")
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		log.Warn().Str("email", req.Email).Msg("Login failed: password mismatch")
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		return
	}

	// Age gate: check if user is under 18
	var profile *models.Profile
	profile, _ = h.repo.GetProfileByID(c.Request.Context(), user.ID.String())
	if profile != nil && profile.BirthYear > 0 {
		now := time.Now()
		age := now.Year() - profile.BirthYear
		if int(now.Month()) < profile.BirthMonth {
			age--
		}
		if age < 18 {
			log.Warn().Int("age", age).Msg("Login blocked for underage user")
			c.JSON(http.StatusForbidden, gin.H{
				"error": "You must be at least 18 years old to use Sojorn.",
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
		log.Info().Str("previous_status", string(user.Status)).Str("email", req.Email).Msg("Reactivating account")
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
		h.mfaTokens.Set(tempToken, user.ID)
		c.JSON(http.StatusOK, gin.H{
			"mfa_required": true,
			"temp_token":   tempToken,
		})
		return
	}

	_ = h.repo.UpdateLastLogin(c.Request.Context(), user.ID.String())

	token, err := h.generateToken(user.ID)
	if err != nil {
		internalError(c, "Failed to generate token", err)
		return
	}

	refreshToken, _ := generateRandomString(32)
	_ = h.repo.StoreRefreshToken(c.Request.Context(), user.ID.String(), refreshToken, 30*24*time.Hour)

	// Re-fetch profile if not already loaded from age check
	if profile == nil {
		profile, _ = h.repo.GetProfileByID(c.Request.Context(), user.ID.String())
	}
	if profile == nil {
		log.Error().Str("user_id", user.ID.String()).Msg("Failed to get profile")
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
		log.Error().Err(err).Str("user_id", userId).Msg("Failed to complete onboarding")
		internalError(c, "Failed to update onboarding status", err)
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
		internalError(c, "Failed to prepare verification", err)
		return
	}

	go func() {
		name := ""
		profile, err := h.repo.GetProfileByID(c.Request.Context(), user.ID.String())
		if err == nil && profile != nil && profile.DisplayName != nil {
			name = *profile.DisplayName
		}
		if err := h.emailService.SendVerificationEmail(user.Email, name, rawToken); err != nil {
			log.Error().Err(err).Str("email", user.Email).Msg("Failed to send verification email")
		}
	}()

	log.Info().Str("email", user.Email).Msg("Resent verification token")

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

	// Generate new tokens BEFORE revoking old one — prevents permanent
	// lockout if generation or storage fails after revocation.
	newAccessToken, err := h.generateToken(rt.UserID)
	if err != nil {
		internalError(c, "Failed to generate token", err)
		return
	}

	newRefreshToken, _ := generateRandomString(32)
	err = h.repo.StoreRefreshToken(c.Request.Context(), rt.UserID.String(), newRefreshToken, 30*24*time.Hour)
	if err != nil {
		internalError(c, "Failed to save session", err)
		return
	}

	// Only revoke old token after new one is safely stored.
	_ = h.repo.RevokeRefreshToken(c.Request.Context(), req.RefreshToken)

	c.JSON(http.StatusOK, models.TokenPair{
		AccessToken:  newAccessToken,
		RefreshToken: newRefreshToken,
	})
}

func (h *AuthHandler) generateToken(userID uuid.UUID) (string, error) {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":  userID.String(),
		"exp":  time.Now().Add(time.Minute * 15).Unix(), // 15 minutes — refresh token handles session continuity
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
		log.Error().Err(err).Msg("Failed to create reset token")
		internalError(c, "Internal error", err)
		return
	}

	go func() {
		name := ""
		profile, err := h.repo.GetProfileByID(c.Request.Context(), user.ID.String())
		if err == nil && profile != nil && profile.DisplayName != nil {
			name = *profile.DisplayName
		}
		if err := h.emailService.SendPasswordResetEmail(user.Email, name, rawToken); err != nil {
			log.Error().Err(err).Str("email", user.Email).Msg("Failed to send reset email")
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
		internalError(c, "Failed to update password", err)
		return
	}

	_ = h.repo.DeletePasswordResetToken(c.Request.Context(), hashString)

	c.JSON(http.StatusOK, gin.H{"message": "Password reset successfully"})
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

// ── MFA TOTP Endpoints ──────────────────────────────────────────────────

// SetupMFA generates a TOTP secret + recovery codes. Does NOT enable MFA yet.
func (h *AuthHandler) SetupMFA(c *gin.Context) {
	userID := c.MustGet("user_id").(string)
	uid, _ := uuid.Parse(userID)

	user, err := h.repo.GetUserByID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}
	if user.MFAEnabled {
		c.JSON(http.StatusConflict, gin.H{"error": "MFA is already enabled"})
		return
	}

	secret, provisioningURI, err := h.totpService.GenerateSecret(user.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate TOTP secret"})
		return
	}

	recoveryCodes, err := h.totpService.GenerateRecoveryCodes()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate recovery codes"})
		return
	}

	hashedCodes, err := h.totpService.HashRecoveryCodes(recoveryCodes)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to hash recovery codes"})
		return
	}

	// Store secret + hashed codes, but don't enable MFA yet (user must confirm with a code first)
	if err := h.mfaRepo.SaveSecret(c.Request.Context(), uid, secret, hashedCodes); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to store MFA secret"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"secret":           secret,
		"provisioning_uri": provisioningURI,
		"recovery_codes":   recoveryCodes,
	})
}

// ConfirmMFA verifies the first TOTP code and enables MFA on the account.
func (h *AuthHandler) ConfirmMFA(c *gin.Context) {
	userID := c.MustGet("user_id").(string)
	uid, _ := uuid.Parse(userID)

	var req struct {
		Code string `json:"code" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Code is required"})
		return
	}

	mfaSecret, err := h.mfaRepo.GetSecret(c.Request.Context(), uid)
	if err != nil || mfaSecret == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "MFA setup not started"})
		return
	}

	if !h.totpService.ValidateCode(mfaSecret.Secret, req.Code) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid verification code"})
		return
	}

	if err := h.mfaRepo.SetMFAEnabled(c.Request.Context(), uid, true); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to enable MFA"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "MFA enabled successfully"})
}

// VerifyMFA validates a TOTP code (or recovery code) during login.
func (h *AuthHandler) VerifyMFA(c *gin.Context) {
	var req struct {
		TempToken    string `json:"temp_token" binding:"required"`
		Code         string `json:"code"`
		RecoveryCode string `json:"recovery_code"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "temp_token is required"})
		return
	}

	if req.Code == "" && req.RecoveryCode == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Provide either code or recovery_code"})
		return
	}

	userID, ok := h.mfaTokens.Get(req.TempToken)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired MFA session"})
		return
	}

	mfaSecret, err := h.mfaRepo.GetSecret(c.Request.Context(), userID)
	if err != nil || mfaSecret == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "MFA configuration not found"})
		return
	}

	if req.Code != "" {
		if !h.totpService.ValidateCode(mfaSecret.Secret, req.Code) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid verification code"})
			return
		}
	} else {
		idx := h.totpService.CheckRecoveryCode(mfaSecret.RecoveryCodes, req.RecoveryCode)
		if idx < 0 {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid recovery code"})
			return
		}
		// Remove used recovery code
		remaining := make([]string, 0, len(mfaSecret.RecoveryCodes)-1)
		for i, code := range mfaSecret.RecoveryCodes {
			if i != idx {
				remaining = append(remaining, code)
			}
		}
		_ = h.mfaRepo.UpdateRecoveryCodes(c.Request.Context(), userID, remaining)
	}

	// MFA verified — consume temp token, issue real tokens
	h.mfaTokens.Delete(req.TempToken)
	_ = h.repo.UpdateLastLogin(c.Request.Context(), userID.String())

	token, err := h.generateToken(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	refreshToken, _ := generateRandomString(32)
	_ = h.repo.StoreRefreshToken(c.Request.Context(), userID.String(), refreshToken, 30*24*time.Hour)

	user, _ := h.repo.GetUserByID(c.Request.Context(), userID.String())
	profile, _ := h.repo.GetProfileByID(c.Request.Context(), userID.String())

	c.JSON(http.StatusOK, gin.H{
		"token":         token,
		"access_token":  token,
		"refresh_token": refreshToken,
		"user":          user,
		"profile":       profile,
	})
}

// DisableMFA removes TOTP from an account. Requires current password + TOTP code.
func (h *AuthHandler) DisableMFA(c *gin.Context) {
	userID := c.MustGet("user_id").(string)
	uid, _ := uuid.Parse(userID)

	var req struct {
		Password string `json:"password" binding:"required"`
		Code     string `json:"code" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Password and code are required"})
		return
	}

	user, err := h.repo.GetUserByID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	if bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)) != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid password"})
		return
	}

	mfaSecret, err := h.mfaRepo.GetSecret(c.Request.Context(), uid)
	if err != nil || mfaSecret == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "MFA is not enabled"})
		return
	}

	if !h.totpService.ValidateCode(mfaSecret.Secret, req.Code) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid verification code"})
		return
	}

	if err := h.mfaRepo.SetMFAEnabled(c.Request.Context(), uid, false); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to disable MFA"})
		return
	}
	_ = h.mfaRepo.DeleteSecret(c.Request.Context(), uid)

	c.JSON(http.StatusOK, gin.H{"message": "MFA disabled successfully"})
}
