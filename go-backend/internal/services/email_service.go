// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/smtp"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/config"
	"github.com/rs/zerolog/log"
)

type EmailService struct {
	config       *config.Config
	pool         *pgxpool.Pool
	token        string
	tokenExpires time.Time
	mu           sync.Mutex
}

func NewEmailService(cfg *config.Config, pool *pgxpool.Pool) *EmailService {
	return &EmailService{config: cfg, pool: pool}
}

type dbTemplate struct {
	Subject     string
	Title       string
	Header      string
	Content     string
	ButtonText  string
	ButtonURL   string
	ButtonColor string
	Footer      string
	TextBody    string
	Enabled     bool
}

func (s *EmailService) getTemplate(slug string) *dbTemplate {
	if s.pool == nil {
		return nil
	}
	var t dbTemplate
	err := s.pool.QueryRow(context.Background(),
		`SELECT subject, title, header, content, button_text, button_url, button_color, footer, text_body, enabled
		 FROM email_templates WHERE slug = $1`, slug).
		Scan(&t.Subject, &t.Title, &t.Header, &t.Content, &t.ButtonText, &t.ButtonURL, &t.ButtonColor, &t.Footer, &t.TextBody, &t.Enabled)
	if err != nil {
		log.Debug().Str("slug", slug).Err(err).Msg("Email template not found in DB, using hardcoded fallback")
		return nil
	}
	if !t.Enabled {
		log.Info().Str("slug", slug).Msg("Email template disabled, skipping send")
		return &t
	}
	return &t
}

func (s *EmailService) sendFromTemplate(slug string, replacements map[string]string, toEmail, toName string, fallback func() error) error {
	t := s.getTemplate(slug)
	if t == nil {
		return fallback()
	}
	if !t.Enabled {
		return nil
	}

	r := func(s string) string {
		for k, v := range replacements {
			s = strings.ReplaceAll(s, k, v)
		}
		return s
	}

	subject := r(t.Subject)
	title := r(t.Title)
	header := r(t.Header)
	content := r(t.Content)
	buttonText := r(t.ButtonText)
	buttonURL := r(t.ButtonURL)
	footer := r(t.Footer)
	textBody := r(t.TextBody)
	buttonColor := t.ButtonColor
	if buttonColor == "" {
		buttonColor = "#4338CA"
	}

	htmlBody := s.BuildHTMLEmailWithColor(title, header, content, buttonURL, buttonText, footer, buttonColor)
	return s.sendEmail(toEmail, toName, subject, htmlBody, textBody)
}

// SendPulse API Structs
type sendPulseAuthResponse struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	ExpiresIn   int    `json:"expires_in"`
}


type sendPulseEmailRequest struct {
	Email sendPulseEmailData `json:"email"`
}

type sendPulseEmailData struct {
	HTML    string              `json:"html"`
	Text    string              `json:"text"`
	Subject string              `json:"subject"`
	From    sendPulseIdentity   `json:"from"`
	To      []sendPulseIdentity `json:"to"`
}

type sendPulseIdentity struct {
	Name  string `json:"name"`
	Email string `json:"email"`
}

func (s *EmailService) SendVerificationEmail(toEmail, toName, token string) error {
	apiBase := strings.TrimSuffix(s.config.APIBaseURL, "/api/v1")
	verifyURL := fmt.Sprintf("%s/api/v1/auth/verify?token=%s", apiBase, url.QueryEscape(token))

	name := toName
	if name == "" {
		name = "there"
	}

	return s.sendFromTemplate("verification", map[string]string{
		"{{name}}":       name,
		"{{verify_url}}": verifyURL,
	}, toEmail, toName, func() error {
		subject := "Verify your Sojorn account"
		title := "Email Verification"
		header := fmt.Sprintf("Hey %s!", name)

		content := `
		<p>Welcome to Sojorn &mdash; your vibrant new social space. We're thrilled to have you join our community!</p>
		<p>To get started in the app, please verify your email address by clicking the button below:</p>
	`
		footer := fmt.Sprintf(`
		<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" style="margin-top: 24px;">
			<tr><td style="background: #F9FAFB; border-radius: 8px; padding: 16px;">
				<p style="font-size: 13px; color: #9CA3AF; margin: 0 0 8px 0;">If the button above doesn't work, copy and paste this link into your browser:</p>
				<a href="%s" style="color: #4338CA; text-decoration: underline; word-break: break-all; font-size: 13px;">%s</a>
			</td></tr>
		</table>
	`, verifyURL, verifyURL)

		htmlBody := s.buildHTMLEmail(title, header, content, verifyURL, "Verify My Email", footer)
		textBody := fmt.Sprintf("Welcome to Sojorn!\n\nPlease verify your email by visiting this link:\n\n%s\n\nIf you did not create an account, you can ignore this email.", verifyURL)
		return s.sendEmail(toEmail, toName, subject, htmlBody, textBody)
	})
}

