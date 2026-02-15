package models

import (
	"time"

	"github.com/google/uuid"
)

// NeighborhoodSeed is a cached neighborhood definition, populated on-demand
// via the Overpass (OSM) API when users visit new areas.
type NeighborhoodSeed struct {
	ID           uuid.UUID  `json:"id" db:"id"`
	Name         string     `json:"name" db:"name"`
	City         string     `json:"city" db:"city"`
	State        string     `json:"state" db:"state"`
	ZipCode      string     `json:"zip_code" db:"zip_code"`
	Country      string     `json:"country" db:"country"`
	Lat          float64    `json:"lat" db:"lat"`
	Lng          float64    `json:"lng" db:"lng"`
	RadiusMeters int        `json:"radius_meters" db:"radius_meters"`
	GroupID      *uuid.UUID `json:"group_id,omitempty" db:"group_id"`
	CreatedAt    time.Time  `json:"created_at" db:"created_at"`
}

// NeighborhoodDetectResult is the response from the detect endpoint.
type NeighborhoodDetectResult struct {
	Neighborhood NeighborhoodSeed `json:"neighborhood"`
	GroupID      uuid.UUID        `json:"group_id"`
	GroupName    string           `json:"group_name"`
	MemberCount  int              `json:"member_count"`
	IsNew        bool             `json:"is_new"`
	JustJoined   bool             `json:"just_joined"`
}
