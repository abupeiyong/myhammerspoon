-- Load configuration
local config = require("config")

-- ChatGPT API configuration
local OPENAI_API_KEY = config.OPENAI_API_KEY
local OPENAI_API_URL = "https://api.openai.com/v1/chat/completions"

-- ElevenLabs API configuration
local ELEVENLABS_API_KEY = config.ELEVENLABS_API_KEY or "your-api-key-here"
local ELEVENLABS_VOICE_ID = config.ELEVENLABS_VOICE_ID or "JBFqnCBsd6RMkjVDRZzb"
local ELEVENLABS_API_URL = "https://api.elevenlabs.io/v1/text-to-speech/" .. ELEVENLABS_VOICE_ID


-- Function to translate selected text using ChatGPT
local function translateSelectedText()
  -- First, try to copy the current selection
  local hasSelection = false
  local selectedText = nil

  -- Simulate Cmd+C to copy current selection
  hs.eventtap.keyStroke({"cmd"}, "c")

  -- Small delay to ensure clipboard is updated
  hs.timer.usleep(100000) -- 100ms delay

  -- Get the clipboard content
  local currentClipboard = hs.pasteboard.getContents()

  -- Check if we actually copied something new (by checking if clipboard changed)
  -- We'll consider it a selection if we successfully got text from clipboard after Cmd+C
  local elem = hs.uielement.focusedElement()
  if elem then
    local elemSelectedText = elem:selectedText()
    if elemSelectedText and elemSelectedText ~= "" then
      hasSelection = true
      selectedText = currentClipboard
    end
  end

  -- If no selection detected, just use current clipboard content
  if not hasSelection then
    selectedText = currentClipboard
  end

  if not selectedText or selectedText == "" then
    hs.alert.show("No text selected or in clipboard", 2)
    return
  end

  -- Prepare the request body
  local requestBody = hs.json.encode({
    model = "gpt-5-nano",
    -- Disable hidden reasoning (see dictionary lookup note): translation is a
    -- direct task, so "minimal" cuts latency ~7x with no quality loss.
    reasoning_effort = "minimal",
    messages = {
      {
        role = "system",
        content = "You are a professional translator and language expert. Translate the following text to English, and optimize its grammar and expression to make it more natural and professional. Only return the translated and optimized English text without any explanation."
      },
      {
        role = "user",
        content = selectedText
      }
    }
  })

  -- Make the API request
  hs.http.asyncPost(
    OPENAI_API_URL,
    requestBody,
    {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. OPENAI_API_KEY
    },
    function(status, body, headers)
      if status == 200 then
        local response = hs.json.decode(body)
        if response and response.choices and response.choices[1] and response.choices[1].message then
          local translatedText = response.choices[1].message.content

          -- Copy to clipboard
          hs.pasteboard.setContents(translatedText)

          -- If there was selected text, automatically paste to replace it
          if hasSelection then
            -- Small delay to ensure clipboard is updated
            hs.timer.doAfter(0.1, function()
              -- Simulate Cmd+V to paste
              hs.eventtap.keyStroke({"cmd"}, "v")

              -- Show brief notification
              hs.alert.show("✓ Replaced with translation", {
                textSize = 14,
                fadeInDuration = 0.1,
                fadeOutDuration = 1
              })
            end)
          else
            -- If no selection, just show the result
            hs.alert.show(translatedText, {
              textSize = 14,
              fadeInDuration = 0.25,
              fadeOutDuration = 2
            })
          end
        else
          hs.alert.show("Error: Invalid response from ChatGPT", 3)
        end
      else
        local errorMsg = "Error: API request failed"
        if body then
          local errorData = hs.json.decode(body)
          if errorData and errorData.error and errorData.error.message then
            errorMsg = "Error: " .. errorData.error.message
          end
        end
        hs.alert.show(errorMsg, 5)
        print("API Error - Status:", status, "Body:", body)
      end
    end
  )

  -- Show loading indicator with selected text preview
  local preview = selectedText
  if #preview > 50 then
    preview = string.sub(preview, 1, 50) .. "..."
  end
  hs.alert.show("Translating: " .. preview, {
    textSize = 14,
    fadeOutDuration = 0
  })
end

local hyper = {"cmd", "alt", "ctrl", "shift"}

-- 快捷键：Hyper + T 翻译选中文本或剪贴板内容
hs.hotkey.bind(hyper, "T", translateSelectedText)

