// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package services

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/google/uuid"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/models"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
	"github.com/rs/zerolog/log"
)

type NotificationService struct {
	notifRepo *repository.NotificationRepository
	pushSvc   *PushService
	userRepo  *repository.UserRepository
}

func NewNotificationService(notifRepo *repository.NotificationRepository, pushSvc *PushService, userRepo *repository.UserRepository) *NotificationService {
	return &NotificationService{
		notifRepo: notifRepo,
		pushSvc:   pushSvc,
		userRepo:  userRepo,
	}
}

// ============================================================================
// High-Level Notification Methods (Called by Handlers)
// ============================================================================

// NotifyLike sends a notification when someone likes a post
func (s *NotificationService) NotifyLike(ctx context.Context, postAuthorID, actorID, postID string, postType string, emoji string) error {
	if postAuthorID == actorID {
		return nil // Don't notify self
	}

	if emoji == "" {
		emoji = "❤️"
	}

	return s.sendNotification(ctx, models.PushNotificationRequest{
		UserID:   uuid.MustParse(postAuthorID),
		Type:     models.NotificationTypeLike,
		ActorID:  uuid.MustParse(actorID),
		PostID:   uuidPtr(postID),
		PostType: postType,
		GroupKey: fmt.Sprintf("like:%s", postID), // Group likes on same post
		Priority: models.PriorityNormal,
		Metadata: map[string]interface{}{
			"emoji": emoji,
		},
	})
}

// NotifyComment sends a notification when someone comments on a post
func (s *NotificationService) NotifyComment(ctx context.Context, postAuthorID, actorID, postID, commentID string, postType string) error {
	if postAuthorID == actorID {
		return nil
	}

	return s.sendNotification(ctx, models.PushNotificationRequest{
		UserID:    uuid.MustParse(postAuthorID),
		Type:      models.NotificationTypeComment,
		ActorID:   uuid.MustParse(actorID),
		PostID:    uuidPtr(postID),
		CommentID: uuidPtr(commentID),
		PostType:  postType,
		GroupKey:  fmt.Sprintf("comment:%s", postID),
		Priority:  models.PriorityNormal,
	})
}

// NotifyReply sends a notification when someone replies to a comment
func (s *NotificationService) NotifyReply(ctx context.Context, commentAuthorID, actorID, postID, commentID string) error {
	if commentAuthorID == actorID {
		return nil
	}

	return s.sendNotification(ctx, models.PushNotificationRequest{
		UserID:    uuid.MustParse(commentAuthorID),
		Type:      models.NotificationTypeReply,
		ActorID:   uuid.MustParse(actorID),
		PostID:    uuidPtr(postID),
		CommentID: uuidPtr(commentID),
		Priority:  models.PriorityNormal,
	})
}

// NotifyMention sends notifications to all mentioned users
func (s *NotificationService) NotifyMention(ctx context.Context, actorID, postID string, text string) error {
	mentionedUserIDs, err := s.notifRepo.ExtractMentions(ctx, text)
	if err != nil || len(mentionedUserIDs) == 0 {
		return err
	}

	actorUUID := uuid.MustParse(actorID)
	for _, userID := range mentionedUserIDs {
		if userID == actorUUID {
			continue // Don't notify self
		}

		err := s.sendNotification(ctx, models.PushNotificationRequest{
			UserID:   userID,
			Type:     models.NotificationTypeMention,
			ActorID:  actorUUID,
			PostID:   uuidPtr(postID),
			Priority: models.PriorityHigh, // Mentions are high priority
		})
		if err != nil {
			log.Warn().Err(err).Str("user_id", userID.String()).Msg("Failed to send mention notification")
		}
	}

	return nil
}

// NotifyFollow sends a notification when someone follows a user
func (s *NotificationService) NotifyFollow(ctx context.Context, followedUserID, followerID string, isPending bool) error {
	notifType := models.NotificationTypeFollow
	if isPending {
		notifType = models.NotificationTypeFollowRequest
	}

	return s.sendNotification(ctx, models.PushNotificationRequest{
		UserID:   uuid.MustParse(followedUserID),
		Type:     notifType,
		ActorID:  uuid.MustParse(followerID),
		Priority: models.PriorityNormal,
		Metadata: map[string]interface{}{
			"follower_id": followerID,
		},
	})
}

