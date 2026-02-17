package services

import (
	"context"
	"fmt"
	"os"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/repository"
	"github.com/rs/zerolog/log"
	"google.golang.org/api/option"
)

type PushService struct {
	client   *messaging.Client
	userRepo *repository.UserRepository
}

func NewPushService(userRepo *repository.UserRepository, credentialsFile string) (*PushService, error) {
	ctx := context.Background()
	var opt option.ClientOption

	if credentialsFile != "" {
		if _, err := os.Stat(credentialsFile); err == nil {
			opt = option.WithCredentialsFile(credentialsFile)
		} else {
			log.Warn().Msg("Firebase credentials file not found, using default credentials")
			opt = option.WithoutAuthentication()
		}
	} else {
		opt = option.WithCredentialsFile("firebase-service-account.json")
	}

	app, err := firebase.NewApp(ctx, nil, opt)
	if err != nil {
		return nil, fmt.Errorf("error initializing app: %v", err)
	}

	client, err := app.Messaging(ctx)
	if err != nil {
		return nil, fmt.Errorf("error getting Messaging client: %v", err)
	}

	log.Info().Msg("[INFO] PushService initialized successfully")

	return &PushService{
		client:   client,
		userRepo: userRepo,
	}, nil
}

// SendPush sends a push notification to all user devices
func (s *PushService) SendPush(ctx context.Context, userID, title, body string, data map[string]string) error {
	return s.SendPushWithBadge(ctx, userID, title, body, data, 0)
}

// SendPushWithBadge sends a push notification with badge count for iOS
func (s *PushService) SendPushWithBadge(ctx context.Context, userID, title, body string, data map[string]string, badge int) error {
	tokens, err := s.userRepo.GetFCMTokens(ctx, userID)
	if err != nil {
		return fmt.Errorf("failed to get FCM tokens: %w", err)
	}

	if len(tokens) == 0 {
		log.Debug().Str("user_id", userID).Msg("No FCM tokens found for user")
		return nil
	}

	// Build the message
	message := &messaging.MulticastMessage{
		Tokens: tokens,
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Data: data,
		Android: &messaging.AndroidConfig{
			Priority: "high",
			Notification: &messaging.AndroidNotification{
				Sound:                 "default",
				ClickAction:           "FLUTTER_NOTIFICATION_CLICK",
				ChannelID:             "sojorn_notifications",
				DefaultSound:          true,
				DefaultVibrateTimings: true,
				NotificationCount:     func() *int { c := badge; return &c }(),
			},
		},
		APNS: &messaging.APNSConfig{
			Headers: map[string]string{
				"apns-priority": "10",
			},
			Payload: &messaging.APNSPayload{
				Aps: &messaging.Aps{
					Sound:            "default",
					Badge:            &badge,
					MutableContent:   true,
					ContentAvailable: true,
				},
			},
		},
		Webpush: &messaging.WebpushConfig{
			Notification: &messaging.WebpushNotification{
				Title: title,
				Body:  body,
				Icon:  "/icons/icon-192.png",
				Badge: "/icons/badge-72.png",
				Data:  data,
			},
			FCMOptions: &messaging.WebpushFCMOptions{
				Link: buildDeepLink(data),
			},
		},
	}

	br, err := s.client.SendEachForMulticast(ctx, message)
	if err != nil {
		return fmt.Errorf("error sending multicast message: %w", err)
	}

	log.Debug().
		Str("user_id", userID).
		Int("success_count", br.SuccessCount).
		Int("failure_count", br.FailureCount).
		Msg("Push notification sent")

	if br.FailureCount > 0 {
		s.handleFailedTokens(ctx, userID, tokens, br.Responses)
	}

	return nil
}

// SendPushToTopics sends a push notification to a topic
func (s *PushService) SendPushToTopic(ctx context.Context, topic, title, body string, data map[string]string) error {
	message := &messaging.Message{
		Topic: topic,
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Data: data,
		Android: &messaging.AndroidConfig{
			Priority: "high",
		},
		APNS: &messaging.APNSConfig{
			Payload: &messaging.APNSPayload{
				Aps: &messaging.Aps{
					Sound: "default",
				},
			},
		},
	}

	_, err := s.client.Send(ctx, message)
	return err
}

// SendSilentPush sends a data-only notification for badge updates
func (s *PushService) SendSilentPush(ctx context.Context, userID string, data map[string]string, badge int) error {
	tokens, err := s.userRepo.GetFCMTokens(ctx, userID)
	if err != nil || len(tokens) == 0 {
		return err
	}

	message := &messaging.MulticastMessage{
		Tokens: tokens,
		Data:   data,
		Android: &messaging.AndroidConfig{
			Priority: "normal",
		},
		APNS: &messaging.APNSConfig{
			Payload: &messaging.APNSPayload{
				Aps: &messaging.Aps{
					Badge:            &badge,
					ContentAvailable: true,
				},
			},
		},
	}

	_, err = s.client.SendEachForMulticast(ctx, message)
	return err
}

// handleFailedTokens removes invalid tokens from the database
func (s *PushService) handleFailedTokens(ctx context.Context, userID string, tokens []string, responses []*messaging.SendResponse) {
	var invalidTokens []string

	for idx, resp := range responses {
		if !resp.Success {
			if resp.Error != nil && messaging.IsRegistrationTokenNotRegistered(resp.Error) {
				invalidTokens = append(invalidTokens, tokens[idx])
				if err := s.userRepo.DeleteFCMToken(ctx, userID, tokens[idx]); err != nil {
					log.Warn().Err(err).Str("user_id", userID).Msg("Failed to delete invalid FCM token")
				}
			} else if resp.Error != nil {
				log.Warn().
					Err(resp.Error).
					Str("user_id", userID).
					Str("token", tokens[idx][:min(20, len(tokens[idx]))]).
					Msg("FCM send failed for token")
			}
		}
	}

	if len(invalidTokens) > 0 {
		log.Info().
			Str("user_id", userID).
			Int("count", len(invalidTokens)).
			Msg("Cleaned up invalid FCM tokens")
	}
}

// buildDeepLink creates a deep link URL from notification data
func buildDeepLink(data map[string]string) string {
	target := data["target"]
	baseURL := "https://sojorn.net"

	switch target {
	case "secure_chat":
		if convID, ok := data["conversation_id"]; ok {
			return fmt.Sprintf("%s/secure-chat/%s", baseURL, convID)
		}
		return baseURL + "/secure-chat"
	case "profile":
		if followerID, ok := data["follower_id"]; ok {
			return fmt.Sprintf("%s/u/%s", baseURL, followerID)
		}
		return baseURL + "/profile"
	case "beacon_map":
		return baseURL + "/beacon"
	case "quip_feed":
		return baseURL + "/quips"
	case "thread_view":
		if postID, ok := data["post_id"]; ok {
			return fmt.Sprintf("%s/p/%s", baseURL, postID)
		}
		return baseURL
	default:
		if postID, ok := data["post_id"]; ok {
			return fmt.Sprintf("%s/p/%s", baseURL, postID)
		}
		return baseURL
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