-- Store current audio player for stopping
local currentAudioPlayer = nil

-- ElevenLabs TTS synthesis params (shared by all speak functions; part of cache key)
local TTS_MODEL_ID = "eleven_flash_v2_5"
local TTS_VOICE_SETTINGS = { stability = 0.5, similarity_boost = 0.5 }

-- On-disk cache for generated audio, keyed by voice + model + text. Identical
-- requests replay the cached mp3 instead of hitting the API again.
local TTS_CACHE_DIR = os.getenv("HOME") .. "/.hammerspoon/tts_cache"
hs.fs.mkdir(TTS_CACHE_DIR)  -- no-op if it already exists

local function ttsCachePath(text)
  local key = ELEVENLABS_VOICE_ID .. "|" .. TTS_MODEL_ID .. "|" .. text
  return TTS_CACHE_DIR .. "/" .. hs.hash.MD5(key) .. ".mp3"
end

-- Play a local mp3, tracking it as the current player. Returns true if started.
local function playCachedAudio(path, onStart, onFail)
  currentAudioPlayer = hs.sound.getByFile(path)
  if currentAudioPlayer then
    currentAudioPlayer:play()
    if onStart then onStart() end
    currentAudioPlayer:setCallback(function() currentAudioPlayer = nil end)
    return true
  end
  if onFail then onFail() end
  return false
end

-- Speak text via ElevenLabs, using the on-disk cache. Stops any current
-- playback first. callbacks: onSpeaking() once playback starts, onError(msg).
local function speakWithCache(text, callbacks)
  callbacks = callbacks or {}
  if not text or text == "" then return end

  if currentAudioPlayer and currentAudioPlayer:isPlaying() then
    currentAudioPlayer:stop()
    currentAudioPlayer = nil
  end

  local path = ttsCachePath(text)

  -- Cache hit: replay without touching the API
  if hs.fs.attributes(path) then
    if playCachedAudio(path, callbacks.onSpeaking) then return end
    os.remove(path)  -- unreadable/corrupt; drop it and re-fetch below
  end

  if callbacks.onGenerating then callbacks.onGenerating() end

  local requestBody = hs.json.encode({
    text = text,
    model_id = TTS_MODEL_ID,
    voice_settings = TTS_VOICE_SETTINGS
  })

  hs.http.asyncPost(
    ELEVENLABS_API_URL,
    requestBody,
    {
      ["Content-Type"] = "application/json",
      ["xi-api-key"] = ELEVENLABS_API_KEY,
      ["Accept"] = "audio/mpeg"
    },
    function(status, body, headers)
      if status == 200 then
        local file = io.open(path, "wb")
        if file then
          file:write(body)
          file:close()
          playCachedAudio(path, callbacks.onSpeaking, function()
            os.remove(path)
            if callbacks.onError then callbacks.onError("Failed to play audio") end
          end)
        end
      else
        local errorMsg = "TTS API request failed"
        if body then
          local errorData = hs.json.decode(body)
          if errorData and errorData.detail then
            errorMsg = errorData.detail.message or errorData.detail.status or errorMsg
          end
        end
        if callbacks.onError then callbacks.onError(errorMsg) end
        print("ElevenLabs API Error - Status:", status, "Body:", body)
      end
    end
  )
end

-- Function to speak selected text using ElevenLabs
local function speakSelectedText()
  -- First, try to copy the current selection
  hs.eventtap.keyStroke({"cmd"}, "c")

  -- Small delay to ensure clipboard is updated
  hs.timer.usleep(100000) -- 100ms delay

  -- Get the clipboard content
  local textToSpeak = hs.pasteboard.getContents()

  if not textToSpeak or textToSpeak == "" then
    hs.alert.show("No text selected or in clipboard", {
      textSize = 14,
      fadeInDuration = 0.1,
      fadeOutDuration = 1
    })
    return
  end

  -- Check if already playing and stop if so
  if currentAudioPlayer and currentAudioPlayer:isPlaying() then
    currentAudioPlayer:stop()
    currentAudioPlayer = nil
    hs.alert.show("⏹ Stopped speaking", {
      textSize = 14,
      fadeInDuration = 0.1,
      fadeOutDuration = 0.5
    })
    return
  end

  speakWithCache(textToSpeak, {
    onGenerating = function()
      hs.alert.show("🔊 Generating speech...", {
        textSize = 14,
        fadeInDuration = 0.1,
        fadeOutDuration = 0
      })
    end,
    onSpeaking = function()
      hs.alert.show("🔊 Speaking...", {
        textSize = 14,
        fadeInDuration = 0.1,
        fadeOutDuration = 0.5
      })
    end,
    onError = function(msg)
      hs.alert.show(msg, {
        textSize = 14,
        fadeInDuration = 0.1,
        fadeOutDuration = 2
      })
    end
  })