// NotifyFollowAccepted sends a notification when a follow request is accepted
func (s *NotificationService) NotifyFollowAccepted(ctx context.Context, followerID, acceptorID string) error {
	return s.sendNotification(ctx, models.PushNotificationRequest{
		UserID:   uuid.MustParse(followerID),
		Type:     models.NotificationTypeFollowAccept,
		ActorID:  uuid.MustParse(acceptorID),
		Priority: models.PriorityNormal,
	})
}

// NotifySave sends a notification when someone saves a post
func (s *NotificationService) NotifySave(ctx context.Context, postAuthorID, actorID, postID, postType string) error {
	if postAuthorID == actorID {
		return nil
	}

	return s.sendNotification(ctx, models.PushNotificationRequest{
		UserID:   uuid.MustParse(postAuthorID),
		Type:     models.NotificationTypeSave,
		ActorID:  uuid.MustParse(actorID),
		PostID:   uuidPtr(postID),
		PostType: postType,
		GroupKey: fmt.Sprintf("save:%s", postID),
		Priority: models.PriorityLow, // Saves are lower priority
	})
}

// NotifyMessage sends a notification for new chat messages
func (s *NotificationService) NotifyMessage(ctx context.Context, receiverID, senderID, conversationID string) error {
	return s.sendNotification(ctx, models.PushNotificationRequest{
		UserID:   uuid.MustParse(receiverID),
		Type:     models.NotificationTypeMessage,
		ActorID:  uuid.MustParse(senderID),
		Priority: models.PriorityHigh, // Messages are high priority
		Metadata: map[string]interface{}{
			"conversation_id": conversationID,
		},
	})
}

// NotifyBeaconVouch sends a notification when someone vouches for a beacon
func (s *NotificationService) NotifyBeaconVouch(ctx context.Context, beaconAuthorID, actorID, beaconID string) error {
	if beaconAuthorID == actorID {
		return nil
	}

	return s.sendNotification(ctx, models.PushNotificationRequest{
		UserID:   uuid.MustParse(beaconAuthorID),
		Type:     models.NotificationTypeBeaconVouch,
		ActorID:  uuid.MustParse(actorID),
		PostID:   uuidPtr(beaconID),
		PostType: "beacon",
		GroupKey: fmt.Sprintf("beacon_vouch:%s", beaconID),
		Priority: models.PriorityNormal,
	})
}

// NotifyBeaconReport sends a notification when someone reports a beacon
func (s *NotificationService) NotifyBeaconReport(ctx context.Context, beaconAuthorID, actorID, beaconID string) error {
	if beaconAuthorID == actorID {
		return nil
	}

	return s.sendNotification(ctx, models.PushNotificationRequest{
		UserID:   uuid.MustParse(beaconAuthorID),
		Type:     models.NotificationTypeBeaconReport,
		ActorID:  uuid.MustParse(actorID),
		PostID:   uuidPtr(beaconID),
		PostType: "beacon",
		Priority: models.PriorityNormal,
	})
}

// NotifyGroupPost notifies all group members (except the author) when someone posts in a group
func (s *NotificationService) NotifyGroupPost(ctx context.Context, actorID, postID, groupID, groupName string, memberIDs []string) error {
	actorUUID := uuid.MustParse(actorID)
	for _, memberID := range memberIDs {
		memberUUID := uuid.MustParse(memberID)
		if memberUUID == actorUUID {
			continue // Don't notify self
		}
		err := s.sendNotification(ctx, models.PushNotificationRequest{
			UserID:   memberUUID,
			Type:     models.NotificationTypeGroupPost,
			ActorID:  actorUUID,
			PostID:   uuidPtr(postID),
			PostType: "group",
			GroupKey: fmt.Sprintf("group_post:%s", groupID),
			Priority: models.PriorityNormal,
			Metadata: map[string]interface{}{
				"group_id":   groupID,
				"group_name": groupName,
			},
		})
		if err != nil {
			log.Warn().Err(err).Str("member_id", memberID).Msg("Failed to send group post notification")
		}
	}
	return nil
}

