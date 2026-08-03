<p align="center">
  <img src="Assets/Brand/anchor-logo.svg" alt="Anchor" width="110" />
</p>

<h1 align="center">Anchor</h1>

<p align="center"><b>A Dynamic-Island focus companion for macOS — a lookout on the mast, not a jailer.</b></p>

<p align="center">
  <a href="https://github.com/TIFOSI528/anchor/releases/latest"><img src="https://img.shields.io/github/v/release/TIFOSI528/anchor?label=release" alt="Release"></a>
  <a href="https://github.com/TIFOSI528/anchor/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/TIFOSI528/anchor/ci.yml?branch=main&label=CI" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/TIFOSI528/anchor" alt="GPL-3.0"></a>
  <a href="https://github.com/TIFOSI528/anchor/releases"><img src="https://img.shields.io/github/downloads/TIFOSI528/anchor/total" alt="Downloads"></a>
</p>

<p align="center">
  <img src="Assets/demo/hero.svg" alt="drift → island countdown → snap back" width="600" />
  <br/><sub>Three acts on loop: invisible in green → drift countdown → click to snap back (design demo)</sub>
</p>

<p align="center"><a href="README.md">中文</a> · English</p>

---

You are writing code, and your hand opens Twitter anyway. Anchor will not lock it: the island lights up with a countdown, the screen slowly fogs as you stay away, and a single click takes you back to where you were working. **No blocking, no judgment — just a gentle tug when you drift.**

## Features

- **Dynamic Island, done natively** — hugs the real notch on MacBooks; becomes a menu-bar pill on notch-less Macs (idle state is a tiny dot that is click-through, so your status icons stay usable)
- **Three-zone rules** — green (apps/sites your current task allows) stays invisible; gray (unclassified) passes but starts a drift countdown; red (blocklist) intervenes immediately, with a 5-second slip buffer
- **Tab-level granularity** — with the Chrome extension, rules match full URLs: `github.com/your-repo` can be green while `github.com/trending` is red
- **One-click snap-back** — click the island to return to your most recent work app in under 200 ms
- **Sanctioned slacking** — long-press for 3 seconds to admit "I just want a break": 5 legal minutes; the first 3 per day end with a gentle "5 more?", after that it snaps you back
- **Focus Lock** — "only this": make the current page / site / app the sole green zone; while reading one paper, even your usual green apps count as drift
- **Progressive friction** — screen blur deepens along a time curve; it is a reminder, not a punishment, and every intervention has an off switch in Settings
- **A recap that reads like a letter** — every night at 22:00: an open-formula Deep Score, a 24-hour timeline, a weekly drift heatmap, today's "time thieves", and your top drift chains; on Sundays, one actionable rule suggestion you can apply with one click
- **Local-first** — everything lives in an on-disk SQLite database; no account, no telemetry, no subscription; GPL-3.0

## Install

Download the latest `Anchor-x.y.z.dmg` from [**Releases**](https://github.com/TIFOSI528/anchor/releases/latest) and drag it into Applications. The app is signed and notarized — no Gatekeeper hoops — and updates itself via Sparkle.

**Browser extension** (enables tab-level rules; optional but highly recommended):

1. Download `anchor-chrome-extension-x.y.z.zip` from the same [Releases](https://github.com/TIFOSI528/anchor/releases/latest) page and unzip it
2. Open `chrome://extensions`, enable **Developer mode**, click **Load unpacked**, and select the unzipped folder
3. The connection dot in Anchor's Settings → General turns green when linked

> Chrome Web Store listing is planned; until then the zip is the official channel.

<details>
<summary>Build from source</summary>

```bash
git clone https://github.com/TIFOSI528/anchor.git && cd anchor
swift build -c release
zsh scripts/package-app.sh    # → output/Anchor.app + dmg
```

Requires macOS 14+ / Xcode 16+ / Swift 6.0+. Dev loop: `open Package.swift`; tests: `swift test`.
</details>

## Quick start

A four-step guide runs on first launch — it explains the three zones, the escape hatch, the extension and the shortcut permission (re-open any time from the menu bar → **Getting Started**). After that:

1. An **anchor icon** appears in the menu bar; once you're in a working app, a **breathing green dot** sits at the top of your screen
2. Menu bar → **Scenes** → pick one (built-in *Coding / Reading / Browsing*; rules are editable with `*` wildcards)
3. Switch to an unrelated app — the dot expands into a countdown capsule; **click it** to snap back to work
4. Want to blocklist something the moment you drift into it? Menu bar → **"Add current app / site to red zone"** — effective immediately

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `⌃⌥⌘A` | Snap back to the latest green-zone app |
| `⌃⌥⌘B` | 5-minute sanctioned break |
| `⌃⌥⌘L` | Focus Lock: engage / release "only this" |
| `⌃⌥⌘P` | Pause the watch (≥10-char reason, lands in tonight's recap); press again to resume |

## Permissions & privacy

| Capability | Permission required |
|---|---|
| Foreground-app watch, island, recap | **None** |
| Browser tab rules | Extension (talks only to `127.0.0.1`, never the network) |
| Global hotkeys, scroll lock (off by default) | Accessibility (optional; degrades silently if not granted) |

All data stays in SQLite under `~/Library/Application Support/Anchor/` (mode `0600`, owner-only) — no account, no cloud, no telemetry. **URLs are stored as host + path only; anything after `?` is discarded before it reaches disk**, so search terms and share tokens never land in the database. Settings → Privacy & Data lets you export everything, erase all history, and set a retention window.

The one network request is the **update check**, which is off by default: when enabled or triggered manually it makes an HTTPS request to `raw.githubusercontent.com`, disclosing your IP address and Anchor version to GitHub. Nothing else leaves the machine — full details in [PRIVACY.md](PRIVACY.md).

> **Language:** the interface follows your system language — English and Simplified Chinese are both fully localized. To force one, use System Settings → General → Language & Region → Applications.

*Why not the Mac App Store?* Sandboxing would kill the foreground watch that the whole product stands on, so Anchor ships as a notarized direct download.

## Design stances

**No hard blocking** (there is always an escape hatch) · **no social pressure** (a self-discipline tool should not have leaderboards) · **no cloud, no telemetry**. The full product philosophy, island spec, recap spec and architecture live in [`docs/`](docs/) (Chinese-first).

## Contributing

Bugs & ideas → [Issues](https://github.com/TIFOSI528/anchor/issues) · workflow → [CONTRIBUTING.md](CONTRIBUTING.md) · history → [CHANGELOG.md](CHANGELOG.md) · releasing → [RELEASING.md](RELEASING.md)

---

<p align="center"><b>An invisible rubber band between you and your task.</b><br/>
<sub>GPL-3.0 · Built with <a href="https://github.com/MrKai77/DynamicNotchKit">DynamicNotchKit</a> · <a href="https://sparkle-project.org">Sparkle</a> · <a href="https://github.com/stephencelis/SQLite.swift">SQLite.swift</a></sub></p>