end

-- 快捷键：Hyper + S 朗读选中文本
hs.hotkey.bind(hyper, "S", speakSelectedText)

-- Play given text via ElevenLabs (fire-and-forget; stops any current playback)
local function speakText(text)
  speakWithCache(text)
end

-- Append a dictionary entry to today's Obsidian daily note (creates file if missing)
local function appendToDailyNote(word, meaning)
  local dailyDir = "/Users/yangpeiyong/Documents/Becoming/Daily"
  local today = os.date("%Y-%m-%d")
  local filePath = dailyDir .. "/" .. today .. ".md"

  local cleanMeaning = meaning:gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  local cleanWord = word:gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  local line = string.format("- **%s** — %s\n", cleanWord, cleanMeaning)

  local file = io.open(filePath, "a")
  if file then
    file:write(line)
    file:close()
    return true
  end
  return false
end

-- Run the dictionary flow on a captured word.
local function runDictionaryLookup(word)
  word = word:gsub("^%s+", ""):gsub("%s+$", "")
  if word == "" then
    hs.alert.show("No text selected", 2)
    return
  end

  hs.alert.show("📖 " .. word, {
    textSize = 14,
    fadeOutDuration = 0
  })

  local requestBody = hs.json.encode({
    model = "gpt-5-nano",
    -- gpt-5-nano is a reasoning model; without this it burns ~1500 hidden
    -- reasoning tokens (~9s) on a lookup that only needs a dozen output tokens.
    -- "minimal" disables reasoning → ~1.3s with identical output quality.
    reasoning_effort = "minimal",
    messages = {
      {
        role = "system",
        content = "You are a concise English-to-Chinese dictionary. For the given English word or phrase, return ONLY a dictionary entry in this exact format: `/IPA/ <part-of-speech>. <chinese meaning 1>；<chinese meaning 2>` — start with the British IPA phonetic transcription enclosed in forward slashes (e.g. /ˈdɪkʃənri/), then 1-3 Chinese meanings separated by full-width semicolons ；. Part of speech abbreviations: n./v./adj./adv./prep./conj./phrase. For multi-word phrases, omit the IPA. No extra text, no explanation, no quotes."
      },
      {
        role = "user",
        content = word
      }
    }
  })

  hs.http.asyncPost(
    OPENAI_API_URL,
    requestBody,
    {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. OPENAI_API_KEY
    },
    function(status, body, headers)
      if status == 200 then
        local response = hs.json.decode(body)
        if response and response.choices and response.choices[1] and response.choices[1].message then
          local meaning = response.choices[1].message.content
          local trimmed = meaning:gsub("^%s+", ""):gsub("%s+$", "")

          hs.alert.show(word .. "\n" .. trimmed, {
            textSize = 20,
            fadeInDuration = 0.1,
            fadeOutDuration = 3,
            radius = 8
          })

          speakText(word)

          if not appendToDailyNote(word, trimmed) then
            hs.alert.show("⚠️ Could not write to daily note", 2)
          end
        else
          hs.alert.show("Error: Invalid response from ChatGPT", 3)
        end
      else
        local errorMsg = "Dictionary lookup failed"
        if body then
          local errorData = hs.json.decode(body)
          if errorData and errorData.error and errorData.error.message then
            errorMsg = "Error: " .. errorData.error.message
          end
        end
        hs.alert.show(errorMsg, 3)
        print("API Error - Status:", status, "Body:", body)
      end
    end
  )
end