// NotifyGroupComment notifies the post author when someone comments on their group post
func (s *NotificationService) NotifyGroupComment(ctx context.Context, postAuthorID, actorID, postID, groupID, groupName string) error {
	if postAuthorID == actorID {
		return nil
	}
	return s.sendNotification(ctx, models.PushNotificationRequest{
		UserID:   uuid.MustParse(postAuthorID),
		Type:     models.NotificationTypeGroupComment,
		ActorID:  uuid.MustParse(actorID),
		PostID:   uuidPtr(postID),
		PostType: "group",
		GroupKey: fmt.Sprintf("group_comment:%s", postID),
		Priority: models.PriorityNormal,
		Metadata: map[string]interface{}{
			"group_id":   groupID,
			"group_name": groupName,
		},
	})
}

// NotifyGroupLike notifies the post author when someone likes their group post
func (s *NotificationService) NotifyGroupLike(ctx context.Context, postAuthorID, actorID, postID, groupID, groupName string) error {
	if postAuthorID == actorID {
		return nil
	}
	return s.sendNotification(ctx, models.PushNotificationRequest{
		UserID:   uuid.MustParse(postAuthorID),
		Type:     models.NotificationTypeGroupLike,
		ActorID:  uuid.MustParse(actorID),
		PostID:   uuidPtr(postID),
		PostType: "group",
		GroupKey: fmt.Sprintf("group_like:%s", postID),
		Priority: models.PriorityNormal,
		Metadata: map[string]interface{}{
			"group_id":   groupID,
			"group_name": groupName,
		},
	})
}

// NotifyGroupInvite notifies a user when they are added to a group
func (s *NotificationService) NotifyGroupInvite(ctx context.Context, invitedUserID, actorID, groupID, groupName string) error {
	if invitedUserID == actorID {
		return nil
	}
	return s.sendNotification(ctx, models.PushNotificationRequest{
		UserID:   uuid.MustParse(invitedUserID),
		Type:     models.NotificationTypeGroupInvite,
		ActorID:  uuid.MustParse(actorID),
		PostType: "group",
		Priority: models.PriorityNormal,
		Metadata: map[string]interface{}{
			"group_id":   groupID,
			"group_name": groupName,
		},
	})
}

// NotifyGroupThread notifies all group members when a new forum thread is created
func (s *NotificationService) NotifyGroupThread(ctx context.Context, actorID, threadID, groupID, groupName string, memberIDs []string) error {
	actorUUID := uuid.MustParse(actorID)
	for _, memberID := range memberIDs {
		memberUUID := uuid.MustParse(memberID)
		if memberUUID == actorUUID {
			continue
		}
		err := s.sendNotification(ctx, models.PushNotificationRequest{
			UserID:   memberUUID,
			Type:     models.NotificationTypeGroupThread,
			ActorID:  actorUUID,
			PostID:   uuidPtr(threadID),
			PostType: "group",
			GroupKey: fmt.Sprintf("group_thread:%s", groupID),
			Priority: models.PriorityNormal,
			Metadata: map[string]interface{}{
				"group_id":   groupID,
				"group_name": groupName,
			},
		})
		if err != nil {
			log.Warn().Err(err).Str("member_id", memberID).Msg("Failed to send group thread notification")
		}
	}
	return nil
}

// NotifyGroupReply notifies the thread author when someone replies to their forum thread
func (s *NotificationService) NotifyGroupReply(ctx context.Context, threadAuthorID, actorID, threadID, groupID, groupName string) error {
	if threadAuthorID == actorID {
		return nil
	}
	return s.sendNotification(ctx, models.PushNotificationRequest{
		UserID:   uuid.MustParse(threadAuthorID),
		Type:     models.NotificationTypeGroupReply,
		ActorID:  uuid.MustParse(actorID),
		PostID:   uuidPtr(threadID),
		PostType: "group",
		GroupKey: fmt.Sprintf("group_reply:%s", threadID),
		Priority: models.PriorityNormal,
		Metadata: map[string]interface{}{
			"group_id":   groupID,
			"group_name": groupName,
		},
	})
}

// NotifyNSFWWarning sends a warning when a post is auto-labeled as NSFW
func (s *NotificationService) NotifyNSFWWarning(ctx context.Context, authorID string, postID string) error {
	authorUUID := uuid.MustParse(authorID)
	return s.sendNotification(ctx, models.PushNotificationRequest{
		UserID:   authorUUID,
		Type:     models.NotificationTypeNSFWWarning,
		ActorID:  authorUUID, // system-generated, actor is self
		PostID:   uuidPtr(postID),
		PostType: "standard",
		Priority: models.PriorityHigh,
	})
}

