# Herdr iOS

A native iOS (SwiftUI) client for [Herdr](https://herdr.dev), the terminal-native
**agent multiplexer**. Browse your workspaces, watch live agent status, and read
or drive any pane from your phone.

> **Status:** the full app runs on an in-memory **Mock** transport with realistic
> data and live status updates, *and* over a real **SSH** connection that bridges
> to the remote Herdr Unix socket (see [SSH transport](#ssh-transport)). Known
> limitations: key auth currently supports OpenSSH-format RSA keys only, and host
> keys are accepted without pinning (TOFU is a follow-up).

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

`App/Herdr/Connection/SSHTransport.swift` implements the bridge with **Citadel**
(SwiftNIO SSH):

1. `connect()` opens an `SSHClient` connection authenticated with the host's
   `Credential` (password, or an OpenSSH-format RSA private key, from the
   Keychain).
2. It then opens a `withExec` channel running
   `socat - UNIX-CONNECT:<socketPath> || nc -U <socketPath>` and suspends until
   the channel is live. The channel's stdout is fed through the existing
   `LineBuffer` → `IncomingMessage.decode` → `continuation.yield`; `send(_:)`
   writes `NDJSON.frame(request)` to the channel's stdin. A leading `~` in the
   socket path is rewritten to `$HOME` so the remote shell expands it.

To switch the app onto SSH, point `AppModel.connect(to:)` at a saved `Host` (it
already builds an `SSHTransport`); the demo entry point stays on the Mock.

**Follow-ups:**

- Key auth handles OpenSSH-format **RSA** keys only (`Insecure.RSA.PrivateKey`).
  Ed25519/ECDSA support needs a proper OpenSSH key parser; password auth works
  for everything in the meantime.
- Host keys are accepted via `.acceptAnything()`. Add trust-on-first-use pinning
  before treating this as secure against MITM.
- Confirm the exact socket `method` strings and subscribe/event names in
  `Sources/HerdrKit/Protocol/Method.swift` against
  <https://herdr.dev/docs/socket-api/>.

## References

- Docs: <https://herdr.dev/docs/> · Socket API: <https://herdr.dev/docs/socket-api/>
- Source: <https://github.com/ogulcancelik/herdr> (`README.md`, `SKILL.md`)
