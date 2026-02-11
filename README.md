# Chowder - iOS Client for OpenClaw

Chowder is a native iOS chat client that connects to an [OpenClaw](https://docs.openclaw.ai) gateway over WebSocket. It lets you talk to your personal AI assistant from your iPhone or iPad, using the same sessions and routing as WhatsApp, Telegram, Discord, and other OpenClaw channels.

## Features

- **Real-time chat** with streaming AI responses via WebSocket
- **Persistent chat history** stored locally (survives app kill/relaunch)
- **Agent identity sync** -- dynamically mirrors the bot's IDENTITY.md (name, creature, vibe, emoji) and USER.md (what the bot knows about you) from the OpenClaw workspace
- **"Thinking..." shimmer** -- shows an animated status line while the agent is working, with a minimum display duration so it doesn't flash on fast responses
- **Verbose tool activity** -- automatically enables `/verbose on` so tool calls (read, write, bash, etc.) update the shimmer with real-time labels like "Reading IDENTITY.md..."
- **Activity detail card** -- tap the shimmer to see the full list of thinking steps and tool calls the agent performed
- **Custom agent avatar** -- pick a profile photo for the agent from your photo library
- **Settings sync** -- edit the bot's identity or your user profile in Settings and the changes are written back to the OpenClaw workspace files
- **Automatic reconnection** with 3-second backoff after network interruptions
- **Debug log** -- tap the header to view raw WebSocket traffic for troubleshooting

## Prerequisites

- **Mac mini (or any macOS/Linux host)** running OpenClaw gateway
- **Tailscale** installed on both the gateway host and the iOS device (same tailnet)
- **Xcode 15+** on a Mac to build and install Chowder
- **iOS 17+** on the target device

## Architecture

```
iPhone (Chowder)                Mac mini (Gateway)
      |                               |
      |  ws://<tailscale-ip>:18789    |
      |------------------------------>|
      |  connect.challenge (nonce)    |
      |<------------------------------|
      |  connect (auth + client info) |
      |------------------------------>|
      |  hello-ok (protocol 3)       |
      |<------------------------------|
      |                               |
      |  /verbose on (invisible)      |  --> enables tool summaries
      |------------------------------>|
      |  sync: read IDENTITY/USER.md  |  --> agent reads workspace files
      |------------------------------>|
      |  chat.final (sync response)   |  --> parsed into BotIdentity/UserProfile
      |<------------------------------|
      |                               |
      |  chat.send (user message)     |  --> Pi agent (RPC)
      |------------------------------>|
      |  chat.delta (tool summaries)  |  --> shimmer: "Reading IDENTITY.md..."
      |<------------------------------|
      |  agent/assistant (text deltas)|  --> streamed into chat bubble
      |<------------------------------|
      |  agent/lifecycle (end)        |  --> message complete
      |<------------------------------|
      |  chat.final (full response)   |
      |<------------------------------|
```

Chowder connects as an `openclaw-ios` / `ui` mode operator client using the OpenClaw Gateway Protocol v3. On connect, it silently enables verbose mode and syncs the agent's workspace files to populate the header name and cached identity/profile data.

## Setup Guide

### 1. Install and Start OpenClaw on the Mac mini

```bash
npm install -g openclaw@latest
openclaw onboard --install-daemon
```

The onboarding wizard will generate a gateway token and install the gateway as a background service.

### 2. Configure the Gateway for Tailscale Access

The gateway needs to listen on the Tailscale network interface so your iPhone can reach it. Edit `~/.openclaw/openclaw.json` on the Mac mini:

```json
{
  "gateway": {
    "bind": "tailnet",
    "auth": {
      "mode": "token",
      "token": "your-gateway-token"
    }
  }
}
```

Then restart the gateway:

```bash
openclaw gateway restart
```

Verify it's running:

```bash
openclaw gateway status
openclaw doctor
```

### 3. Install Tailscale on Both Devices

- **Mac mini**: Install Tailscale from [tailscale.com](https://tailscale.com) and sign in
- **iPhone**: Install the Tailscale app from the App Store and sign in to the same tailnet

Confirm connectivity by finding the Mac mini's Tailscale IP:

```bash
# On the Mac mini:
tailscale ip -4
# Example output: 100.104.164.27
```

### 4. Find Your Gateway Token

The gateway token was generated during onboarding. To find it:

```bash
openclaw config get gateway.auth.token
```

Or generate a new one:

```bash
openclaw doctor --generate-gateway-token
```

### 5. Build and Install Chowder

```bash
git clone <this-repo>
cd chowder-iOS/Chowder
open Chowder.xcodeproj
```

In Xcode:
1. Select your iPhone as the build target
2. Update the signing team in the project settings
3. Build and run (Cmd+R)

### 6. Configure Chowder on Your iPhone

1. Open Chowder -- the Settings sheet appears on first launch
2. Fill in the fields:
   - **Gateway**: `ws://<tailscale-ip>:18789` (e.g. `ws://100.104.164.27:18789`)
   - **Token**: paste the gateway token from step 4
   - **Session**: leave as `agent:main:main` (default) or change to target a specific agent
3. Tap **Save**

Chowder will connect to the gateway, complete the WebSocket handshake, and show **Online** in the header.

## How It Works

### Connection Flow

1. Chowder opens a WebSocket to the gateway
2. The gateway sends a `connect.challenge` with a nonce
3. Chowder responds with a `connect` request containing:
   - Protocol version (v3)
   - Client identity (`openclaw-ios` / `ui` mode)
   - Auth token
   - Operator role and scopes
4. The gateway validates and returns `hello-ok`
5. Chowder silently sends `/verbose on` to enable tool call summaries
6. Chowder sends an invisible sync request asking the bot to read IDENTITY.md and USER.md
7. The response is parsed to populate `BotIdentity` (header name, creature, vibe) and `UserProfile`

### Workspace Sync

Chowder dynamically mirrors the bot's workspace files -- it never hardcodes identity values. On connect, it asks the bot to read `IDENTITY.md` and `USER.md` and return their contents in a delimiter-based format. The response is parsed into structured Swift models (`BotIdentity`, `UserProfile`) and cached locally via `LocalStorage`. When the user edits these in Settings, the changes are written back to the workspace via a chat-driven write request.

### Verbose Tool Activity

With `/verbose on`, the gateway sends tool call summaries as separate `chat.delta` events (e.g., "📄 read: IDENTITY.md"). Chowder detects these by pattern-matching known tool names and routes them to the shimmer display instead of the chat. This gives users real-time visibility into what the agent is doing.

### Sending Messages

Messages are sent as `chat.send` requests with an idempotency key. The gateway acks immediately with a `runId`, then streams the AI response as `agent` events:

- `agent` / `stream: "assistant"` -- text deltas (incremental tokens)
- `agent` / `stream: "lifecycle"` -- start/end of agent run
- `chat` / `state: "delta"` -- verbose tool summaries (parsed for shimmer)
- `chat` / `state: "final"` -- complete message with full text

### Reconnection

Chowder automatically reconnects after network interruptions with a 3-second backoff.

## Troubleshooting

### "Not connected" / stays Offline

- Verify Tailscale is connected on both devices: `tailscale status`
- Confirm the gateway is running: `openclaw gateway status`
- Check the gateway URL includes `ws://` (not `http://`)
- Try pinging the Mac mini's Tailscale IP from the iPhone

### Connection drops immediately

- Verify the token matches: `openclaw config get gateway.auth.token`
- Check gateway logs for rejection reasons: `openclaw logs --follow`

### Connected but no AI response

- Check model auth: `openclaw models status`
- Ensure an API key or OAuth token is configured for your model provider
- Try sending a message from the CLI to verify the agent works: `openclaw agent --message "hello"`

### Header shows "Chowder" instead of the bot's name

- The bot's IDENTITY.md may be empty. Tell the bot to fill it in: "Set your name to OddJob in IDENTITY.md"
- Check the debug log for `Synced IDENTITY.md` or `Sync response could not be parsed` messages

### Gateway not reachable over Tailscale

- Ensure `gateway.bind` is set to `"tailnet"` (not `"loopback"`)
- Restart the gateway after config changes: `openclaw gateway restart`
- Check that the gateway port (18789) is not blocked

## Project Structure

```
Chowder/
  ChowderApp.swift              -- App entry point
  Models/
    AgentActivity.swift          -- Thinking/tool step tracking for shimmer
    BotIdentity.swift            -- Parsed IDENTITY.md model + markdown serialization
    ConnectionConfig.swift       -- Gateway URL, token, session key storage
    Message.swift                -- Chat message model (Codable, persisted)
    UserProfile.swift            -- Parsed USER.md model + markdown serialization
  Services/
    ChatService.swift            -- WebSocket connection, protocol handling, verbose tool parsing
    KeychainService.swift        -- Secure token storage
    LocalStorage.swift           -- File-based persistence (messages, avatar, identity, profile)
  ViewModels/
    ChatViewModel.swift          -- Chat state, sync orchestration, shimmer logic
  Views/
    AgentActivityCard.swift      -- Detail card showing all thinking/tool steps
    ChatView.swift               -- Main chat screen with shimmer + activity card
    ChatHeaderView.swift         -- Header with dynamic bot name + online/offline
    MessageBubbleView.swift      -- Message bubble with markdown rendering
    SettingsView.swift           -- Gateway config, identity/profile editing, avatar picker
    ThinkingShimmerView.swift    -- Animated "Thinking..." / tool status shimmer line
```

## OpenClaw Protocol Reference

- [Gateway Protocol](https://docs.openclaw.ai/gateway/protocol) -- WebSocket framing and handshake
- [Thinking Levels](https://docs.openclaw.ai/tools/thinking) -- `/verbose`, `/think`, `/reasoning` directives
- [Agent Loop](https://docs.openclaw.ai/concepts/agent-loop) -- How the agent processes messages
- [Tailscale Setup](https://docs.openclaw.ai/gateway/tailscale) -- Network access via Tailscale
- [Configuration](https://docs.openclaw.ai/gateway/configuration) -- All gateway config keys

## License

MIT