// NotifyContentRemoved sends a notification when content is removed by AI moderation
func (s *NotificationService) NotifyContentRemoved(ctx context.Context, authorID string, postID string) error {
	authorUUID := uuid.MustParse(authorID)
	return s.sendNotification(ctx, models.PushNotificationRequest{
		UserID:   authorUUID,
		Type:     models.NotificationTypeContentRemoved,
		ActorID:  authorUUID, // system-generated
		PostID:   uuidPtr(postID),
		PostType: "standard",
		Priority: models.PriorityUrgent,
	})
}

// ============================================================================
// Core Send Logic
// ============================================================================

func (s *NotificationService) sendNotification(ctx context.Context, req models.PushNotificationRequest) error {
	// Check user preferences
	shouldSend, err := s.notifRepo.ShouldSendPush(ctx, req.UserID.String(), req.Type)
	if err != nil {
		log.Warn().Err(err).Msg("Failed to check notification preferences")
	}

	// Get actor details
	actor, err := s.userRepo.GetProfileByID(ctx, req.ActorID.String())
	if err != nil {
		log.Warn().Err(err).Msg("Failed to get actor profile for notification")
		actor = &models.Profile{DisplayName: ptrString("Someone")}
	}
	if actor.DisplayName != nil {
		req.ActorName = *actor.DisplayName
	}
	if actor.AvatarURL != nil {
		req.ActorAvatar = *actor.AvatarURL
	}
	if actor.Handle != nil {
		req.ActorHandle = *actor.Handle
	}

	// Create in-app notification record
	notif := &models.Notification{
		UserID:   req.UserID,
		Type:     req.Type,
		ActorID:  req.ActorID,
		PostID:   req.PostID,
		IsRead:   false,
		Priority: req.Priority,
		Metadata: s.buildMetadata(req),
	}
	if req.CommentID != nil {
		notif.CommentID = req.CommentID
	}
	if req.GroupKey != "" {
		notif.GroupKey = &req.GroupKey
	}

	if err := s.notifRepo.CreateNotification(ctx, notif); err != nil {
		log.Warn().Err(err).Msg("Failed to create in-app notification")
	}

	// Send push notification if enabled
	if shouldSend && s.pushSvc != nil {
		title, body, data := s.buildPushPayload(req)

		// Get badge count for iOS/macOS
		badge, _ := s.notifRepo.GetUnreadBadge(ctx, req.UserID.String())

		err := s.pushSvc.SendPushWithBadge(ctx, req.UserID.String(), title, body, data, badge.TotalCount)
		if err != nil {
			log.Warn().Err(err).Str("user_id", req.UserID.String()).Msg("Failed to send push notification")
		}
	}

	return nil
}

func (s *NotificationService) buildMetadata(req models.PushNotificationRequest) json.RawMessage {
	data := map[string]interface{}{
		"actor_name": req.ActorName,
		"post_type":  req.PostType,
	}

	if req.PostID != nil {
		data["post_id"] = req.PostID.String()
	}
	if req.CommentID != nil {
		data["comment_id"] = req.CommentID.String()
	}
	if req.PostPreview != "" {
		data["post_preview"] = req.PostPreview
	}

	for k, v := range req.Metadata {
		data[k] = v
	}

	bytes, _ := json.Marshal(data)
	return bytes
}

