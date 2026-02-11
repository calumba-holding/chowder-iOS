# Chowder - iOS Client for OpenClaw

Chowder is a native iOS chat client that connects to an [OpenClaw](https://docs.openclaw.ai) gateway over WebSocket. It lets you talk to your personal AI assistant from your iPhone or iPad, using the same sessions and routing as WhatsApp, Telegram, Discord, and other OpenClaw channels.

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
      |  chat.send (message)          |  --> Pi agent (RPC)
      |------------------------------>|
      |  agent events (text deltas)   |
      |<------------------------------|
      |  chat final                   |
      |<------------------------------|
```

Chowder connects as a `cli` mode operator client using the OpenClaw Gateway Protocol v3. It authenticates with a shared gateway token and streams AI responses via WebSocket events.

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
   - Client identity (`cli` / `cli` mode)
   - Auth token
   - Operator role and scopes
4. The gateway validates and returns `hello-ok`
5. The connection is authenticated and ready for chat

### Sending Messages

Messages are sent as `chat.send` requests with an idempotency key. The gateway acks immediately with a `runId`, then streams the AI response as `agent` events:

- `agent` / `stream: "assistant"` -- text deltas (incremental tokens)
- `agent` / `stream: "lifecycle"` -- start/end of agent run
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

### Gateway not reachable over Tailscale

- Ensure `gateway.bind` is set to `"tailnet"` (not `"loopback"`)
- Restart the gateway after config changes: `openclaw gateway restart`
- Check that the gateway port (18789) is not blocked

## Project Structure

```
Chowder/
  ChowderApp.swift          -- App entry point
  Models/
    ConnectionConfig.swift   -- Gateway URL, token, session key storage
    Message.swift            -- Chat message model (user/assistant)
  Services/
    ChatService.swift        -- WebSocket connection + OpenClaw protocol
    KeychainService.swift    -- Secure token storage
  ViewModels/
    ChatViewModel.swift      -- Chat state, message list, delegates
  Views/
    ChatView.swift           -- Main chat screen
    ChatHeaderView.swift     -- Header with online/offline status
    MessageBubbleView.swift  -- Message bubble UI
    SettingsView.swift       -- Gateway URL, token, session config
```

## OpenClaw Protocol Reference

- [Gateway Protocol](https://docs.openclaw.ai/gateway/protocol) -- WebSocket framing and handshake
- [Tailscale Setup](https://docs.openclaw.ai/gateway/tailscale) -- Network access via Tailscale
- [Configuration](https://docs.openclaw.ai/gateway/configuration) -- All gateway config keys
- [Troubleshooting](https://docs.openclaw.ai/gateway/troubleshooting) -- Gateway diagnostics

## License

MIT
