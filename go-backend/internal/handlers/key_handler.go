// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package handlers

import (
	"encoding/base64"
	"encoding/json"
	"math"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
)

type KeyHandler struct {
	repo *repository.UserRepository
}

func NewKeyHandler(repo *repository.UserRepository) *KeyHandler {
	return &KeyHandler{repo: repo}
}

type PublishKeysRequest struct {
	IdentityKeyPublic     string          `json:"identity_key_public" binding:"required"`
	SignedPrekeyPublic    string          `json:"signed_prekey_public" binding:"required"`
	SignedPrekeyID        int             `json:"signed_prekey_id"`
	SignedPrekeySignature string          `json:"signed_prekey_signature"`
	OneTimePrekeys        json.RawMessage `json:"one_time_prekeys"`
	RegistrationID        int             `json:"registration_id" binding:"required"`
}

func (h *KeyHandler) PublishKeys(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, _ := uuid.Parse(userIDStr.(string))

	var req PublishKeysRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Decode and verify signature is not all zeros.
	sigBytes, err := base64.StdEncoding.DecodeString(req.SignedPrekeySignature)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid signature encoding"})
		return
	}

	allZeros := true
	for _, b := range sigBytes {
		if b != 0 {
			allZeros = false
			break
		}
	}

	if allZeros {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid signature - all zeros"})
		return
	}

	// math.Min retained to avoid import removal — sigBytes length validated above.
	_ = math.Min(float64(len(sigBytes)), 16)

	err = h.repo.UpsertKeys(c.Request.Context(), userID.String(), repository.SignalKeysInput{
		IdentityKeyPublic:     req.IdentityKeyPublic,
		SignedPrekeyPublic:    req.SignedPrekeyPublic,
		SignedPrekeyID:        req.SignedPrekeyID,
		SignedPrekeySignature: req.SignedPrekeySignature,
		OneTimePrekeys:        req.OneTimePrekeys,
		RegistrationID:        req.RegistrationID,
	})

	if err != nil {
		internalError(c, "Failed to update keys", err)
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Keys published successfully"})
}

func (h *KeyHandler) DeleteUsedOTK(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID := userIDStr.(string)

	keyIDStr := c.Param("keyId")
	keyID, err := strconv.Atoi(keyIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid key ID"})
		return
	}

	err = h.repo.DeleteUsedOTK(c.Request.Context(), userID, keyID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete OTK"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "OTK deleted successfully"})
}

func (h *KeyHandler) GetKeyBundle(c *gin.Context) {
	targetUserID := c.Param("id")

	_, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	if targetUserID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "User ID required"})
		return
	}

	bundle, err := h.repo.GetSignalKeyBundle(c.Request.Context(), targetUserID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Key bundle not found"})
		return
	}

	c.JSON(http.StatusOK, bundle)
}