func (s *EmailService) SendPasswordResetEmail(toEmail, toName, token string) error {
	resetURL := fmt.Sprintf("%s/reset-password?token=%s", s.config.AppBaseURL, url.QueryEscape(token))

	return s.sendFromTemplate("password_reset", map[string]string{
		"{{name}}":      toName,
		"{{reset_url}}": resetURL,
	}, toEmail, toName, func() error {
		subject := "Reset your Sojorn password"
		title := "Password Reset"
		header := "Reset your password"
		content := fmt.Sprintf(`
		<p>Hey %s,</p>
		<p>You requested a password reset for your Sojorn account. Click the button below to set a new password:</p>
	`, toName)

		footer := fmt.Sprintf(`
		<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" style="margin-top: 24px;">
			<tr><td style="background: #F9FAFB; border-radius: 8px; padding: 16px;">
				<p style="font-size: 13px; color: #9CA3AF; margin: 0 0 8px 0;">If the button doesn't work, copy and paste this link:</p>
				<a href="%s" style="color: #4338CA; text-decoration: underline; word-break: break-all; font-size: 13px;">%s</a>
			</td></tr>
		</table>
		<p style="color: #9CA3AF; font-size: 12px; margin-top: 16px;">This link expires in 1 hour. If you did not request this, you can safely ignore this email.</p>
	`, resetURL, resetURL)

		htmlBody := s.buildHTMLEmail(title, header, content, resetURL, "Reset Password", footer)
		textBody := fmt.Sprintf("Reset your Sojorn password by visiting this link:\n\n%s\n\nThis link expires in 1 hour.", resetURL)
		return s.sendEmail(toEmail, toName, subject, htmlBody, textBody)
	})
}

func (s *EmailService) sendEmail(toEmail, toName, subject, htmlBody, textBody string) error {
	// SendPulse API (only if credentials are set)
	if s.config.SendPulseID != "" && s.config.SendPulseSecret != "" {
		return s.sendViaSendPulse(toEmail, toName, subject, htmlBody, textBody)
	}

	// Direct SMTP (PurelyMail, Gmail, any SMTP relay)
	if s.config.SMTPHost != "" && s.config.SMTPUser != "" {
		return s.sendViaSMTP(toEmail, toName, subject, htmlBody, textBody)
	}

	log.Warn().Msg("No email provider configured, skipping send")
	return nil
}

// sendViaSMTP sends a multipart/alternative email (HTML + plain text) via SMTP with PLAIN auth.
func (s *EmailService) sendViaSMTP(toEmail, toName, subject, htmlBody, textBody string) error {
	fromEmail := s.config.SMTPFrom
	if fromEmail == "" {
		fromEmail = s.config.SMTPUser
	}

	auth := smtp.PlainAuth("", s.config.SMTPUser, s.config.SMTPPass, s.config.SMTPHost)

	boundary := "sojorn-mime-alt-boundary"
	var msg strings.Builder
	msg.WriteString("From: Sojorn <" + fromEmail + ">\r\n")
	msg.WriteString("To: " + toName + " <" + toEmail + ">\r\n")
	msg.WriteString("Subject: " + subject + "\r\n")
	msg.WriteString("MIME-Version: 1.0\r\n")
	msg.WriteString("Content-Type: multipart/alternative; boundary=\"" + boundary + "\"\r\n")
	msg.WriteString("\r\n")
	msg.WriteString("--" + boundary + "\r\n")
	msg.WriteString("Content-Type: text/plain; charset=UTF-8\r\n\r\n")
	msg.WriteString(textBody + "\r\n\r\n")
	msg.WriteString("--" + boundary + "\r\n")
	msg.WriteString("Content-Type: text/html; charset=UTF-8\r\n\r\n")
	msg.WriteString(htmlBody + "\r\n\r\n")
	msg.WriteString("--" + boundary + "--\r\n")

	addr := fmt.Sprintf("%s:%d", s.config.SMTPHost, s.config.SMTPPort)
	if err := smtp.SendMail(addr, auth, fromEmail, []string{toEmail}, []byte(msg.String())); err != nil {
		log.Error().Err(err).Str("to", toEmail).Msg("SMTP send failed")
		return err
	}
	log.Info().Str("to", toEmail).Str("host", s.config.SMTPHost).Msg("Email sent via SMTP")
	return nil
}

