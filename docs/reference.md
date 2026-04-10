# Implementation Reference

This page is a module-by-module tour of the source tree. Everything lives under `RetoldRemote/`.

## Project Layout

```
RetoldRemote/
├── App/
│   ├── RetoldRemoteApp.swift        // @main entry point
│   ├── AppContainer.swift           // Service locator
│   └── AppCoordinator.swift         // Navigation + session lifecycle
├── Configuration/
│   ├── Config.swift                 // Reads xcconfig values
│   ├── Local.xcconfig.sample
│   └── Release.xcconfig
├── Services/
│   ├── RemoteClient.swift           // REST transport
│   ├── TidingsClient.swift          // WebSocket transport
│   ├── AuthService.swift            // Keychain + biometrics
│   ├── PushService.swift            // APNs registration
│   └── FileService.swift            // Upload / download
├── Persistence/
│   ├── CacheStore.swift             // SQLite wrapper
│   ├── Outbox.swift                 // Offline write queue
│   └── Migrations/
├── Models/
│   ├── Record.swift
│   ├── Entity.swift
│   └── TidingsEnvelope.swift
├── Features/
│   ├── Login/
│   ├── Home/
│   ├── Records/
│   ├── Files/
│   └── Settings/
└── Resources/
    ├── Assets.xcassets
    ├── Info.plist
    └── Localizable.strings
```

## App

### `RetoldRemoteApp`

`@main` struct conforming to `SwiftUI.App`. Builds the root `AppContainer`, installs it as an `@Environment` value, and hands control to `AppCoordinator`.

### `AppContainer`

A protocol-oriented service locator. Exposes every service as a `lazy var` behind its protocol. Construction order matters: `AuthService` must be ready before `RemoteClient`.

```swift
final class AppContainer {
    lazy var config: Config = Config.load()
    lazy var auth: AuthServiceProtocol = AuthService(config: config)
    lazy var remote: RemoteClientProtocol = RemoteClient(config: config, auth: auth)
    lazy var tidings: TidingsClientProtocol = TidingsClient(config: config, auth: auth)
    lazy var files: FileServiceProtocol = FileService(remote: remote)
    lazy var push: PushServiceProtocol = PushService(remote: remote)
    lazy var cache: CacheStore = try! CacheStore.open()
}
```

### `AppCoordinator`

Owns the root navigation state (`@Published var route: Route`). Observes `AuthService.sessionState` and flips between the login flow and the main tab view.

## Services

### `RemoteClient`

Thin wrapper over `URLSession`. Responsibilities:

- Base URL and header injection
- JSON encode/decode with `ISO8601DateFormatter`
- Automatic `401` -> refresh -> retry
- Typed `async throws` methods for each endpoint family (`list`, `read`, `create`, `update`, `delete`)
- Request signing via `AuthService.currentToken()`

All methods are `async throws`. Errors are surfaced as a `RemoteError` enum (`.network`, `.decoding`, `.http(Int)`, `.unauthorized`).

### `TidingsClient`

Single-connection WebSocket client. Maintains a `@Published` `connectionState` (`.connecting`, `.open`, `.closed`). Exposes a `publisher(for channel: String) -> AnyPublisher<TidingsEnvelope, Never>` method that view models use to subscribe to live updates.

Reconnect policy: exponential backoff with a 30-second cap. On reconnect, the client sends a `resume` frame with the last seen sequence number.

### `AuthService`

Stores credentials in the Keychain. Exposes:

- `signIn(username:password:) async throws`
- `signOut() async`
- `currentToken() -> String?`
- `sessionState: AnyPublisher<SessionState, Never>`
- `requireBiometricUnlock() async throws`

Uses `LocalAuthentication` for Face ID / Touch ID gating.

### `PushService`

Registers for remote notifications, uploads the APNs device token to `retold-remote`, and routes incoming notifications through the `AppCoordinator` for deep linking. The mapping from `userInfo` payloads to in-app routes lives in `PushRouteResolver`.

### `FileService`

Handles both uploads (multipart to `orator-static-server`) and downloads (resumable via `URLSessionDownloadTask`). Uploads that exceed 10 MB use a background `URLSession` so they survive app suspension.

## Persistence

### `CacheStore`

A thin wrapper around `SQLite.swift`. One table per entity, plus a `sync_meta` table tracking the last-seen server version per channel. Exposes `async` methods that mirror `RemoteClient`'s shape so view models can swap transparently between cache and network reads.

### `Outbox`

Single-table queue of pending writes. Each row has a `payload` blob, a `kind`, a `createdAt`, and a `retryCount`. On connectivity change, `OutboxFlusher` drains the queue using `RemoteClient`.

## Models

All wire models are `Codable`. Two-way `Equatable` and `Hashable` conformance is synthesized. Server-side timestamps are decoded as `Date` via a custom `JSONDecoder.DateDecodingStrategy`.

## Features

Each feature folder is self-contained: `View`, `ViewModel`, optional local `Models`, and a `Route` case. View models are `@MainActor` classes that expose `@Published` state and `async` actions. No feature imports another feature -- cross-feature navigation goes through `AppCoordinator`.

### `Login`

Username/password form -> `AuthService.signIn`. On success, hands off to `AppCoordinator` which transitions to the `.main` route.

### `Home`

Dashboard pulling a small set of "pinned" entities. Subscribes to the `home.feed` Tidings channel for live updates.

### `Records`

Generic record browser. Drives off the entity schema served by `retold-remote` under `/schema/:entity`. Supports list, filter, detail, and edit.

### `Files`

Browse and preview files from `orator-static-server`. Supports capture from the camera and import from Files.app.

### `Settings`

Server URL, biometric toggle, cache management, sign-out.

## Testing

- **Unit tests** -- `RetoldRemoteTests/` -- one file per service, using protocol fakes injected via `AppContainer`.
- **Snapshot tests** -- `RetoldRemoteSnapshotTests/` -- uses `swift-snapshot-testing` for key screens.
- **UI tests** -- `RetoldRemoteUITests/` -- covers the login flow and one end-to-end record edit against a mock server.

Run all tests with **⌘U** in Xcode or `xcodebuild test -scheme RetoldRemote -destination 'platform=iOS Simulator,name=iPhone 15'` from the command line.
