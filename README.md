<div align="center">

<img src="Resources/icon-2048.png" width="128" height="128" alt="MagPulse Icon" />

# MagPulse

**Physical MagSafe dual-color pulse for your Mac's AI agents.**

English · [简体中文](README.zh-CN.md)

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple&style=flat-square)](#requirements)
[![Apple silicon](https://img.shields.io/badge/Apple%20silicon-arm64-black?style=flat-square)](#requirements)
[![Release](https://img.shields.io/github/v/release/ReffWu/magpulse?style=flat-square)](https://github.com/ReffWu/magpulse/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)

</div>

---

MagPulse maps thinking, waiting, and completion states across your Mac's coding tools and AI assistants directly to the physical dual-color LED on your MacBook's **MagSafe 3 port**.

Glance at the left edge of your laptop without switching windows or interrupting your flow:
- 🟠 **Amber Breathing**: Model is thinking, generating code, or executing tools.
- 🟢 **Emerald Green**: Turn or build is complete. Gracefully returns to system charging state upon review.
- 🟡 **Pulsing Amber**: Waiting for user input or tool execution permission.

<p align="center">
  <img src="Resources/screenshot_latest.png" width="360" alt="MagPulse Interface" />
</p>

## Supported Tools

### Desktop Apps
- **Antigravity**: Google DeepMind coding assistant (sub-second transcript activity & turn detection)
- **Claude Desktop**: Anthropic Claude official macOS app
- **ChatGPT Desktop**: OpenAI ChatGPT macOS client
- **Cursor**: AI-first code editor
- **VSCode**: Visual Studio Code
- **Xcode**: Apple Xcode IDE & build toolchain

### CLI & Terminal Tools
- **Claude Code**: Anthropic CLI agent (`claude`)
- **CodeX**: OpenAI Codex CLI runner
- **Terminal & Shells**: Terminal, iTerm2, Ghostty background builds

## Download & Installation

Download the official signed package:
👉 **[Download MagPulse.dmg](https://github.com/ReffWu/magpulse/releases/latest/download/MagPulse.dmg)**

Open the DMG and drag **MagPulse** into your `Applications` folder.

> Updates are delivered automatically and silently via Sparkle 2.

## Requirements

- MacBook Pro (14" or 16", 2021 or later) or MacBook Air (2022 or later) with **MagSafe 3**.
- Apple Silicon (M1/M2/M3/M4 series).
- macOS 14 Sonoma or macOS 15 Sequoia.

## Build from Source

```bash
git clone https://github.com/ReffWu/magpulse.git
cd magpulse

# Generate project and build
make build

# Run directly
make run

# Package signed DMG
make dmg
```

## Privacy & Security

- **Strictly Local**: Reads local transcripts, processes, and Apple SMC registers only.
- **Zero Cloud Dependence**: No telemetry, no account required, zero data leaves your Mac.

## License

[MIT](LICENSE) © 2026 Reff Wu
