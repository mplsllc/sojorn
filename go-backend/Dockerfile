# Build stage
FROM golang:1.25-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w -X main.gitCommit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown) -X main.buildDate=$(date -u +%Y-%m-%dT%H:%M:%SZ)" -o /api ./cmd/api/main.go
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /migrate ./cmd/migrate/main.go
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /admin ./cmd/admin/main.go

# Run stage
FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

COPY --from=builder /api ./api
COPY --from=builder /migrate ./migrate
COPY --from=builder /admin ./admin
COPY migrations ./migrations

EXPOSE 8080

CMD ["./api"]
