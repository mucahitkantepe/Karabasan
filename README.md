# Karabasan

A tiny macOS menu bar app that prevents your Mac from sleeping. One click to toggle.

Named after the **Karabasan** — the sleep paralysis demon from Turkic mythology that keeps you from sleeping.

## How It Works

- Click the **eye icon** in the menu bar to toggle sleep prevention on/off
- **Eye open** = sleep prevented (Karabasan is upon you)
- **Eye closed** = sleep allowed (Karabasan sleeps)
- Right-click for quit menu

Uses macOS `IOPMAssertion` API (same as Caffeine/Amphetamine) — no elevated privileges needed.

## Install

### Download

Grab the latest `Karabasan.zip` from [Releases](../../releases), unzip, and drag `Karabasan.app` to `/Applications`.

> On first launch, macOS may block the app since it's unsigned. Go to **System Settings > Privacy & Security** and click **Open Anyway**.

### Build from Source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/mucahitkantepe/Karabasan.git
cd Karabasan
./build.sh
open build/Karabasan.app
```

The build script compiles a universal binary (Apple Silicon + Intel).

## How Is This Different from Caffeine?

Same concept, same underlying API. Karabasan is:
- Open source (single Swift file, ~80 lines)
- No App Store, no tracking, no updates phoning home
- Named after a Turkic demon instead of a beverage

## Security

- **No elevated privileges** — standard user-level `IOPMAssertionCreate` API
- **No network access** — zero outbound connections
- **No data collection** — no files read or written
- **Self-cleaning** — assertion is released when the app quits
- Only prevents **idle** sleep. Closing the lid and Apple menu > Sleep still work.

## License

MIT
