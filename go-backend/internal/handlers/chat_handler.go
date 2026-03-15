// Copyright (c) 2026 MPLS LLC
// SPDX-License-Identifier: AGPL-3.0-or-later
// See LICENSE file for details

package handlers

import (
	"context"
	//	"encoding/base64"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/realtime"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/services"
	"github.com/rs/zerolog/log"
)

type ChatHandler struct {
	chatRepo            *repository.ChatRepository
	notificationService *services.NotificationService
	hub                 *realtime.Hub
}

func NewChatHandler(chatRepo *repository.ChatRepository, notificationService *services.NotificationService, hub *realtime.Hub) *ChatHandler {
	return &ChatHandler{
		chatRepo:            chatRepo,
		notificationService: notificationService,
		hub:                 hub,
	}
}

func (h *ChatHandler) GetConversations(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	conversations, err := h.chatRepo.GetConversations(c.Request.Context(), userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch conversations"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"conversations": conversations})
}

func (h *ChatHandler) GetOrCreateConversation(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	otherUserID := c.Query("other_user_id")
	if otherUserID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "other_user_id is required"})
		return
	}

	id, err := h.chatRepo.GetOrCreateConversation(c.Request.Context(), userIDStr.(string), otherUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to handle conversation"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"conversation_id": id})
}

