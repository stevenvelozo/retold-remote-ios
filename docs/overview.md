# Overview

`retold-remote-ios` is the native iOS companion to the `retold-remote` server. It brings the Retold ecosystem -- dashboards, data records, file transfers, and realtime events -- into a first-class SwiftUI experience on iPhone, iPad, and Apple Silicon Macs (via Mac Catalyst).

## What It Is

A thin, purposeful client. The heavy lifting -- authentication, authorization, data access, file storage -- stays on the `retold-remote` server built on Fable/Meadow/Orator. The iOS app is responsible for:

- Presenting a native, fluent UI for the services exposed by `retold-remote`
- Caching recent data for offline browsing
- Handling push notifications and realtime updates via Tidings
- Safely storing credentials and session tokens in the iOS Keychain
- Uploading media captured on-device (camera, files, documents)

## What It Is Not

- **Not a server.** It never exposes endpoints; it consumes them.
- **Not a port of Pict.** Pict is a JS MVC framework; this app is pure Swift/SwiftUI. It speaks the same *wire protocol* as Pict clients, not the same runtime.
- **Not a standalone data store.** The local SQLite cache is strictly an offline mirror and is invalidated aggressively.

## Core Capabilities

| Capability | Backed By |
|---|---|
| Authentication (session/token) | `orator-authentication` on the server |
| Data record read/write | `meadow-endpoints` REST API |
| Realtime events | `tidings` WebSocket channel |
| File upload/download | `orator-static-server` + signed URLs |
| Structured forms | JSON form schema served by `retold-remote` |
| Push notifications | APNs -> server -> Tidings fan-out |

## Platform Support

- **iOS 16.0+** (primary)
- **iPadOS 16.0+** (universal)
- **Mac Catalyst 16.0+** (optional target)
- Xcode 15+, Swift 5.9+

## Relationship to the Rest of the Ecosystem

The iOS app is the outermost edge of a Retold deployment. It only talks to one thing -- a `retold-remote` server -- which brokers everything else.

```
iPhone / iPad  ──HTTPS/WSS──>  retold-remote (Orator)
                                   │
                                   ├── Fable (config, logging, DI)
                                   ├── Meadow (data access)
                                   ├── Tidings (realtime)
                                   └── Ultravisor beacons (optional)
```

See the [Architecture](#/page/architecture.md) page for a full diagram.
