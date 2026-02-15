# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Copy dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -o /api ./cmd/api/main.go

# Run stage
FROM alpine:latest

WORKDIR /app

# Copy the binary from the builder stage
COPY --from=builder /api ./api
COPY .env.example ./.env

# Create migrations directory
COPY internal/database/migrations ./migrations

EXPOSE 8080

CMD ["./api"]
