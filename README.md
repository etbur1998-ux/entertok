# EnterTok

A full-stack social media platform built with **Flutter** (Windows/Web/Mobile) and **Go** backend.

## Features

- 🎥 TikTok-style video feed with infinite scroll
- 💬 Real-time chat (WebSocket)
- 📞 1-to-1 video & audio calls (WebRTC)
- 👥 Group video & audio calls
- 🎲 Random video chat (Omegle-style)
- 📺 Live streaming
- 🛒 Marketplace
- ❤️ Dating page
- 💰 Wallet & Boost system
- 📢 Marketing & Ads
- 🔔 Real-time notifications
- 👤 User profiles & discovery
- 🛡️ Admin panel (React)

## Stack

- **Frontend:** Flutter (Dart) — Windows, Web, Android, iOS
- **Backend:** Go (Gin, GORM, SQLite, WebSocket)
- **Admin:** React + Vite
- **Real-time:** WebSocket hub + WebRTC

## Quick Start

### Backend
```bash
cd backend
cp .env.example .env
go run .
```

### Flutter
```bash
flutter pub get
flutter run -d windows
```

### Admin Panel
```bash
cd backend/admin
npm install
npm run dev
```

## API
Base URL: `http://localhost:8082/api/v1`
WebSocket: `ws://localhost:8082/ws?token=<jwt>`
