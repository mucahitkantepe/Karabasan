# Karabasan

A tiny macOS menu bar app that prevents your Mac from sleeping. One click to toggle.

Named after the **Karabasan** — the sleep paralysis demon from Turkic mythology.

## Usage

- **Left-click** the eye icon to toggle sleep prevention on/off (4 hours)
- **Right-click** to pick a duration (30 minutes to 8 hours, or indefinitely)
- **Hover** the icon to see time left on a timed session

| Icon | Mode | What it does |
|------|------|-------------|
| Eye closed | Off | Sleep allowed |
| Red eye | On | ALL sleep prevented (including lid close) |

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/mucahitkantepe/Karabasan/main/install.sh | sh
```

Or download `Karabasan.zip` from [Releases](../../releases) manually.

### Build from Source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/mucahitkantepe/Karabasan.git
cd Karabasan
./build.sh
open build/Karabasan.app
```

Builds a universal binary (Apple Silicon + Intel).

## Security

- **No network access** — zero outbound connections
- **No data collection** — no files read or written
- **Self-cleaning** — idle assertion is released when the app quits
- Full mode uses `pmset disablesleep` and persists after quit (by design)

## License

MIT
