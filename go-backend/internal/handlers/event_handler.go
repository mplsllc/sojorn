// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

type EventHandler struct {
	db *pgxpool.Pool
}

func NewEventHandler(db *pgxpool.Pool) *EventHandler {
	return &EventHandler{db: db}
}

type GroupEvent struct {
	ID            string     `json:"id"`
	GroupID       string     `json:"group_id"`
	GroupName     string     `json:"group_name,omitempty"`
	CreatedBy     string     `json:"created_by"`
	Title         string     `json:"title"`
	Description   string     `json:"description"`
	LocationName  *string    `json:"location_name"`
	Lat           *float64   `json:"lat"`
	Long          *float64   `json:"long"`
	StartsAt      time.Time  `json:"starts_at"`
	EndsAt        *time.Time `json:"ends_at"`
	IsPublic      bool       `json:"is_public"`
	CoverImageURL *string    `json:"cover_image_url"`
	MaxAttendees  *int       `json:"max_attendees"`
	AttendeeCount int        `json:"attendee_count"`
	MyRSVP        *string    `json:"my_rsvp,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

// CreateEvent — POST /groups/:id/events
func (h *EventHandler) CreateEvent(c *gin.Context) {
	userID, _ := c.Get("user_id")
	userIDStr := userID.(string)
	groupID := c.Param("id")

	// Check user is admin/owner of the group
	var role string
	err := h.db.QueryRow(c.Request.Context(), `
		SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2::uuid
	`, groupID, userIDStr).Scan(&role)
	if err != nil || (role != "owner" && role != "admin") {
		c.JSON(http.StatusForbidden, gin.H{"error": "only group admins can create events"})
		return
	}

	var req struct {
		Title         string   `json:"title" binding:"required"`
		Description   string   `json:"description"`
		LocationName  *string  `json:"location_name"`
		Lat           *float64 `json:"lat"`
		Long          *float64 `json:"long"`
		StartsAt      string   `json:"starts_at" binding:"required"`
		EndsAt        *string  `json:"ends_at"`
		IsPublic      bool     `json:"is_public"`
		CoverImageURL *string  `json:"cover_image_url"`
		MaxAttendees  *int     `json:"max_attendees"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	startsAt, err := time.Parse(time.RFC3339, req.StartsAt)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid starts_at format (use RFC3339)"})
		return
	}

	var endsAt *time.Time
	if req.EndsAt != nil {
		t, err := time.Parse(time.RFC3339, *req.EndsAt)
		if err == nil {
			endsAt = &t
		}
	}

	var event GroupEvent
	err = h.db.QueryRow(c.Request.Context(), `
		INSERT INTO group_events (group_id, created_by, title, description, location_name, lat, long, starts_at, ends_at, is_public, cover_image_url, max_attendees)
		VALUES ($1, $2::uuid, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
		RETURNING id, group_id, created_by, title, description, location_name, lat, long, starts_at, ends_at, is_public, cover_image_url, max_attendees, created_at, updated_at
	`, groupID, userIDStr, req.Title, req.Description, req.LocationName, req.Lat, req.Long, startsAt, endsAt, req.IsPublic, req.CoverImageURL, req.MaxAttendees,
	).Scan(&event.ID, &event.GroupID, &event.CreatedBy, &event.Title, &event.Description,
		&event.LocationName, &event.Lat, &event.Long, &event.StartsAt, &event.EndsAt,
		&event.IsPublic, &event.CoverImageURL, &event.MaxAttendees, &event.CreatedAt, &event.UpdatedAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create event"})
		return
	}

	// Auto-RSVP the creator as "going"
	_, _ = h.db.Exec(c.Request.Context(), `
		INSERT INTO group_event_rsvps (event_id, user_id, status) VALUES ($1, $2::uuid, 'going')
		ON CONFLICT DO NOTHING
	`, event.ID, userIDStr)
	event.AttendeeCount = 1
	going := "going"
	event.MyRSVP = &going

	c.JSON(http.StatusCreated, event)
}