func (s *EmailService) getSendPulseToken() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.token != "" && time.Now().Before(s.tokenExpires) {
		return s.token, nil
	}

	url := "https://api.sendpulse.com/oauth/access_token"
	payload := map[string]string{
		"grant_type":    "client_credentials",
		"client_id":     s.config.SendPulseID,
		"client_secret": s.config.SendPulseSecret,
	}
	jsonData, _ := json.Marshal(payload)

	resp, err := http.Post(url, "application/json", bytes.NewBuffer(jsonData))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		log.Error().Str("body", string(body)).Int("status", resp.StatusCode).Msg("Failed to get SendPulse Token")
		return "", fmt.Errorf("failed to auth sendpulse: %d", resp.StatusCode)
	}

	var authResp sendPulseAuthResponse
	if err := json.NewDecoder(resp.Body).Decode(&authResp); err != nil {
		return "", err
	}

	s.token = authResp.AccessToken
	s.tokenExpires = time.Now().Add(time.Duration(authResp.ExpiresIn-60) * time.Second) // Buffer 60s
	log.Info().Msg("Authenticated with SendPulse")

	return s.token, nil
}

func (s *EmailService) sendViaSendPulse(toEmail, toName, subject, htmlBody, textBody string) error {
	token, err := s.getSendPulseToken()
	if err != nil {
		return err
	}

	url := "https://api.sendpulse.com/smtp/emails"

	// Determine correct FROM email
	fromEmail := s.config.SMTPFrom
	if fromEmail == "" {
		fromEmail = "no-reply@sojorn.net"
	}

	reqBody := sendPulseEmailRequest{
		Email: sendPulseEmailData{
			HTML:    htmlBody,
			Text:    textBody,
			Subject: subject,
			From: sendPulseIdentity{
				Name:  "Sojorn",
				Email: fromEmail,
			},
			To: []sendPulseIdentity{
				{Name: toName, Email: toEmail},
			},
		},
	}

	// Use a buffer with SetEscapeHTML(false) so that HTML angle brackets
	// are sent as literal < > characters, not \u003c \u003e unicode escapes.
	// Go's default json.Marshal escapes HTML which breaks email rendering.
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.Encode(reqBody)
	log.Debug().Int("html_len", len(htmlBody)).Int("text_len", len(textBody)).Msg("SendPulse outgoing email")
	req, err := http.NewRequest("POST", url, &buf)
	if err != nil {
		return err
	}

	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		log.Error().Err(err).Msg("Failed to call SendPulse API")
		return err
	}
	defer resp.Body.Close()

	bodyBytes, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		log.Error().Int("status", resp.StatusCode).Str("body", string(bodyBytes)).Msg("SendPulse API Error")

		// If 401, maybe token expired? Reset token and retry once?
		if resp.StatusCode == 401 {
			s.mu.Lock()
			s.token = ""
			s.mu.Unlock()
			// Simple retry logic could be added here
		}

		return fmt.Errorf("sendpulse error: %s", string(bodyBytes))
	}

	log.Info().Str("response", string(bodyBytes)).Msgf("Email sent to %s via SendPulse", toEmail)
	return nil
}