-- Capture selected text, then run the dictionary flow.
-- Cmd+Q is macOS's quit gesture, so synthesizing Cmd+C while Hyper+Q is still
-- physically held races with the OS's hold-to-quit handling and often fails to
-- reach the focused app (unlike Hyper+S, where Cmd+S has no such gesture).
-- Strategy: read the selection via the accessibility API first (no keystroke
-- needed); if unavailable, defer Cmd+C by 120ms so the user releases Hyper+Q
-- before the synthetic keystroke fires.
local function dictionaryLookup()
  local elem = hs.uielement.focusedElement()
  if elem then
    local ok, sel = pcall(function() return elem:selectedText() end)
    if ok and sel and sel ~= "" then
      runDictionaryLookup(sel)
      return
    end
  end

  local beforeCount = hs.pasteboard.changeCount()
  hs.timer.doAfter(0.12, function()
    hs.eventtap.keyStroke({"cmd"}, "c")
    hs.timer.doAfter(0.15, function()
      if hs.pasteboard.changeCount() == beforeCount then
        hs.alert.show("No text selected", 2)
        return
      end
      local word = hs.pasteboard.getContents() or ""
      runDictionaryLookup(word)
    end)
  end)
end

-- 快捷键：Hyper + W 查词：显示中文释义、朗读、写入 Obsidian 日记
hs.hotkey.bind(hyper, "W", dictionaryLookup)

-- Grayscale (Color Filters) toggle via a small helper that calls the private
-- UniversalAccess framework — the only way to flip grayscale live.
local grayscaleDir = os.getenv("HOME") .. "/.hammerspoon/tools"
local grayscaleBin = grayscaleDir .. "/toggle-grayscale"

-- Build the helper if it's missing (e.g. after a fresh checkout; binary is gitignored).
if not hs.fs.attributes(grayscaleBin) then
  hs.execute(string.format(
    "clang -framework UniversalAccess -F/System/Library/PrivateFrameworks %q -o %q 2>&1",
    grayscaleDir .. "/toggle-grayscale.m", grayscaleBin))
end

local function toggleGrayscale()
  if not hs.fs.attributes(grayscaleBin) then
    hs.alert.show("toggle-grayscale helper not built", 3)
    return
  end
  hs.task.new(grayscaleBin, function(exitCode, stdOut, stdErr)
    if exitCode == 0 then
      local state = (stdOut or ""):gsub("%s+", "")
      hs.alert.show(state == "on" and "◐ 黑白" or "◑ 彩色", {
        textSize = 18,
        fadeInDuration = 0.05,
        fadeOutDuration = 0.6,
        radius = 6
      })
    else
      hs.alert.show("Failed to toggle grayscale", 2)
      print("toggle-grayscale error:", stdErr)
    end
  end):start()
end

-- 快捷键：Hyper + C 切换黑白/彩色显示
hs.hotkey.bind(hyper, "C", toggleGrayscale)

hs.hotkey.bind(hyper, "R", function()
  hs.reload()
end)

-- Function to request authorization for Reminders
local function requestRemindersAuthorization()
  -- Simple script to trigger authorization
  local authScript = [[
    tell application "System Events"
      set remindersList to name of every process
      if "Reminders" is not in remindersList then
        tell application "Reminders" to launch
        delay 0.5
      end if
    end tell

    tell application "Reminders"
      try
        count of reminders
        return "authorized"
      on error
        return "not authorized"
      end try
    end tell
  ]]

  local ok, result = hs.osascript.applescript(authScript)
  return ok
end

-- Use Shortcuts to create reminder
local function createReminderViaShortcut(text)
  -- Method 1: Use shortcuts URL scheme
  local encodedText = hs.http.encodeForQuery(text)
  local shortcutURL = "shortcuts://run-shortcut?name=Add%20to%20Reminders&input=text&text=" .. encodedText

  -- Try to open the shortcut (requires a shortcut named "Add to Reminders")
  hs.urlevent.openURL(shortcutURL)
end

-- Alternative: Use osascript with shortcuts CLI
local function createReminderViaScript(text)
  -- Escape special characters for shell
  local escapedText = text:gsub('"', '\\"'):gsub("'", "'\\''"):gsub("\n", " ")

  -- Use osascript to tell Reminders app to create a new reminder
  local command = string.format([[
    osascript -e 'tell application "Reminders"
      set myList to default list
      tell myList
        make new reminder with properties {name:"%s"}
      end tell
    end tell'
  ]], escapedText)

  -- Execute the command
  local output, status = hs.execute(command)

  return status
end

-- Alternative: Use shortcuts CLI if available
local function createReminderViaShortcutsCLI(text)
  -- Check if shortcuts CLI is available
  local checkCmd = "which shortcuts"
  local shortcutsPath = hs.execute(checkCmd)

  if shortcutsPath and shortcutsPath ~= "" then
    -- Escape text for shell
    local escapedText = text:gsub('"', '\\"'):gsub("'", "'\\''")

    -- Run shortcuts command
    local cmd = string.format('echo "%s" | shortcuts run "Add to Reminders" -i -', escapedText)
    local output, status = hs.execute(cmd)

    return status
  else
    return false
  end
