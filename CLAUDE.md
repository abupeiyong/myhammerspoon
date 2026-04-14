# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal Hammerspoon configuration for macOS automation. Hammerspoon is a Lua-based macOS automation framework. All configuration is loaded by Hammerspoon from `~/.hammerspoon/init.lua` on launch.

## Reloading

After editing any Lua files, reload the config in Hammerspoon with Hyper+R (Cmd+Alt+Ctrl+Shift+R), or run `hs -c "hs.reload()"` from terminal.

## Architecture

- **init.lua** — Main entry point. Defines all hotkey bindings and their handler functions. Uses the "Hyper" key (Cmd+Alt+Ctrl+Shift) as the modifier for all shortcuts.
- **config.lua** — Returns a table with sensitive config (API keys). Loaded via `require("config")`. Listed in `.gitignore`.
- **simple_input.lua** — Reusable webview-based input dialog module (currently unused in init.lua but available).
- **Spoons/** — Directory for Hammerspoon Spoon plugins (currently empty).

## Key bindings defined in init.lua

| Key | Function |
|-----|----------|
| Hyper+T | Translate selected text via OpenAI API |
| Hyper+S | Text-to-speech toggle for selected text |
| Hyper+I | Quick reminder from selection |
| Hyper+M | Reminder with edit dialog |
| Hyper+N | Reminder via AppleScript |
| Hyper+1 | Decrease external display brightness |
| Hyper+2 | Increase external display brightness |
| Hyper+R | Reload Hammerspoon config |

## External dependencies

- **OpenAI API** — Used for translation (Hyper+T). Requires `OPENAI_API_KEY` in `config.lua`.
- **m1ddc** (`/opt/homebrew/bin/m1ddc`) — Used for external display brightness control via DDC/CI. Install with `brew install m1ddc`.

## Conventions

- All hotkeys use the `hyper` modifier variable defined as `{"cmd", "alt", "ctrl", "shift"}`.
- Chinese comments describe hotkey purposes (e.g., `-- 快捷键：Hyper + T 翻译选中文本`).
- API calls use `hs.http.asyncPost` for non-blocking requests.
- User feedback is shown via `hs.alert.show` with custom styling options.
- The translation function uses OpenAI chat completions endpoint with a system prompt for English translation.