func (s *EmailService) SendBanNotificationEmail(toEmail, toName, reason string) error {
	return s.sendFromTemplate("ban_notification", map[string]string{
		"{{name}}":   toName,
		"{{reason}}": reason,
	}, toEmail, toName, func() error {
		subject := "Your Sojorn account has been suspended"
		title := "Account Suspended"
		header := "Your account has been suspended"
		content := fmt.Sprintf(`
		<p>Hi %s,</p>
		<p>After a review of your recent activity, your Sojorn account has been <strong>permanently suspended</strong> for violating our <a href="https://mp.ls/terms" style="color: #4338CA;">Community Guidelines</a>.</p>
		<p style="background: #FEF2F2; border-left: 4px solid #EF4444; padding: 12px 16px; border-radius: 4px; margin: 16px 0;">
			<strong>Reason:</strong> %s
		</p>
		<p>If you believe this action was taken in error, you can submit an appeal.</p>
	`, toName, reason)

		appealURL := "mailto:appeals@sojorn.net?subject=Account%%20Appeal"
		footer := `<p style="color: #9CA3AF; font-size: 12px; margin-top: 16px;">You can also reply directly to this email to submit your appeal.</p>`
		htmlBody := s.buildHTMLEmail(title, header, content, appealURL, "Submit an Appeal", footer)
		textBody := fmt.Sprintf("Hi %s,\n\nYour Sojorn account has been permanently suspended.\n\nReason: %s\n\nIf you believe this was in error, reply to this email or contact appeals@sojorn.net.\n\n— The Sojorn Team", toName, reason)
		return s.sendEmail(toEmail, toName, subject, htmlBody, textBody)
	})
}

func (s *EmailService) SendSuspensionNotificationEmail(toEmail, toName, reason, duration string) error {
	return s.sendFromTemplate("suspension_notification", map[string]string{
		"{{name}}":     toName,
		"{{reason}}":   reason,
		"{{duration}}": duration,
	}, toEmail, toName, func() error {
		subject := "Your Sojorn account has been temporarily suspended"
		title := "Account Temporarily Suspended"
		header := "Your account has been temporarily suspended"
		content := fmt.Sprintf(`
		<p>Hi %s,</p>
		<p>Your Sojorn account has been <strong>temporarily suspended for %s</strong> due to a violation of our <a href="https://mp.ls/terms" style="color: #4338CA;">Community Guidelines</a>.</p>
		<p style="background: #FFFBEB; border-left: 4px solid #F59E0B; padding: 12px 16px; border-radius: 4px; margin: 16px 0;">
			<strong>Reason:</strong> %s
		</p>
		<p>Your account will be automatically restored after the suspension period.</p>
	`, toName, duration, reason)

		htmlBody := s.buildHTMLEmail(title, header, content, "https://mp.ls/terms", "Review Community Guidelines", "")
		textBody := fmt.Sprintf("Hi %s,\n\nYour Sojorn account has been temporarily suspended for %s.\n\nReason: %s\n\nYour account will be restored after the suspension period.\n\n— The Sojorn Team", toName, duration, reason)
		return s.sendEmail(toEmail, toName, subject, htmlBody, textBody)
	})
}

func (s *EmailService) SendAccountRestoredEmail(toEmail, toName, reason string) error {
	return s.sendFromTemplate("account_restored", map[string]string{
		"{{name}}":   toName,
		"{{reason}}": reason,
	}, toEmail, toName, func() error {
		subject := "Your Sojorn account has been restored"
		title := "Account Restored"
		header := "Welcome back!"
		content := fmt.Sprintf(`
		<p>Hi %s,</p>
		<p>Great news — your Sojorn account has been <strong>restored</strong> and is fully active again.</p>
		<p style="background: #F0FDF4; border-left: 4px solid #22C55E; padding: 12px 16px; border-radius: 4px; margin: 16px 0;">
			<strong>Note:</strong> %s
		</p>
		<p>All of your previous posts and comments have been restored and are visible again.</p>
	`, toName, reason)

		htmlBody := s.buildHTMLEmail(title, header, content, "https://mp.ls/sojorn", "Open Sojorn", "")
		textBody := fmt.Sprintf("Hi %s,\n\nYour Sojorn account has been restored and is fully active again.\n\nNote: %s\n\nAll of your posts and comments are visible again.\n\n— The Sojorn Team", toName, reason)
		return s.sendEmail(toEmail, toName, subject, htmlBody, textBody)
	})
}