end

-- Function to create a reminder from selected text
local function createReminderFromSelection()
  -- Get the currently selected text
  local elem = hs.uielement.focusedElement()
  local selectedText = nil

  if elem then
    selectedText = elem:selectedText()
  end

  -- If no text is selected, try to get from clipboard
  if not selectedText or selectedText == "" then
    selectedText = hs.pasteboard.getContents()
  end

  if not selectedText or selectedText == "" then
    hs.alert.show("No text selected or in clipboard", 2)
    return
  end

  -- Try osascript method (most reliable, but needs authorization)
  local success = createReminderViaScript(selectedText)

  if success then
    -- Show success notification
    hs.alert.show("✓ Added to Reminders", {
      textSize = 14,
      fadeInDuration = 0.25,
      fadeOutDuration = 1
    })

    -- Play a sound for feedback
    hs.sound.getByName("Glass"):play()
  else
    -- If failed, show instructions
    hs.alert.show("⚠️ Please authorize Hammerspoon in System Settings", 5)

    -- Show dialog with instructions
    hs.dialog.blockAlert(
      "Authorization Required",
      "To add reminders automatically, please:\n\n" ..
      "1. Open System Settings\n" ..
      "2. Go to Privacy & Security → Automation\n" ..
      "3. Find Hammerspoon\n" ..
      "4. Enable 'Reminders'\n\n" ..
      "Or use Hyper+M to manually enter reminders.",
      "OK"
    )
  end
end

-- Alternative function using AppleScript (requires authorization)
local function createReminderViaAppleScript()
  -- First check/request authorization
  if not requestRemindersAuthorization() then
    -- Show instructions for manual authorization
    hs.alert.show("⚠️ Please grant permission in System Settings", 5)

    -- Open System Settings to Privacy & Security
    hs.execute("open x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")

    return
  end

  -- Get the currently selected text
  local elem = hs.uielement.focusedElement()
  local selectedText = nil

  if elem then
    selectedText = elem:selectedText()
  end

  -- If no text is selected, try to get from clipboard
  if not selectedText or selectedText == "" then
    selectedText = hs.pasteboard.getContents()
  end

  if not selectedText or selectedText == "" then
    hs.alert.show("No text selected or in clipboard", 2)
    return
  end

  -- Clean up the text for AppleScript
  local cleanedText = selectedText:gsub('"', '\\"'):gsub('\n', ' ')

  -- Simplified AppleScript
  local script = string.format([[
    tell application "Reminders"
      set newReminder to make new reminder with properties {name:"%s"}
      return "Success"
    end tell
  ]], cleanedText)

  -- Execute the AppleScript
  local ok, result, raw = hs.osascript.applescript(script)

  if ok then
    -- Success notification
    hs.alert.show("✓ Added to Reminders", {
      textSize = 14,
      fadeInDuration = 0.25,
      fadeOutDuration = 1
    })

    -- Also play a sound for feedback
    hs.sound.getByName("Glass"):play()
  else
    -- Error notification
    local errorMsg = "Failed: " .. tostring(result)
    hs.alert.show(errorMsg, 5)
  end
end

-- 快捷键：Hyper + I 创建 Reminder (I for Inbox)
hs.hotkey.bind(hyper, "I", createReminderFromSelection)

-- Function to create a reminder with dialog for editing
local function createReminderWithDialog()
  -- Get the currently selected text as default
  local elem = hs.uielement.focusedElement()
  local selectedText = ""

  if elem then
    selectedText = elem:selectedText() or ""
  end

  -- If no text is selected, try to get from clipboard
  if selectedText == "" then
    selectedText = hs.pasteboard.getContents() or ""
  end

  -- Show dialog for user to edit/confirm the reminder text
  local button, reminderText = hs.dialog.textPrompt(
    "Add to Reminders",
    "Enter reminder text:",
    selectedText,
    "Add",
    "Cancel"
  )

  if button == "Add" and reminderText ~= "" then
    -- Try osascript method
    local success = createReminderViaScript(reminderText)

    if success then
      -- Success notification
      local displayText = reminderText
      if #displayText > 50 then
        displayText = displayText:sub(1, 50) .. "..."
      end
      hs.alert.show("✓ Added: " .. displayText, {
        textSize = 14,
        fadeInDuration = 0.25,
        fadeOutDuration = 1.5
      })

      -- Play a sound for feedback
      hs.sound.getByName("Glass"):play()
    else
      hs.alert.show("Failed to add reminder - check authorization", 3)
    end
  end
