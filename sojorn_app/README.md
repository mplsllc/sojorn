# Sojorn Flutter App

Cross-platform mobile and web client for the Sojorn social network.

## Tech Stack

- **Framework**: Flutter 3.x
- **State Management**: Riverpod
- **Video Processing**: ffmpeg_kit_flutter_new (mobile only, stub for web)
- **Platforms**: Android, iOS, Web

## Features

### Content
- Posts with rich text, images, video, link previews, audio overlays
- Quips (short-form video) with threaded comment chains
- Reposts/boosts with 4 repost types
- Categories and hashtags

### Community Safety
- Beacons: real-time safety alerts with approximate location
- Neighborhood boards with topic-based entries (community, question, event, lost pet, resource, recommendation, warning)
- Board voting and reply threads

### Social
- Follow/unfollow with pending requests for private profiles
- Profile widgets with customizable layout
- Blocking (single, by handle, bulk import)
- Circle-based visibility controls

### Messaging
- E2EE direct messages (Signal protocol / X3DH)
- Groups with chat, forums, and posts
- Encrypted Capsules (E2EE group messaging)
- Push notifications via FCM

### Media
- Image upload and editing with crop/filters
- Video recording and playback
- Audio overlay system: device audio + Funkwhale library
- Signed media URLs via Go backend
- NSFW blur with user toggle

## Design System

- **Fonts**: Literata (content/body), Inter (labels/UI)
- **Corner radii**: `SojornRadii` in `tokens.dart` — xs=2, sm=4, md=8, lg=12, card=16, xl=20, modal=24, full=36
- **Bottom sheets**: `SojornSheet.show(context, child:, title:)`
- **Snackbars**: `context.showError/showSuccess/showInfo/showWarning()`
- **Avatars**: `SojornAvatar(displayName:, avatarUrl:, size:)` — rounded squares, never CircleAvatar
- **Skeleton loaders**: `SkeletonFeedList`, `SkeletonGroupList`

## Setup

```bash
flutter pub get
flutter run
```

For web:
```bash
flutter run -d chrome
```

## Project Structure

```
lib/
├── screens/          # All screens organized by feature
│   ├── auth/         # Sign in, sign up
│   ├── home/         # Home shell, feed
│   ├── beacon/       # Safety beacons
│   ├── compose/      # Post creation, image editor
│   ├── quips/        # Short-form video
│   ├── profile/      # Profile, settings
│   ├── chat/         # E2EE messaging
│   ├── groups/       # Groups and capsules
│   └── audio/        # Audio library
├── services/         # API, auth, E2EE, image upload, etc.
├── widgets/          # Shared components
├── providers/        # Riverpod providers
├── models/           # Data models
├── theme/            # Design tokens, colors, typography
└── utils/            # Extensions and helpers
```

## Backend Connection

The app connects to the Go backend at `api.sojorn.net`. The API base URL is configured in the API service. All authenticated requests use JWT Bearer tokens with proactive refresh (2 minutes before expiry).