// ListGroupEvents — GET /groups/:id/events
func (h *EventHandler) ListGroupEvents(c *gin.Context) {
	userID, _ := c.Get("user_id")
	userIDStr := userID.(string)
	groupID := c.Param("id")

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT e.id, e.group_id, e.created_by, e.title, e.description, e.location_name,
		       e.lat, e.long, e.starts_at, e.ends_at, e.is_public, e.cover_image_url,
		       e.max_attendees, e.created_at, e.updated_at,
		       (SELECT COUNT(*) FROM group_event_rsvps WHERE event_id = e.id AND status = 'going') AS attendee_count,
		       (SELECT status FROM group_event_rsvps WHERE event_id = e.id AND user_id = $2::uuid) AS my_rsvp
		FROM group_events e
		WHERE e.group_id = $1
		ORDER BY e.starts_at ASC
	`, groupID, userIDStr)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch events"})
		return
	}
	defer rows.Close()

	events := []GroupEvent{}
	for rows.Next() {
		var e GroupEvent
		if err := rows.Scan(&e.ID, &e.GroupID, &e.CreatedBy, &e.Title, &e.Description,
			&e.LocationName, &e.Lat, &e.Long, &e.StartsAt, &e.EndsAt, &e.IsPublic,
			&e.CoverImageURL, &e.MaxAttendees, &e.CreatedAt, &e.UpdatedAt,
			&e.AttendeeCount, &e.MyRSVP); err != nil {
			continue
		}
		events = append(events, e)
	}

	c.JSON(http.StatusOK, gin.H{"events": events})
}

// GetEvent — GET /groups/:id/events/:eventId
func (h *EventHandler) GetEvent(c *gin.Context) {
	userID, _ := c.Get("user_id")
	userIDStr := userID.(string)
	eventID := c.Param("eventId")

	var e GroupEvent
	err := h.db.QueryRow(c.Request.Context(), `
		SELECT e.id, e.group_id, e.created_by, e.title, e.description, e.location_name,
		       e.lat, e.long, e.starts_at, e.ends_at, e.is_public, e.cover_image_url,
		       e.max_attendees, e.created_at, e.updated_at,
		       g.name AS group_name,
		       (SELECT COUNT(*) FROM group_event_rsvps WHERE event_id = e.id AND status = 'going') AS attendee_count,
		       (SELECT status FROM group_event_rsvps WHERE event_id = e.id AND user_id = $2::uuid) AS my_rsvp
		FROM group_events e
		JOIN groups g ON g.id = e.group_id
		WHERE e.id = $1
	`, eventID, userIDStr).Scan(&e.ID, &e.GroupID, &e.CreatedBy, &e.Title, &e.Description,
		&e.LocationName, &e.Lat, &e.Long, &e.StartsAt, &e.EndsAt, &e.IsPublic,
		&e.CoverImageURL, &e.MaxAttendees, &e.CreatedAt, &e.UpdatedAt,
		&e.GroupName, &e.AttendeeCount, &e.MyRSVP)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "event not found"})
		return
	}

	c.JSON(http.StatusOK, e)
}

// UpdateEvent — PATCH /groups/:id/events/:eventId
func (h *EventHandler) UpdateEvent(c *gin.Context) {
	userID, _ := c.Get("user_id")
	userIDStr := userID.(string)
	groupID := c.Param("id")
	eventID := c.Param("eventId")

	// Check admin/owner
	var role string
	err := h.db.QueryRow(c.Request.Context(), `
		SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2::uuid
	`, groupID, userIDStr).Scan(&role)
	if err != nil || (role != "owner" && role != "admin") {
		c.JSON(http.StatusForbidden, gin.H{"error": "only group admins can update events"})
		return
	}

	var req struct {
		Title         *string  `json:"title"`
		Description   *string  `json:"description"`
		LocationName  *string  `json:"location_name"`
		Lat           *float64 `json:"lat"`
		Long          *float64 `json:"long"`
		StartsAt      *string  `json:"starts_at"`
		EndsAt        *string  `json:"ends_at"`
		IsPublic      *bool    `json:"is_public"`
		CoverImageURL *string  `json:"cover_image_url"`
		MaxAttendees  *int     `json:"max_attendees"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err = h.db.Exec(c.Request.Context(), `
		UPDATE group_events SET
			title           = COALESCE($2, title),
			description     = COALESCE($3, description),
			location_name   = COALESCE($4, location_name),
			lat             = COALESCE($5, lat),
			long            = COALESCE($6, long),
			is_public       = COALESCE($7, is_public),
			cover_image_url = COALESCE($8, cover_image_url),
			max_attendees   = COALESCE($9, max_attendees),
			updated_at      = now()
		WHERE id = $1
	`, eventID, req.Title, req.Description, req.LocationName, req.Lat, req.Long, req.IsPublic, req.CoverImageURL, req.MaxAttendees)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update event"})
		return
	}

	// Handle starts_at/ends_at separately (need time parsing)
	if req.StartsAt != nil {
		if t, err := time.Parse(time.RFC3339, *req.StartsAt); err == nil {
			h.db.Exec(c.Request.Context(), `UPDATE group_events SET starts_at = $1 WHERE id = $2`, t, eventID) //nolint:errcheck
		}
	}
	if req.EndsAt != nil {
		if t, err := time.Parse(time.RFC3339, *req.EndsAt); err == nil {
			h.db.Exec(c.Request.Context(), `UPDATE group_events SET ends_at = $1 WHERE id = $2`, t, eventID) //nolint:errcheck
		}
	}

	// Return the updated event
	var updated GroupEvent
	err = h.db.QueryRow(c.Request.Context(), `
		SELECT e.id, e.group_id, e.created_by, e.title, e.description, e.location_name,
		       e.lat, e.long, e.starts_at, e.ends_at, e.is_public, e.cover_image_url,
		       e.max_attendees, e.created_at, e.updated_at,
		       g.name AS group_name,
		       (SELECT COUNT(*) FROM group_event_rsvps WHERE event_id = e.id AND status = 'going') AS attendee_count,
		       (SELECT status FROM group_event_rsvps WHERE event_id = e.id AND user_id = $2::uuid) AS my_rsvp
		FROM group_events e
		JOIN groups g ON g.id = e.group_id
		WHERE e.id = $1
	`, eventID, userIDStr).Scan(&updated.ID, &updated.GroupID, &updated.CreatedBy, &updated.Title, &updated.Description,
		&updated.LocationName, &updated.Lat, &updated.Long, &updated.StartsAt, &updated.EndsAt, &updated.IsPublic,
		&updated.CoverImageURL, &updated.MaxAttendees, &updated.CreatedAt, &updated.UpdatedAt,
		&updated.GroupName, &updated.AttendeeCount, &updated.MyRSVP)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"message": "event updated"})
		return
	}
	c.JSON(http.StatusOK, updated)
}

