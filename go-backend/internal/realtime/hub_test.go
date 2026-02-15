package realtime

import (
	"testing"
	"time"
)

func TestHubSendToUserMultiDevice(t *testing.T) {
	hub := NewHub()

	clientA := &Client{UserID: "user-1", Send: make(chan interface{}, 1)}
	clientB := &Client{UserID: "user-1", Send: make(chan interface{}, 1)}

	hub.Register(clientA)
	hub.Register(clientB)

	payload := map[string]string{"type": "ping"}
	if err := hub.SendToUser("user-1", payload); err != nil {
		t.Fatalf("SendToUser error: %v", err)
	}

	select {
	case msg := <-clientA.Send:
		if msg == nil {
			t.Fatalf("clientA received nil message")
		}
	case <-time.After(500 * time.Millisecond):
		t.Fatalf("clientA did not receive message")
	}

	select {
	case msg := <-clientB.Send:
		if msg == nil {
			t.Fatalf("clientB received nil message")
		}
	case <-time.After(500 * time.Millisecond):
		t.Fatalf("clientB did not receive message")
	}
}
