-- Load configuration
local config = require("config")

-- ChatGPT API configuration
local OPENAI_API_KEY = config.OPENAI_API_KEY
local OPENAI_API_URL = "https://api.openai.com/v1/chat/completions"

-- Function to create a minimal input dialog using webview
local function createInputDialog(callback)
  local webview = hs.webview.new({x=0, y=0, w=500, h=300})

  -- Store webview reference for cleanup
  local webviewRef = webview

  -- Center the window on screen
  local screen = hs.screen.mainScreen()
  local screenFrame = screen:frame()
  local windowFrame = webview:frame()
  windowFrame.x = screenFrame.x + (screenFrame.w - windowFrame.w) / 2
  windowFrame.y = screenFrame.y + (screenFrame.h - windowFrame.h) / 2
  webview:frame(windowFrame)

  local html = [[
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        * {
          margin: 0;
          padding: 0;
          box-sizing: border-box;
        }
        body {
          font-family: -apple-system, BlinkMacSystemFont, sans-serif;
          background: transparent;
          height: 100vh;
          display: flex;
          padding: 10px;
        }
        #inputArea {
          width: 100%;
          height: 100%;
          padding: 20px;
          font-size: 18px;
          border: none;
          resize: none;
          outline: none;
          line-height: 1.6;
          background: white;
          border-radius: 12px;
          transition: all 0.3s ease;
          box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
        }
        #inputArea:focus {
          outline: none;
          box-shadow: 0 6px 20px rgba(0, 0, 0, 0.15);
        }
        #inputArea.translating {
          background: #f8f8f8;
          color: #666;
        }
        #inputArea.translated {
          background: #f0f9ff;
          color: #0066cc;
        }
        ::placeholder {
          color: #999;
          font-size: 16px;
        }
        .loading {
          animation: pulse 1.5s infinite;
        }
        @keyframes pulse {
          0% { opacity: 1; }
          50% { opacity: 0.5; }
          100% { opacity: 1; }
        }
      </style>
    </head>
    <body>
      <textarea id="inputArea" placeholder="Type or paste text here..." autofocus></textarea>
      <script>
        const textarea = document.getElementById('inputArea');
        let isTranslating = false;

        // Auto focus
        textarea.focus();

        // Handle keyboard shortcuts
        textarea.addEventListener('keydown', function(e) {
          // Enter to translate (only if not already translating)
          if (e.key === 'Enter' && !e.shiftKey && !isTranslating) {
            e.preventDefault();
            const text = textarea.value.trim();
            if (text) {
              isTranslating = true;
              // Disable input and show translating state
              textarea.disabled = true;
              textarea.classList.add('translating', 'loading');
              textarea.placeholder = 'Translating...';

              // Use window title to pass data
              document.title = 'TRANSLATE:' + text;
            }
          }
          // Escape to close
          if (e.key === 'Escape') {
            e.preventDefault();
            document.title = 'CANCEL';
          }
        });

        // Function to show translation result
        window.showTranslation = function(translatedText) {
          textarea.value = translatedText;
          textarea.classList.remove('translating', 'loading');
          textarea.classList.add('translated');
          textarea.disabled = false;
          textarea.readOnly = true;

          // Select all text for easy copying
          textarea.select();

          // Update placeholder
          textarea.placeholder = 'Press Escape to close';
        };

        // Function to show error
        window.showError = function(errorMsg) {
          textarea.value = 'Error: ' + errorMsg;
          textarea.classList.remove('translating', 'loading');
          textarea.disabled = false;
          isTranslating = false;
        };

        // Clear placeholder when typing
        textarea.addEventListener('input', function() {
          if (this.value && !isTranslating) {
            this.placeholder = '';
          } else if (!this.value && !isTranslating) {
            this.placeholder = 'Type or paste text here...';
          }
        });
      </script>
    </body>
    </html>
  ]]

  webview:html(html)
  webview:allowTextEntry(true)
  webview:windowStyle({"borderless", "nonactivating"})  -- 无标题栏，最简洁
  webview:level(hs.drawing.windowLevels.modalPanel)

  -- Enable transparency for rounded corners
  webview:transparent(true)

  -- Remove window shadow since we have our own CSS shadow
  webview:shadow(false)

  -- Store original text for translation
  local originalText = nil

  -- Watch for title changes as communication mechanism
  local titleWatcher
  titleWatcher = hs.timer.new(0.1, function()
    local title = webview:title()
    if title and title:match("^TRANSLATE:") then
      originalText = title:match("^TRANSLATE:(.+)")
      if originalText then
        -- Don't close the webview, just stop watching for translate command
        webview:evaluateJavaScript("document.title = ''")

        -- Call the callback to perform translation
        callback(originalText, webview)
      end
    elseif title == "CANCEL" then
      titleWatcher:stop()
      webviewRef:delete()
    end
  end)
  titleWatcher:start()

  webview:show()

  -- Return webview reference for updating with results
  return webview
end

-- Function to translate and optimize text using ChatGPT
local function translateToEnglish()
  createInputDialog(function(inputText, webview)
    if not inputText or inputText == "" then
      return
    end

    -- Prepare the request body
    local requestBody = hs.json.encode({
      model = "gpt-5-nano",
      messages = {
        {
          role = "system",
          content = "You are a professional translator and language expert. Translate the following text to English, and optimize its grammar and expression to make it more natural and professional. Only return the translated and optimized English text without any explanation."
        },
        {
          role = "user",
          content = inputText
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

            -- Update the webview with translation result
            webview:evaluateJavaScript(string.format("showTranslation('%s')",
              translatedText:gsub("'", "\\'"):gsub("\n", "\\n"):gsub("\r", "\\r")))

            -- Small notification that it's copied
            hs.alert.show("✓ Copied to clipboard", {
              textSize = 12,
              fadeInDuration = 0.1,
              fadeOutDuration = 0.5
            })
          else
            webview:evaluateJavaScript("showError('Invalid response from ChatGPT')")
          end
        else
          local errorMsg = "API request failed"
          if body then
            local errorData = hs.json.decode(body)
            if errorData and errorData.error and errorData.error.message then
              errorMsg = errorData.error.message
            end
          end
          webview:evaluateJavaScript(string.format("showError('%s')",
            errorMsg:gsub("'", "\\'"):gsub("\n", "\\n")))
          print("API Error - Status:", status, "Body:", body)
        end
      end
    )
  end)
end

-- Function to translate selected text using ChatGPT
local function translateSelectedText()
  -- Get the currently selected text
  local elem = hs.uielement.focusedElement()
  local selectedText = nil
  local hasSelection = false

  if elem then
    selectedText = elem:selectedText()
    if selectedText and selectedText ~= "" then
      hasSelection = true
    end
  end

  -- If no text is selected, try to get from clipboard
  if not selectedText or selectedText == "" then
    selectedText = hs.pasteboard.getContents()
    hasSelection = false
  end

  if not selectedText or selectedText == "" then
    hs.alert.show("No text selected or in clipboard", 2)
    return
  end

  -- Prepare the request body
  local requestBody = hs.json.encode({
    model = "gpt-5-nano",
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
            hs.alert.show("✓ Translation copied to clipboard", {
              textSize = 14,
              fadeInDuration = 0.25,
              fadeOutDuration = 1
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
-- 快捷键：Cmd + Option + T 翻译文本到英文（输入对话框）
hs.hotkey.bind(hyper, "T", translateToEnglish)

-- 快捷键：Cmd + Option + S 翻译选中文本或剪贴板内容
hs.hotkey.bind(hyper, "S", translateSelectedText)

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