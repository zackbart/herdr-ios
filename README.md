# Herdr iOS

A native iOS (SwiftUI) client for [Herdr](https://herdr.dev), the terminal-native
**agent multiplexer**. Browse your workspaces, watch live agent status, and read
or drive any pane from your phone.

> **Status:** the full app runs today on an in-memory **Mock** transport with
> realistic data and live status updates. The SSH transport is scaffolded; the
> socket bridge is a tracked follow-up (see [SSH transport](#ssh-transport)).

## Why SSH?

Herdr has **no network API and no official mobile app** by design. Its socket API
is **newline-delimited JSON-RPC over a local Unix domain socket**
(`~/.config/herdr/herdr.sock`; named sessions under
`~/.config/herdr/sessions/<n>/herdr.sock`). Remote use is officially "SSH into
the box and run herdr." So this client reaches the socket the same way: over SSH,
by bridging an exec channel to the Unix socket and speaking JSON-RPC directly —
which keeps live event subscriptions working.

## Architecture

Two cleanly separated layers, so the entire UI runs on a Mock and the real SSH
transport is a drop-in swap.

### `HerdrKit` — platform-independent core (`Sources/HerdrKit`)

No SwiftUI, no third-party deps, Foundation + Swift Concurrency only → builds and
unit-tests with `swift test` on macOS or Linux.

| Area | Files |
| --- | --- |
| Models | `Models/{IDs,AgentStatus,Pane,Workspace}.swift` — ids are non-durable strings; status is `idle/working/blocked/done/unknown` |
| Protocol | `Protocol/{JSONValue,RPC,NDJSON,Method}.swift` — NDJSON JSON-RPC codec; every wire `method` string lives in `Method.swift` |
| Transport | `Transport/HerdrTransport.swift` — dumb in/out channel protocol |
| Client | `Client/{HerdrClient,HerdrEvent}.swift` — actor that correlates replies and demuxes events into one `eventStream` |
| Mock | `Mock/{MockTransport,MockData}.swift` — answers requests and emits live status/output events |

### `Herdr` — SwiftUI app (`App/Herdr`)

State via `@Observable`. A single `SessionModel` is the source of truth, injected
through the environment.

- **Connection** — `Host`, `ConnectionStore` (UserDefaults), `KeychainStore`
  (key/password in the Keychain), `SSHTransport` (stub), `ConnectView`.
- **Screen 1 — Workspaces** — `Features/Workspaces/WorkspaceListView.swift`:
  live aggregate status, per-status counts, pull-to-refresh.
- **Screen 2 — Panes/agents** — `Features/Panes/WorkspaceDetailView.swift`:
  tabs and their panes with per-agent status.
- **Screen 3 — Pane** — `Features/Pane/PaneView.swift`: monospaced scrollback
  (ANSI-stripped, live-appended) and an input bar (text + Enter / quick keys).

### Data flow

`HerdrClient` (actor) owns a `HerdrTransport`. `SessionModel` calls typed async
methods and consumes `client.eventStream` to update `@Observable` state →
SwiftUI re-renders. Boots on `MockTransport`; swapping to `SSHTransport` is a
one-line change in `AppModel`.

## Build & run

Requires Xcode 15+ (iOS 17 deployment target) on macOS.

```sh
# 1. Core unit tests (no Apple SDK needed — runs on macOS or Linux)
swift test

# 2. Generate and open the app project
brew install xcodegen
xcodegen generate
open Herdr.xcodeproj
# Build & run the "Herdr" scheme on an iOS 17 simulator.
```

On launch, tap **Open demo workspace** to explore against sample data: the
workspace list shows live status badges flipping, drill into a workspace to see
its panes/agents, and open a pane to watch streamed output and send input.

## SSH transport

`App/Herdr/Connection/SSHTransport.swift` is the scaffold and documents the
intended bridge. To complete it:

1. Add **Citadel** (SwiftNIO SSH) — uncomment it in `project.yml`, re-run
   `xcodegen generate`.
2. In `connect()`, open an SSH connection with the host's `Credential`
   (key/password from the Keychain), start an exec channel running
   `socat - UNIX-CONNECT:<socketPath>` (fallback `nc -U <socketPath>`), and feed
   the channel's stdout through the existing `LineBuffer` → `IncomingMessage.decode`
   → `continuation.yield`. Implement `send(_:)` with `NDJSON.frame`.
3. Confirm the exact socket `method` strings and the subscribe/event method names
   in `Sources/HerdrKit/Protocol/Method.swift` against
   <https://herdr.dev/docs/socket-api/>.

## References

- Docs: <https://herdr.dev/docs/> · Socket API: <https://herdr.dev/docs/socket-api/>
- Source: <https://github.com/ogulcancelik/herdr> (`README.md`, `SKILL.md`)
