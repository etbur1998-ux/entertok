# EnterTok Admin Panel

A full-featured React admin dashboard for the EnterTok platform.

## Stack
- **React 18** + **React Router 6**
- **Vite 5** (dev server on port 3001)
- **Recharts** — dashboard charts
- **Lucide React** — icons
- **Axios** — API calls (proxied to Go backend)
- **React Hot Toast** — notifications

## Setup & Run

```bash
# Install dependencies
npm install

# Start dev server (connects to Go backend on :8080)
npm run dev

# Build for production
npm run build
```

The dev server starts on **http://localhost:3001**

Make sure the Go backend is running first:
```bash
cd ../   # backend root
go run .
```

## Login
Use any existing user account. For admin features, the user needs `role = "admin"` in the database.

## Pages
| Route | Description |
|-------|-------------|
| `/` | Dashboard — stats, charts, live streams, trending |
| `/users` | User management — search, view profiles, posts, followers |
| `/posts` | Post moderation — view, filter by type, delete |
| `/products` | Marketplace — product grid, delete |
| `/live` | Live streams — monitor active streams, force end |
| `/ads` | Ad management — impressions, CTR, budget tracking |
| `/messages` | Conversation browser — read all messages |
| `/reports` | Report queue — resolve/reject reports |
| `/settings` | Platform config, server health, admin account |
