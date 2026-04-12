# Hammerspoon Configuration

A personal Hammerspoon configuration for macOS automation, featuring ChatGPT-powered translation, Reminders integration, and external display control.

## Features

### Translation (ChatGPT Integration)

#### Hyper+T - Smart Translation
- Automatically copies and translates selected text to English
- If no text is selected, uses clipboard content
- Auto-replaces selected text with translation result
- Optimizes grammar and expression using ChatGPT (gpt-4o-mini model)
- Shows confirmation when text is replaced

### Reminders Integration

#### Hyper+I - Quick Reminder from Selection
- Creates a reminder from currently selected text
- Adds directly to Reminders inbox
- Requires Reminders app authorization

#### Hyper+M - Reminder with Dialog
- Opens input dialog to create custom reminders
- Enter reminder text and press Enter to create
- Press Escape to cancel

#### Hyper+N - Reminder via AppleScript
- Alternative method using AppleScript
- Useful if other methods fail
- Requires system automation permissions

### Display Control

#### Hyper+1/2 - External Display Brightness
- **Hyper+1**: Decrease brightness by 10%
- **Hyper+2**: Increase brightness by 10%
- Uses `m1ddc` for Apple Silicon compatibility
- Shows current brightness level in notification
- Caches brightness value for consistency

### System

#### Hyper+R - Reload Configuration
- Instantly reloads Hammerspoon configuration
- Useful after making changes to init.lua

## Key Combinations

The "Hyper" key is defined as: **Cmd + Alt + Ctrl + Shift**

| Shortcut | Action |
|----------|--------|
| Hyper+T | Translate selected text or clipboard |
| Hyper+I | Create reminder from selection |
| Hyper+M | Create reminder with dialog |
| Hyper+N | Create reminder via AppleScript |
| Hyper+1 | Decrease display brightness |
| Hyper+2 | Increase display brightness |
| Hyper+R | Reload configuration |

## Setup

### Prerequisites

1. **Hammerspoon** - Install from [https://www.hammerspoon.org/](https://www.hammerspoon.org/)

2. **OpenAI API Key** - Required for translation features
   - Get your API key from [OpenAI Platform](https://platform.openai.com/)
   - Create `config.lua` in `~/.hammerspoon/`:
   ```lua
   return {
     openai_api_key = "your-api-key-here"
   }
   ```

3. **m1ddc** - Required for display brightness control on Apple Silicon
   ```bash
   brew install m1ddc
   ```

### Installation

1. Clone or copy `init.lua` to `~/.hammerspoon/`
2. Create `config.lua` with your OpenAI API key
3. Launch Hammerspoon
4. Grant necessary permissions when prompted:
   - Accessibility (for hotkeys and text selection)
   - Automation (for Reminders integration)

## Configuration Files

### init.lua
Main configuration file containing all hotkey bindings and functions.

### config.lua
Stores sensitive configuration like API keys:
```lua
return {
  openai_api_key = "sk-proj-..."  -- Your OpenAI API key
}
```

## Technical Details

### Translation Implementation
- Uses OpenAI's ChatGPT API (gpt-4o-mini model)
- Sends selected/clipboard text with system prompt for translation
- Optimizes for natural, professional English expression
- Handles API errors gracefully with user notifications

### Display Control Implementation
- Primary method: `m1ddc` command-line tool for DDC/CI control
- Fallback: Native Hammerspoon screen brightness API
- Caches brightness value (default: 70) to handle read failures
- Adjusts in 10% increments with bounds checking (10-100)

### Reminders Integration
Multiple implementation methods for reliability:
1. Direct URL scheme (`x-apple-reminderkit://`)
2. Shell command with `open`
3. AppleScript automation
4. Each method has different permission requirements

## Troubleshooting

### Translation Not Working
- Check OpenAI API key in config.lua
- Verify internet connection
- Check OpenAI API status and credits

### Display Brightness Not Responding
- Ensure m1ddc is installed: `brew install m1ddc`
- Try using number keys (1, 2) instead of F-keys if having issues
- Check if external display supports DDC/CI

### Reminders Not Creating
- Grant Automation permission in System Preferences > Privacy & Security
- Try alternative methods (Hyper+M or Hyper+N)
- Check if Reminders app is running

### Hotkeys Not Working
- Grant Accessibility permission to Hammerspoon
- Check for conflicts with other apps using same key combinations
- Reload configuration with Hyper+R

## Model Information

Currently using **gpt-4o-mini** for translation:
- Fast response times
- Cost-effective
- Excellent translation quality
- Good at preserving context and tone

To change the model, edit the `model` field in the translation functions.

## Privacy & Security

- API keys stored locally in config.lua (not in main init.lua)
- All translations processed via HTTPS to OpenAI
- No data stored or logged beyond Hammerspoon's console
- Clipboard content only accessed when explicitly triggered

## License

Personal configuration - feel free to adapt for your own use.

## Credits

- [Hammerspoon](https://www.hammerspoon.org/) - Powerful macOS automation tool
- [m1ddc](https://github.com/waydabber/m1ddc) - Display control for Apple Silicon
- [OpenAI](https://openai.com/) - ChatGPT API for translations