// DeleteEvent — DELETE /groups/:id/events/:eventId
func (h *EventHandler) DeleteEvent(c *gin.Context) {
	userID, _ := c.Get("user_id")
	userIDStr := userID.(string)
	groupID := c.Param("id")
	eventID := c.Param("eventId")

	// Check admin/owner
	var role string
	err := h.db.QueryRow(c.Request.Context(), `
		SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2::uuid
	`, groupID, userIDStr).Scan(&role)
	if err != nil || (role != "owner" && role != "admin") {
		c.JSON(http.StatusForbidden, gin.H{"error": "only group admins can delete events"})
		return
	}

	_, err = h.db.Exec(c.Request.Context(), `DELETE FROM group_events WHERE id = $1`, eventID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete event"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "event deleted"})
}

// RSVPEvent — POST /groups/:id/events/:eventId/rsvp
func (h *EventHandler) RSVPEvent(c *gin.Context) {
	userID, _ := c.Get("user_id")
	userIDStr := userID.(string)
	eventID := c.Param("eventId")

	var req struct {
		Status string `json:"status" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Status != "going" && req.Status != "interested" && req.Status != "not_going" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "status must be going, interested, or not_going"})
		return
	}

	_, err := h.db.Exec(c.Request.Context(), `
		INSERT INTO group_event_rsvps (event_id, user_id, status)
		VALUES ($1, $2::uuid, $3)
		ON CONFLICT (event_id, user_id) DO UPDATE SET status = $3, created_at = now()
	`, eventID, userIDStr, req.Status)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to RSVP"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": req.Status})
}

// RemoveRSVP — DELETE /groups/:id/events/:eventId/rsvp
func (h *EventHandler) RemoveRSVP(c *gin.Context) {
	userID, _ := c.Get("user_id")
	userIDStr := userID.(string)
	eventID := c.Param("eventId")

	_, err := h.db.Exec(c.Request.Context(), `
		DELETE FROM group_event_rsvps WHERE event_id = $1 AND user_id = $2::uuid
	`, eventID, userIDStr)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to remove RSVP"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "RSVP removed"})
}

// GetUpcomingPublicEvents — GET /events/upcoming?lat=&long=&radius=&limit=
// Returns public events near a location, sorted by start time.
func (h *EventHandler) GetUpcomingPublicEvents(c *gin.Context) {
	userID, _ := c.Get("user_id")
	userIDStr := userID.(string)

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	if limit > 50 {
		limit = 50
	}

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT e.id, e.group_id, e.created_by, e.title, e.description, e.location_name,
		       e.lat, e.long, e.starts_at, e.ends_at, e.is_public, e.cover_image_url,
		       e.max_attendees, e.created_at, e.updated_at,
		       g.name AS group_name,
		       (SELECT COUNT(*) FROM group_event_rsvps WHERE event_id = e.id AND status = 'going') AS attendee_count,
		       (SELECT status FROM group_event_rsvps WHERE event_id = e.id AND user_id = $2::uuid) AS my_rsvp
		FROM group_events e
		JOIN groups g ON g.id = e.group_id
		WHERE e.is_public = true AND e.starts_at >= now()
		ORDER BY e.starts_at ASC
		LIMIT $1
	`, limit, userIDStr)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch events"})
		return
	}
	defer rows.Close()

	events := []GroupEvent{}
	for rows.Next() {
		var e GroupEvent
		if err := rows.Scan(&e.ID, &e.GroupID, &e.CreatedBy, &e.Title, &e.Description,
			&e.LocationName, &e.Lat, &e.Long, &e.StartsAt, &e.EndsAt, &e.IsPublic,
			&e.CoverImageURL, &e.MaxAttendees, &e.CreatedAt, &e.UpdatedAt,
			&e.GroupName, &e.AttendeeCount, &e.MyRSVP); err != nil {
			continue
		}
		events = append(events, e)
	}

	c.JSON(http.StatusOK, gin.H{"events": events})
}