func (s *EmailService) SendDeactivationEmail(toEmail, toName string) error {
	return s.sendFromTemplate("deactivation", map[string]string{
		"{{name}}": toName,
	}, toEmail, toName, func() error {
		subject := "Your Sojorn account has been deactivated"
		title := "Account Deactivated"
		header := "Your account has been deactivated"
		content := fmt.Sprintf(`
		<p>Hey %s,</p>
		<p>Your Sojorn account has been deactivated. Your profile is now hidden from other users.</p>
		<ul style="text-align: left; color: #4B5563;">
			<li>Your profile, posts, and connections are hidden but <strong>fully preserved</strong></li>
			<li>No one can see your account while it is deactivated</li>
			<li>You can reactivate at any time simply by <strong>logging back in</strong></li>
		</ul>
	`, toName)

		htmlBody := s.buildHTMLEmail(title, header, content, "https://mp.ls/sojorn", "Log In to Reactivate", "")
		textBody := fmt.Sprintf("Hey %s,\n\nYour Sojorn account has been deactivated. Your profile is now hidden.\n\nLog back in at any time to reactivate.\n\n— The Sojorn Team", toName)
		return s.sendEmail(toEmail, toName, subject, htmlBody, textBody)
	})
}

func (s *EmailService) SendDeletionScheduledEmail(toEmail, toName, deletionDate string) error {
	return s.sendFromTemplate("deletion_scheduled", map[string]string{
		"{{name}}":          toName,
		"{{deletion_date}}": deletionDate,
	}, toEmail, toName, func() error {
		subject := "Your Sojorn account is scheduled for deletion"
		title := "Account Deletion Scheduled"
		header := "Your account is scheduled for deletion"
		content := fmt.Sprintf(`
		<p>Hey %s,</p>
		<p>Your Sojorn account has been scheduled for <strong>permanent deletion on %s</strong>.</p>
		<ul style="text-align: left; color: #4B5563;">
			<li>Your account is immediately deactivated and hidden</li>
			<li>On <strong>%s</strong>, all data will be permanently destroyed</li>
			<li>This includes posts, messages, encryption keys, profile, followers, and your handle</li>
		</ul>
		<p style="background: #F0FDF4; border-left: 4px solid #22C55E; padding: 12px 16px; border-radius: 4px; margin: 16px 0;">
			<strong>Changed your mind?</strong> Simply log back in before %s to cancel.
		</p>
	`, toName, deletionDate, deletionDate, deletionDate)

		htmlBody := s.buildHTMLEmail(title, header, content, "https://mp.ls/sojorn", "Log In to Cancel Deletion", "")
		textBody := fmt.Sprintf("Hey %s,\n\nYour Sojorn account has been scheduled for permanent deletion on %s.\n\nLog back in before %s to cancel.\n\n— The Sojorn Team", toName, deletionDate, deletionDate)
		return s.sendEmail(toEmail, toName, subject, htmlBody, textBody)
	})
}