func (s *NotificationService) buildPushPayload(req models.PushNotificationRequest) (title, body string, data map[string]string) {
	actorName := req.ActorName
	if actorName == "" {
		actorName = "Someone"
	}

	data = map[string]string{
		"type": req.Type,
	}

	if req.PostID != nil {
		data["post_id"] = req.PostID.String()
	}
	if req.CommentID != nil {
		data["comment_id"] = req.CommentID.String()
	}
	if req.ActorHandle != "" {
		data["actor_handle"] = req.ActorHandle
	}
	if req.PostType != "" {
		data["post_type"] = req.PostType
	}

	// Add target for navigation
	target := s.getNavigationTarget(req.Type, req.PostType)
	data["target"] = target

	// Copy metadata
	for k, v := range req.Metadata {
		if str, ok := v.(string); ok {
			data[k] = str
		}
	}

	// Extract optional emoji
	emoji := getString(req.Metadata, "emoji")

	switch req.Type {
	case models.NotificationTypeLike:
		if emoji != "" {
			title = fmt.Sprintf("%s %s", actorName, emoji)
			body = fmt.Sprintf("%s %s your %s", actorName, emoji, s.formatPostType(req.PostType))
		} else {
			title = "New Like"
			body = fmt.Sprintf("%s liked your %s", actorName, s.formatPostType(req.PostType))
		}

	case models.NotificationTypeComment:
		title = fmt.Sprintf("%s 💬", actorName)
		body = fmt.Sprintf("%s commented on your %s", actorName, s.formatPostType(req.PostType))

	case models.NotificationTypeReply:
		title = fmt.Sprintf("%s 💬", actorName)
		body = fmt.Sprintf("%s replied to your comment", actorName)

	case models.NotificationTypeMention:
		title = "Mentioned"
		body = fmt.Sprintf("%s mentioned you in a post", actorName)

	case models.NotificationTypeFollow:
		title = "New Follower"
		body = fmt.Sprintf("%s started following you", actorName)
		if req.ActorHandle != "" {
			data["follower_id"] = req.ActorHandle
		} else {
			data["follower_id"] = req.ActorID.String()
		}

	case models.NotificationTypeFollowRequest:
		title = "Follow Request"
		body = fmt.Sprintf("%s wants to follow you", actorName)
		if req.ActorHandle != "" {
			data["follower_id"] = req.ActorHandle
		} else {
			data["follower_id"] = req.ActorID.String()
		}

	case models.NotificationTypeFollowAccept:
		title = "Request Accepted"
		body = fmt.Sprintf("%s accepted your follow request", actorName)

	case models.NotificationTypeSave:
		title = "Post Saved"
		body = fmt.Sprintf("%s saved your %s", actorName, s.formatPostType(req.PostType))

	case models.NotificationTypeMessage:
		title = fmt.Sprintf("%s ✉️", actorName)
		body = fmt.Sprintf("%s sent you a message", actorName)

	case models.NotificationTypeBeaconVouch:
		title = "Beacon Vouched"
		body = fmt.Sprintf("%s vouched for your beacon", actorName)
		data["beacon_id"] = req.PostID.String()

	case models.NotificationTypeBeaconReport:
		title = "Beacon Reported"
		body = fmt.Sprintf("%s reported your beacon", actorName)
		data["beacon_id"] = req.PostID.String()

	case models.NotificationTypeQuipReaction:
		if emoji != "" {
			title = fmt.Sprintf("%s %s", actorName, emoji)
			body = fmt.Sprintf("%s reacted %s to your quip", actorName, emoji)
		} else {
			title = "New Reaction"
			body = fmt.Sprintf("%s reacted to your quip", actorName)
		}

	case models.NotificationTypeGroupPost:
		groupName := getString(req.Metadata, "group_name")
		title = fmt.Sprintf("%s posted", actorName)
		if groupName != "" {
			body = fmt.Sprintf("%s shared a new post in %s", actorName, groupName)
		} else {
			body = fmt.Sprintf("%s shared a new post in your group", actorName)
		}
		if groupID := getString(req.Metadata, "group_id"); groupID != "" {
			data["group_id"] = groupID
		}

	case models.NotificationTypeGroupComment:
		groupName := getString(req.Metadata, "group_name")
		title = fmt.Sprintf("%s 💬", actorName)
		if groupName != "" {
			body = fmt.Sprintf("%s commented on your post in %s", actorName, groupName)
		} else {
			body = fmt.Sprintf("%s commented on your group post", actorName)
		}
		if groupID := getString(req.Metadata, "group_id"); groupID != "" {
			data["group_id"] = groupID
		}

	case models.NotificationTypeGroupLike:
		groupName := getString(req.Metadata, "group_name")
		title = fmt.Sprintf("%s ❤️", actorName)
		if groupName != "" {
			body = fmt.Sprintf("%s liked your post in %s", actorName, groupName)
		} else {
			body = fmt.Sprintf("%s liked your group post", actorName)
		}
		if groupID := getString(req.Metadata, "group_id"); groupID != "" {
			data["group_id"] = groupID
		}

	case models.NotificationTypeGroupInvite:
		groupName := getString(req.Metadata, "group_name")
		title = "Added to Group"
		if groupName != "" {
			body = fmt.Sprintf("%s added you to %s", actorName, groupName)
		} else {
			body = fmt.Sprintf("%s added you to a group", actorName)
		}
		if groupID := getString(req.Metadata, "group_id"); groupID != "" {
			data["group_id"] = groupID
		}

	case models.NotificationTypeGroupThread:
		groupName := getString(req.Metadata, "group_name")
		title = fmt.Sprintf("%s started a thread", actorName)
		if groupName != "" {
			body = fmt.Sprintf("%s started a new discussion in %s", actorName, groupName)
		} else {
			body = fmt.Sprintf("%s started a new discussion in your group", actorName)
		}
		if groupID := getString(req.Metadata, "group_id"); groupID != "" {
			data["group_id"] = groupID
		}

	case models.NotificationTypeGroupReply:
		groupName := getString(req.Metadata, "group_name")
		title = fmt.Sprintf("%s replied 💬", actorName)
		if groupName != "" {
			body = fmt.Sprintf("%s replied to your thread in %s", actorName, groupName)
		} else {
			body = fmt.Sprintf("%s replied to your forum thread", actorName)
		}
		if groupID := getString(req.Metadata, "group_id"); groupID != "" {
			data["group_id"] = groupID
		}

	case models.NotificationTypeNSFWWarning:
		title = "Content Labeled as Sensitive"
		body = "Your post was automatically labeled as NSFW. Please label sensitive content when posting to avoid further action."
		data["target"] = "main_feed"

	case models.NotificationTypeContentRemoved:
		title = "Content Removed"
		body = "Your post was removed for violating community guidelines. You can appeal this decision in your profile settings."
		data["target"] = "profile_settings"

	default:
		title = "Sojorn"
		body = "You have a new notification"
	}

	return title, body, data
}