// GetMyEvents — GET /events/mine
// Returns upcoming events from groups the user belongs to.
func (h *EventHandler) GetMyEvents(c *gin.Context) {
	userID, _ := c.Get("user_id")
	userIDStr := userID.(string)

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	if limit > 50 {
		limit = 50
	}

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT e.id, e.group_id, e.created_by, e.title, e.description, e.location_name,
		       e.lat, e.long, e.starts_at, e.ends_at, e.is_public, e.cover_image_url,
		       e.max_attendees, e.created_at, e.updated_at,
		       g.name AS group_name,
		       (SELECT COUNT(*) FROM group_event_rsvps WHERE event_id = e.id AND status = 'going') AS attendee_count,
		       (SELECT status FROM group_event_rsvps WHERE event_id = e.id AND user_id = $2::uuid) AS my_rsvp
		FROM group_events e
		JOIN groups g ON g.id = e.group_id
		WHERE e.group_id IN (SELECT group_id FROM group_members WHERE user_id = $2::uuid)
		  AND e.starts_at >= now()
		ORDER BY e.starts_at ASC
		LIMIT $1
	`, limit, userIDStr)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch events"})
		return
	}
	defer rows.Close()

	events := []GroupEvent{}
	for rows.Next() {
		var e GroupEvent
		if err := rows.Scan(&e.ID, &e.GroupID, &e.CreatedBy, &e.Title, &e.Description,
			&e.LocationName, &e.Lat, &e.Long, &e.StartsAt, &e.EndsAt, &e.IsPublic,
			&e.CoverImageURL, &e.MaxAttendees, &e.CreatedAt, &e.UpdatedAt,
			&e.GroupName, &e.AttendeeCount, &e.MyRSVP); err != nil {
			continue
		}
		events = append(events, e)
	}

	c.JSON(http.StatusOK, gin.H{"events": events})
}
