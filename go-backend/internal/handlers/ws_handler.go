package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/middleware"
	"gitlab.com/patrickbritton3/sojorn/go-backend/internal/realtime"
	"github.com/rs/zerolog/log"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = (pongWait * 9) / 10
	maxMessageSize = 512 * 1024 // 512KB
)

type WSHandler struct {
	hub       *realtime.Hub
	jwtSecret string
}

func NewWSHandler(hub *realtime.Hub, jwtSecret string) *WSHandler {
	return &WSHandler{hub: hub, jwtSecret: jwtSecret}
}

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // Production should be stricter
	},
}

func (h *WSHandler) ServeWS(c *gin.Context) {
	token := c.Query("token")
	if token == "" {
		c.AbortWithStatus(http.StatusUnauthorized)
		return
	}

	userID, _, err := middleware.ParseToken(token, h.jwtSecret)
	if err != nil {
		log.Warn().Err(err).Msg("WebSocket auth failed")
		c.AbortWithStatus(http.StatusUnauthorized)
		return
	}

	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Error().Err(err).Msg("Failed to upgrade to WebSocket")
		return
	}

	client := &realtime.Client{
		UserID: userID,
		Conn:   conn,
		Send:   make(chan interface{}, 256),
	}

	h.hub.Register(client)

	// readPump
	go func() {
		defer func() {
			h.hub.Unregister(client)
		}()

		conn.SetReadLimit(maxMessageSize)
		conn.SetReadDeadline(time.Now().Add(pongWait))
		conn.SetPongHandler(func(string) error {
			conn.SetReadDeadline(time.Now().Add(pongWait))
			return nil
		})

		for {
			var msg map[string]interface{}
			err := conn.ReadJSON(&msg)
			if err != nil {
				if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
					log.Warn().Err(err).Msg("WebSocket read error")
				}
				break
			}

			// Handle client ping messages
			if msgType, ok := msg["type"].(string); ok && msgType == "ping" {
				// Respond with pong immediately
				select {
				case client.Send <- map[string]interface{}{"type": "pong"}:
				default:
					log.Warn().Str("user_id", userID).Msg("Failed to send pong - channel full")
				}
			}
		}
	}()

	// writePump (Single Writer)
	go func() {
		ticker := time.NewTicker(pingPeriod)
		defer func() {
			ticker.Stop()
			h.hub.Unregister(client)
		}()

		for {
			select {
			case message, ok := <-client.Send:
				conn.SetWriteDeadline(time.Now().Add(writeWait))
				if !ok {
					// The hub closed the channel.
					conn.WriteMessage(websocket.CloseMessage, []byte{})
					return
				}

				if err := conn.WriteJSON(message); err != nil {
					log.Warn().Err(err).Str("user_id", userID).Msg("Failed to write JSON to WebSocket")
					return
				}

			case <-ticker.C:
				conn.SetWriteDeadline(time.Now().Add(writeWait))
				if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
					log.Warn().Err(err).Str("user_id", userID).Msg("Failed to send PING")
					return
				}
			}
		}
	}()
}