func (s *NotificationService) getNavigationTarget(notifType, postType string) string {
	switch notifType {
	case models.NotificationTypeMessage:
		return "secure_chat"
	case models.NotificationTypeFollow, models.NotificationTypeFollowRequest, models.NotificationTypeFollowAccept:
		return "profile"
	case models.NotificationTypeBeaconVouch, models.NotificationTypeBeaconReport:
		return "beacon_map"
	case models.NotificationTypeQuipReaction:
		return "quip_feed"
	case models.NotificationTypeGroupPost, models.NotificationTypeGroupComment,
		models.NotificationTypeGroupLike, models.NotificationTypeGroupInvite,
		models.NotificationTypeGroupThread, models.NotificationTypeGroupReply:
		return "group"
	default:
		switch postType {
		case "beacon":
			return "beacon_map"
		case "quip":
			return "quip_feed"
		default:
			return "main_feed"
		}
	}
}

func (s *NotificationService) formatPostType(postType string) string {
	switch postType {
	case "beacon":
		return "beacon"
	case "quip":
		return "quip"
	default:
		return "post"
	}
}

// ============================================================================
// Legacy Compatibility Method
// ============================================================================

// CreateNotification is the legacy method for backwards compatibility
func (s *NotificationService) CreateNotification(ctx context.Context, userID, actorID, notificationType string, postID *string, commentID *string, metadata map[string]interface{}) error {
	actorName := getString(metadata, "actor_name")
	postType := getString(metadata, "post_type")

	req := models.PushNotificationRequest{
		UserID:   uuid.MustParse(userID),
		Type:     notificationType,
		ActorID:  uuid.MustParse(actorID),
		PostType: postType,
		Priority: models.PriorityNormal,
		Metadata: metadata,
	}

	if postID != nil {
		req.PostID = uuidPtr(*postID)
	}
	if commentID != nil {
		req.CommentID = uuidPtr(*commentID)
	}
	if actorName != "" {
		req.ActorName = actorName
	}

	return s.sendNotification(ctx, req)
}

// ============================================================================
// Helpers
// ============================================================================

func uuidPtr(s string) *uuid.UUID {
	if s == "" {
		return nil
	}
	u, err := uuid.Parse(s)
	if err != nil {
		return nil
	}
	return &u
}

func ptrString(s string) *string {
	return &s
}

// Helper functions
func getString(m map[string]interface{}, key string) string {
	if val, ok := m[key]; ok {
		if str, ok := val.(string); ok {
			return str
		}
		if sPtr, ok := val.(*string); ok && sPtr != nil {
			return *sPtr
		}
	}
	return ""
}
