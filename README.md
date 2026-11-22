# OC Pass

**Your self-hosted OpenClaw assistant, on your iPhone.**

[![Download on the App Store](https://img.shields.io/badge/App%20Store-Download-black?logo=apple&logoColor=white)](https://apps.apple.com/app/id6825438357)

OC Pass connects your phone to the [OpenClaw](https://openclaw.ai) gateway running on your own computer. Paste one pairing line — no domain, no public IP, no port forwarding.

## How it works

```
iPhone (OC Pass)  ⇄  relay (forwards bytes only)  ⇄  tunnel on your machine  ⇄  127.0.0.1:18789
```

- The gateway stays bound to localhost.
- The relay forwards WebSocket frames and does not store message content.
- Pairing is a single line of text containing the channel id, secret and your gateway token.

## Features

- Chat, images, files and voice input
- Console: usage, automations, node status
- Demo mode that works offline
- Works with OpenClaw on macOS and Linux

## Requirements

- A computer running OpenClaw with the gateway running
- iOS 17+

## Pricing

Free relay allowance (100 MB). Optional subscription for 1 GB.

## Privacy

Messages are delivered only to your own gateway. The relay does not keep message content. See the privacy policy linked from the App Store listing.

## Development

```bash
brew install xcodegen
xcodegen generate
open OpenClawRemote.xcodeproj
```

CI: `.github/workflows/ios.yml` builds the simulator target on push; a manual dispatch archives and uploads to TestFlight (secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `TEAM_ID`).

---

© XOIO. OC Pass is a client for OpenClaw; it is not affiliated with Telegram or Apple.