end

-- 快捷键：Hyper + M 创建 Reminder with dialog
hs.hotkey.bind(hyper, "M", createReminderWithDialog)

-- 快捷键：Hyper + N 创建 Reminder via AppleScript (需要授权)
hs.hotkey.bind(hyper, "N", createReminderViaAppleScript)

-- External Display Brightness Control using m1ddc

-- Cache for current brightness (since m1ddc get might not work reliably)
local currentBrightness = 70  -- default starting brightness

-- Function to adjust external display brightness
local function adjustExternalDisplayBrightness(delta)
  -- Use m1ddc (best for Apple Silicon Macs)
  local m1ddcPath = "/opt/homebrew/bin/m1ddc"
  print("Adjusting brightness by", delta)

  if hs.fs.attributes(m1ddcPath) then
    -- Calculate new brightness based on cached value
    local new = math.max(0, math.min(100, currentBrightness + delta))

    -- Set new brightness using m1ddc
    local setCmd = string.format("%s set luminance %d 2>&1", m1ddcPath, new)

    -- Use os.execute for more reliable execution
    local success = os.execute(setCmd)

    -- Check if command was successful (os.execute returns true/nil/0 depending on Lua version)
    if success == true or success == 0 then
      -- Update cached value
      currentBrightness = new

      -- Show notification with brightness level and visual bar
      local barLength = 20
      local filledBars = math.floor(new / 100 * barLength)
      local emptyBars = barLength - filledBars
      local bar = string.rep("█", filledBars) .. string.rep("░", emptyBars)

      hs.alert.show(string.format("Display: %d%%\n%s", new, bar), {
        textSize = 18,
        fadeInDuration = 0.05,
        fadeOutDuration = 0.5,
        fillColor = {white = 0, alpha = 0.75},
        strokeColor = {white = 1, alpha = 0},
        textColor = {white = 1, alpha = 1},
        strokeWidth = 0,
        radius = 5
      })

      -- Try to sync with actual value
      local getOutput = hs.execute(m1ddcPath .. " get luminance")
      if getOutput then
        local actual = tonumber(getOutput:match("(%d+)"))
        if actual and actual > 0 then
          currentBrightness = actual
        end
      end
    else
      -- Fallback: try using hs.task for async execution
      hs.task.new(m1ddcPath, function(exitCode, stdOut, stdErr)
        if exitCode == 0 then
          currentBrightness = new

          local barLength = 20
          local filledBars = math.floor(new / 100 * barLength)
          local emptyBars = barLength - filledBars
          local bar = string.rep("█", filledBars) .. string.rep("░", emptyBars)

          hs.alert.show(string.format("Display: %d%%\n%s", new, bar), {
            textSize = 18,
            fadeInDuration = 0.05,
            fadeOutDuration = 0.5,
            fillColor = {white = 0, alpha = 0.75},
            strokeColor = {white = 1, alpha = 0},
            textColor = {white = 1, alpha = 1},
            strokeWidth = 0,
            radius = 5
          })
        else
          print("m1ddc error:", stdErr)
          hs.alert.show("Failed to adjust brightness", 2)
        end
      end, {"set", "luminance", tostring(new)}):start()
    end
  else
    -- m1ddc not found
    hs.alert.show("m1ddc not installed! Run: brew install m1ddc", 3)
  end
end

-- Try to get initial brightness value on load
local m1ddcPath = "/opt/homebrew/bin/m1ddc"
if hs.fs.attributes(m1ddcPath) then
  local output = hs.execute(m1ddcPath .. " get luminance")
  if output then
    local initial = tonumber(output:match("(%d+)"))
    if initial and initial > 0 then
      currentBrightness = initial
    end
  end
end

-- Brightness adjustment step (percentage)
local brightnessStep = 5

-- 快捷键：Hyper + 1 调暗外接显示器
hs.hotkey.bind(hyper, "1", function()
  adjustExternalDisplayBrightness(-brightnessStep)
end)

-- 快捷键：Hyper + 2 调亮外接显示器
hs.hotkey.bind(hyper, "2", function()
  adjustExternalDisplayBrightness(brightnessStep)
end)