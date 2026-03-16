# Contributing to Sojorn

Thank you for your interest in contributing to Sojorn. This guide covers everything you need to get started.

## Prerequisites

- **Go 1.24+** (backend API)
- **Node.js 20+** (admin panel)
- **PostgreSQL 16+**
- (Optional) Ollama for AI moderation features
- (Optional) Cloudflare R2 or any S3-compatible storage for media uploads

## Getting Started

```bash
# 1. Clone the repository
git clone https://gitlab.com/patrickbritton3/sojorn.git
cd sojorn

# 2. Copy the environment template
cp go-backend/.env.example go-backend/.env

# 3. Set the two required variables in go-backend/.env:
#    DATABASE_URL=postgres://user:pass@localhost:5432/sojorn?sslmode=disable
#    JWT_SECRET=$(openssl rand -hex 32)

# 4. Create the database and run migrations
createdb sojorn
cd go-backend
export DATABASE_URL="postgres://user:pass@localhost:5432/sojorn?sslmode=disable"
go run cmd/migrate/main.go

# 5. Start the API server
go run cmd/api/main.go
```

The API listens on `http://localhost:8080` by default.

## Running Locally

### API Backend

```bash
cd go-backend && go run cmd/api/main.go
```

The server reads configuration from environment variables or a `.env` file in the `go-backend/` directory. See `DEPLOYMENT.md` for the full variable reference.

### Running Tests

```bash
cd go-backend && go test ./...
```

### Admin Panel Development

```bash
cd admin
npm ci
npm run dev
```

The admin panel runs on `http://localhost:3002` and expects the API at `http://localhost:8080`.

## Code Style

### Go

All Go code must be formatted with `gofmt`. Run it before committing:

```bash
gofmt -w .
```

There are no additional Go linters configured at this time. Keep code idiomatic: short variable names in tight scopes, descriptive names for exported symbols, and table-driven tests where appropriate.

### TypeScript (Admin Panel)

If Prettier is configured in the `admin/` directory, run it before committing frontend changes:

```bash
npx prettier --write .
```

No additional linters are enforced for the admin panel.

## Creating a New Extension

Sojorn's feature set is modular. If your contribution adds a new toggleable feature, implement it as an extension rather than adding routes to `main.go` directly.

See [go-backend/docs/extensions.md](go-backend/docs/extensions.md) for the full extension development guide, including the interface contract, a step-by-step walkthrough, and a complete code template.

## Pull Request Process

1. **Branch from `goSojorn`** — create a feature or fix branch off of `goSojorn` (e.g., `feat/polls`, `fix/feed-pagination`).
2. **Describe your changes** — the PR description should explain what changed and why. Link related issues if applicable.
3. **Ensure CI passes** — all tests must pass and `gofmt` must report no changes.
4. **Keep PRs focused** — one logical change per PR. If a refactor is needed to support your feature, submit the refactor as a separate PR first.
5. **Respond to review feedback** — maintainers may request changes. Push follow-up commits rather than force-pushing so the review history is preserved.

## Bug Reports

When filing a bug report, include:

- **Instance version** — call `GET /api/v1/version` on your instance and paste the JSON response (`version`, `commit`, `built_at`).
- **Extension state** — list which extensions are enabled/disabled (visible in the admin panel under Extensions, or via `GET /api/v1/instance`).
- **Steps to reproduce** — numbered steps that reliably trigger the issue.
- **Expected vs. actual behavior** — describe what should happen and what happens instead.
- **Logs** — relevant server log output (set `LOG_LEVEL=debug` for maximum detail).
- **Environment** — OS, Go version, PostgreSQL version, browser (for admin panel issues), or Flutter/device info (for app issues).

## Accessibility

Frontend contributions (admin panel and any web-facing UI) must meet the following standards:

- **Keyboard navigation** — all interactive elements must be reachable and operable via keyboard alone. Use semantic HTML elements (`<button>`, `<a>`, `<input>`) rather than `<div>` with click handlers.
- **ARIA labels** — provide `aria-label` or `aria-labelledby` attributes for elements that lack visible text labels (icon buttons, status indicators, media controls).
- **Contrast ratios** — text must meet WCAG 2.1 AA contrast ratios: at least 4.5:1 for normal text and 3:1 for large text. Use a contrast checker before submitting color changes.
- **Focus indicators** — never remove default focus outlines without providing an equally visible alternative.
- **Screen reader support** — dynamic content updates should use `aria-live` regions. Form validation errors should be associated with their fields via `aria-describedby`.

## License

Sojorn is licensed under the [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0). By submitting a pull request, you agree that your contributions will be licensed under the same terms.

If you are contributing on behalf of your employer, ensure you have permission to contribute under AGPL-3.0 before submitting.
