# Quickstart

Get the app running against a local `retold-remote` server in under ten minutes.

## Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 15 or later with the iOS 17 SDK
- A running `retold-remote` server -- see the [retold-remote docs](/apps/retold-remote/)
- Node.js 20+ (only needed for the companion server)

## 1. Clone the Repository

```bash
git clone https://github.com/stevenvelozo/retold-remote-ios.git
cd retold-remote-ios
```

## 2. Open the Xcode Project

```bash
open RetoldRemote.xcodeproj
```

Xcode will resolve Swift Package Manager dependencies on first launch. The project ships with all dependencies pinned in `Package.resolved`.

## 3. Configure a Server Endpoint

Edit `RetoldRemote/Configuration/Local.xcconfig` (copy from `Local.xcconfig.sample` if it does not exist):

```
RETOLD_REMOTE_BASE_URL = https://localhost:8080
RETOLD_REMOTE_TIDINGS_URL = wss://localhost:8080/tidings
RETOLD_REMOTE_ALLOW_INSECURE = YES
```

> `ALLOW_INSECURE = YES` enables `NSAllowsArbitraryLoads` so the simulator can talk to a self-signed local server. **Never ship with this flag enabled.**

## 4. Start the Companion Server

In a separate terminal:

```bash
cd path/to/retold/modules/apps/retold-remote
npm install
npm start
```

The server listens on `http://localhost:8080` by default.

## 5. Run in the Simulator

1. Select the **RetoldRemote** scheme.
2. Choose an iPhone 15 simulator.
3. Press **⌘R**.

The app will build, launch, and show the login screen. Sign in with the credentials configured on your `retold-remote` server.

## 6. Verify Realtime

Once signed in, the home screen shows a **Live** indicator. A green dot means the Tidings WebSocket is connected. Trigger an event on the server (e.g. write a record via the REST API) -- the home feed should update within a second.

## Next Steps

- Read the [Architecture](#/page/architecture.md) page to understand how the layers fit together.
- Read the [Reference](#/page/reference.md) for module-by-module details.
- When you are ready to ship, jump to [iOS Build & Package](#/page/ios-build-and-package.md).
