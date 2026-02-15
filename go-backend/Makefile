.PHONY: build run test migrate-up migrate-down

build:
	go build -o bin/api ./cmd/api/main.go

run:
	go run ./cmd/api/main.go

test:
	go test ./...

migrate-up:
	migrate -path internal/database/migrations -database "$(DATABASE_URL)" up

migrate-down:
	migrate -path internal/database/migrations -database "$(DATABASE_URL)" down

tidy:
	go mod tidy