func (s *EmailService) SendDestroyConfirmationEmail(toEmail, toName, confirmURL string) error {
	return s.sendFromTemplate("destroy_confirmation", map[string]string{
		"{{name}}":        toName,
		"{{confirm_url}}": confirmURL,
	}, toEmail, toName, func() error {
		subject := "FINAL WARNING: Confirm Permanent Account Destruction"
		title := "Account Destruction"
		header := "Confirm account destruction"
		content := fmt.Sprintf(`
		<p>Hey %s,</p>
		<p>You requested <strong>immediate and permanent destruction</strong> of your Sojorn account.</p>
		<p style="background: #FEF2F2; border-left: 4px solid #DC2626; padding: 12px 16px; border-radius: 4px; margin: 16px 0;">
			<strong>THIS ACTION IS IRREVERSIBLE</strong>
		</p>
		<ul style="text-align: left; color: #4B5563;">
			<li>All your posts, comments, and media will be permanently deleted</li>
			<li>All your messages and encryption keys will be destroyed</li>
			<li>Your profile, followers, and social connections will be erased</li>
			<li>Your handle will be released and cannot be reclaimed</li>
			<li><strong>There is no recovery. No backup. No undo.</strong></li>
		</ul>
		<p>If you are absolutely certain, click the button below.</p>
	`, toName)

		footer := `<p style="color: #9CA3AF; font-size: 13px; margin-top: 16px;">This link expires in 1 hour. If you did not request this, ignore this email.</p>`
		htmlBody := s.BuildHTMLEmailWithColor(title, header, content, confirmURL, "PERMANENTLY DESTROY MY ACCOUNT", footer, "#DC2626")
		textBody := fmt.Sprintf("FINAL WARNING\n\nHey %s,\n\nYou requested IMMEDIATE AND PERMANENT DESTRUCTION of your Sojorn account.\n\nTo confirm, visit:\n%s\n\nThis link expires in 1 hour.\n\n— The Sojorn Team", toName, confirmURL)
		return s.sendEmail(toEmail, toName, subject, htmlBody, textBody)
	})
}

func (s *EmailService) SendContentRemovalEmail(toEmail, toName, contentType, reason string, strikeCount int) error {
	strikeWarning := ""
	if strikeCount >= 5 {
		strikeWarning = `<p style="background: #FEF2F2; border-left: 4px solid #EF4444; padding: 12px 16px; border-radius: 4px; margin: 16px 0;"><strong>Warning:</strong> You are close to a permanent suspension.</p>`
	} else if strikeCount >= 3 {
		strikeWarning = `<p style="background: #FFFBEB; border-left: 4px solid #F59E0B; padding: 12px 16px; border-radius: 4px; margin: 16px 0;"><strong>Warning:</strong> Continued violations may result in suspension.</p>`
	}

	return s.sendFromTemplate("content_removal", map[string]string{
		"{{name}}":           toName,
		"{{content_type}}":   contentType,
		"{{reason}}":         reason,
		"{{strike_count}}":   fmt.Sprintf("%d", strikeCount),
		"{{strike_warning}}": strikeWarning,
	}, toEmail, toName, func() error {
		subject := fmt.Sprintf("Your %s on Sojorn was removed", contentType)
		title := "Content Removed"
		header := fmt.Sprintf("Your %s has been removed", contentType)

		content := fmt.Sprintf(`
		<p>Hi %s,</p>
		<p>One of your %ss has been removed by our moderation team for violating our <a href="https://mp.ls/terms" style="color: #4338CA;">Community Guidelines</a>.</p>
		<p style="background: #FEF2F2; border-left: 4px solid #EF4444; padding: 12px 16px; border-radius: 4px; margin: 16px 0;">
			<strong>Reason:</strong> %s
		</p>
		<p>This is <strong>strike %d</strong> on your account.</p>
		%s
		<p>If you believe this was in error, you can reply to this email.</p>
	`, toName, contentType, reason, strikeCount, strikeWarning)

		htmlBody := s.buildHTMLEmail(title, header, content, "https://mp.ls/terms", "Review Community Guidelines", "")
		textBody := fmt.Sprintf("Hi %s,\n\nYour %s has been removed.\n\nReason: %s\nStrike %d on your account.\n\n— The Sojorn Team", toName, contentType, reason, strikeCount)
		return s.sendEmail(toEmail, toName, subject, htmlBody, textBody)
	})
}

// SendGenericEmail sends an email with pre-built HTML and text bodies
func (s *EmailService) SendGenericEmail(toEmail, toName, subject, htmlBody, textBody string) error {
	return s.sendEmail(toEmail, toName, subject, htmlBody, textBody)
}

func (s *EmailService) AddSubscriber(email, name string) {
}

func (s *EmailService) buildHTMLEmail(title, header, content, buttonURL, buttonText, footer string) string {
	return s.BuildHTMLEmailWithColor(title, header, content, buttonURL, buttonText, footer, "#4338CA")
}

