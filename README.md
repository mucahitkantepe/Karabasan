# Karabasan

A tiny macOS menu bar app that prevents your Mac from sleeping. One click to toggle.

Named after the **Karabasan** — the sleep paralysis demon from Turkic mythology.

## Usage

- **Left-click** the eye icon to toggle idle sleep prevention on/off
- **Right-click** for Full mode (prevents ALL sleep including lid close, requires password)

Three states:
| Icon | Mode | What it does |
|------|------|-------------|
| Eye closed | Off | Sleep allowed |
| Eye open | On | Idle sleep prevented |
| Eye with warning | Full | All sleep prevented (including lid close) |

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