func (h *ChatHandler) SendMessage(c *gin.Context) {
	senderIDStr, _ := c.Get("user_id")
	senderID, err := uuid.Parse(senderIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid sender ID"})
		return
	}

	var req struct {
		ConversationID string  `json:"conversation_id" binding:"required"`
		ReceiverID     string  `json:"receiver_id"`
		Ciphertext     string  `json:"ciphertext" binding:"required"`
		IV             string  `json:"iv"`
		KeyVersion     string  `json:"key_version"`
		MessageHeader  string  `json:"message_header"`
		ReplyToID      *string `json:"reply_to_id"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	convID, err := uuid.Parse(req.ConversationID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid conversation ID"})
		return
	}

	pA, pB, err := h.chatRepo.GetParticipants(c.Request.Context(), req.ConversationID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to authenticate conversation participants"})
		return
	}

	if senderID.String() != pA && senderID.String() != pB {
		c.JSON(http.StatusForbidden, gin.H{"error": "You are not a participant in this conversation"})
		return
	}

	otherParticipant := pA
	if senderID.String() == pA {
		otherParticipant = pB
	}

	var receiverID uuid.UUID
	if req.ReceiverID != "" {
		receiverID, err = uuid.Parse(req.ReceiverID)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid receiver ID"})
			return
		}

		if receiverID.String() != otherParticipant {
			c.JSON(http.StatusForbidden, gin.H{"error": "Receiver is not a participant in this conversation"})
			return
		}
	} else {
		receiverID, _ = uuid.Parse(otherParticipant)
	}

	// Parse optional reply_to_id
	var replyToID *uuid.UUID
	if req.ReplyToID != nil && *req.ReplyToID != "" {
		parsed, parseErr := uuid.Parse(*req.ReplyToID)
		if parseErr == nil {
			replyToID = &parsed
		}
	}

	// Persist blind ciphertext to DB
	msg, err := h.chatRepo.CreateMessage(c.Request.Context(), senderID, receiverID, convID, req.Ciphertext, req.IV, req.KeyVersion, req.MessageHeader, replyToID)
	if err != nil {
		log.Error().Err(err).Msg("Failed to persist secure message")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to send message"})
		return
	}

	// Prepare Real-time Payload
	rtPayload := gin.H{
		"type": "new_message",
		"payload": gin.H{
			"id":              msg.ID,
			"conversation_id": msg.ConversationID,
			"sender_id":       msg.SenderID,
			"receiver_id":     msg.ReceiverID,
			"ciphertext":      msg.Ciphertext,
			"iv":              msg.IV,
			"key_version":     msg.KeyVersion,
			"message_header":  msg.MessageHeader,
			"reply_to_id":     msg.ReplyToID,
			"created_at":      msg.CreatedAt,
		},
	}

	// 1. Send via WebSocket (Best Effort, Immediate)
	h.hub.SendToUser(receiverID.String(), rtPayload)

	// 2. Send via Notification Service (Background, Reliable)
	if h.notificationService != nil {
		go func(recipID string, senderID string, convID string) {
			_ = h.notificationService.NotifyMessage(context.Background(), recipID, senderID, convID)
		}(receiverID.String(), senderID.String(), msg.ConversationID.String())
	}

	c.JSON(http.StatusCreated, msg)
}

func (h *ChatHandler) GetMessages(c *gin.Context) {
	convIDStr := c.Param("id")
	convID, err := uuid.Parse(convIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid conversation ID"})
		return
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))

	messages, err := h.chatRepo.GetMessages(c.Request.Context(), convID, limit, offset)
	if err != nil {
		log.Error().Err(err).Str("conversation_id", convIDStr).Msg("Failed to fetch messages")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch messages"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"messages": messages})
}

func (h *ChatHandler) GetMutualFollows(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	profiles, err := h.chatRepo.GetMutualFollows(c.Request.Context(), userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch mutual follows"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"profiles": profiles})
}

func (h *ChatHandler) DeleteConversation(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	convIDStr := c.Param("id")
	convID, err := uuid.Parse(convIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid conversation ID"})
		return
	}

	err = h.chatRepo.DeleteConversation(c.Request.Context(), convID, userIDStr.(string))
	if err != nil {
		log.Error().Err(err).Str("conversation_id", convIDStr).Msg("Failed to delete conversation")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete conversation"})
		return
	}

	// Broadcast deletion to current user via WebSocket
	deleteEvent := map[string]interface{}{
		"type": "conversation_deleted",
		"payload": map[string]interface{}{
			"conversation_id": convID.String(),
			"deleted_by":      userIDStr,
		},
	}

	// Send to current user (all their devices)
	_ = h.hub.SendToUser(userIDStr.(string), deleteEvent)

	c.JSON(http.StatusOK, gin.H{"success": true, "message": "Conversation permanently deleted"})
}

func (h *ChatHandler) DeleteMessage(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	msgIDStr := c.Param("id")
	msgID, err := uuid.Parse(msgIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid message ID"})
		return
	}

	// Get conversation and recipient info before deleting
	var conversationID, senderID, receiverID uuid.UUID
	err = h.chatRepo.GetMessageInfo(c.Request.Context(), msgID, &conversationID, &senderID, &receiverID)
	if err != nil {
		log.Error().Err(err).Str("message_id", msgIDStr).Msg("Failed to get message info")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get message info"})
		return
	}

	err = h.chatRepo.DeleteMessage(c.Request.Context(), msgID, userIDStr.(string))
	if err != nil {
		log.Error().Err(err).Str("message_id", msgIDStr).Msg("Failed to delete message")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete message"})
		return
	}

	// Broadcast deletion to both participants via WebSocket
	deleteEvent := map[string]interface{}{
		"type": "message_deleted",
		"payload": map[string]interface{}{
			"message_id":      msgID.String(),
			"conversation_id": conversationID.String(),
			"deleted_by":      userIDStr,
		},
	}

	// Send to sender (all their devices)
	_ = h.hub.SendToUser(senderID.String(), deleteEvent)
	// Send to receiver (all their devices)
	_ = h.hub.SendToUser(receiverID.String(), deleteEvent)

	c.JSON(http.StatusOK, gin.H{"success": true, "message": "Message permanently deleted"})
}

// ── Reactions ──────────────────────────────────────────────────────────────

func (h *ChatHandler) AddReaction(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user"})
		return
	}

	msgID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid message id"})
		return
	}

	var req struct {
		Emoji string `json:"emoji" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Verify user is a participant in this conversation
	convID, err := h.chatRepo.GetMessageConversationID(c.Request.Context(), msgID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "message not found"})
		return
	}
	pA, pB, err := h.chatRepo.GetParticipants(c.Request.Context(), convID.String())
	if err != nil || (userIDStr.(string) != pA && userIDStr.(string) != pB) {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a participant"})
		return
	}

	reaction, err := h.chatRepo.AddReaction(c.Request.Context(), msgID, userID, req.Emoji)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to add reaction"})
		return
	}

	// Broadcast to both participants
	rtPayload := map[string]interface{}{
		"type": "reaction_added",
		"payload": map[string]interface{}{
			"message_id":      msgID.String(),
			"conversation_id": convID.String(),
			"user_id":         userID.String(),
			"emoji":           req.Emoji,
		},
	}
	_ = h.hub.SendToUser(pA, rtPayload)
	_ = h.hub.SendToUser(pB, rtPayload)

	c.JSON(http.StatusCreated, reaction)
}

func (h *ChatHandler) RemoveReaction(c *gin.Context) {
	userIDStr, _ := c.Get("user_id")
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user"})
		return
	}

	msgID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid message id"})
		return
	}

	emoji := c.Query("emoji")
	if emoji == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "emoji required"})
		return
	}

	// Verify participant
	convID, err := h.chatRepo.GetMessageConversationID(c.Request.Context(), msgID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "message not found"})
		return
	}
	pA, pB, err := h.chatRepo.GetParticipants(c.Request.Context(), convID.String())
	if err != nil || (userIDStr.(string) != pA && userIDStr.(string) != pB) {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a participant"})
		return
	}

	if err := h.chatRepo.RemoveReaction(c.Request.Context(), msgID, userID, emoji); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to remove reaction"})
		return
	}

	// Broadcast removal
	rtPayload := map[string]interface{}{
		"type": "reaction_removed",
		"payload": map[string]interface{}{
			"message_id":      msgID.String(),
			"conversation_id": convID.String(),
			"user_id":         userID.String(),
			"emoji":           emoji,
		},
	}
	_ = h.hub.SendToUser(pA, rtPayload)
	_ = h.hub.SendToUser(pB, rtPayload)

	c.JSON(http.StatusOK, gin.H{"success": true})
}