func (s *EmailService) BuildHTMLEmailWithColor(title, header, content, buttonURL, buttonText, footer, buttonColor string) string {
	tpl := `<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="x-apple-disable-message-reformatting">
    <title>{{TITLE}}</title>
    <!--[if mso]>
    <noscript><xml><o:OfficeDocumentSettings><o:PixelsPerInch>96</o:PixelsPerInch></o:OfficeDocumentSettings></xml></noscript>
    <![endif]-->
    <style>
        body, table, td, a { -webkit-text-size-adjust: 100%; -ms-text-size-adjust: 100%; }
        table, td { mso-table-lspace: 0pt; mso-table-rspace: 0pt; }
        img { -ms-interpolation-mode: bicubic; border: 0; height: auto; line-height: 100%; outline: none; text-decoration: none; }
        body { margin: 0; padding: 0; width: 100% !important; }
        a[x-apple-data-detectors] { color: inherit !important; text-decoration: none !important; font-size: inherit !important; font-family: inherit !important; font-weight: inherit !important; line-height: inherit !important; }
    </style>
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; margin: 0; padding: 0; background-color: #F3F4F6; width: 100%;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color: #F3F4F6;">
        <tr><td style="padding: 40px 20px;">
            <table role="presentation" width="520" cellpadding="0" cellspacing="0" align="center" style="max-width: 520px; margin: 0 auto; background-color: #ffffff; border-radius: 16px; overflow: hidden;">
                <!-- Header -->
                <tr><td style="background-color: #4338CA; padding: 40px; text-align: center;">
                    <img src="https://mp.ls/img/sojornlogo.png" alt="Sojorn" width="80" height="80" style="width: 80px; height: 80px; border-radius: 20px; margin-bottom: 16px; display: block; margin-left: auto; margin-right: auto;">
                    <p style="color: #ffffff; font-size: 12px; font-weight: 600; letter-spacing: 1px; text-transform: uppercase; margin: 0;">{{TITLE}}</p>
                </td></tr>
                
                <!-- Content -->
                <tr><td style="padding: 40px; text-align: center; color: #374151;">
                    <h1 style="color: #1F2937; font-size: 24px; font-weight: 700; margin: 0 0 16px 0;">{{HEADER}}</h1>
                    <div style="font-size: 16px; line-height: 1.6; color: #4B5563; margin-bottom: 32px; text-align: left;">
                        {{CONTENT}}
                    </div>
                    
                    <!-- Button (table-based for Outlook) -->
                    <table role="presentation" cellpadding="0" cellspacing="0" align="center" style="margin: 0 auto;">
                        <tr><td style="background-color: {{BUTTON_COLOR}}; border-radius: 12px; text-align: center;">
                            <a href="{{BUTTON_URL}}" target="_blank" style="display: block; padding: 16px 40px; color: #ffffff; text-decoration: none; font-weight: 600; font-size: 16px; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">{{BUTTON_TEXT}}</a>
                        </td></tr>
                    </table>
                    
                    {{FOOTER}}
                </td></tr>
                
                <!-- Footer -->
                <tr><td style="padding: 32px; text-align: center; background-color: #F9FAFB; border-top: 1px solid #E5E7EB;">
                    <p style="font-size: 12px; color: #9CA3AF; margin: 0 0 8px 0;">&copy; 2026 Sojorn by MPLS LLC. All rights reserved.</p>
                    <p style="font-size: 12px; color: #9CA3AF; margin: 0;">
                        <a href="https://mp.ls/sojorn" style="color: #9CA3AF; text-decoration: none;">Website</a> &bull; 
                        <a href="https://mp.ls/privacy" style="color: #9CA3AF; text-decoration: none;">Privacy</a> &bull; 
                        <a href="https://mp.ls/terms" style="color: #9CA3AF; text-decoration: none;">Terms</a>
                    </p>
                </td></tr>
            </table>
        </td></tr>
    </table>
</body>
</html>`

	r := strings.NewReplacer(
		"{{TITLE}}", title,
		"{{HEADER}}", header,
		"{{CONTENT}}", content,
		"{{BUTTON_COLOR}}", buttonColor,
		"{{BUTTON_URL}}", buttonURL,
		"{{BUTTON_TEXT}}", buttonText,
		"{{FOOTER}}", footer,
	)
	return r.Replace(tpl)
}
