-- Alternative simple input dialog function
-- This creates a minimal, clean input dialog

local function createSimpleInputDialog(callback)
  local webview = hs.webview.new({x=0, y=0, w=500, h=300})

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
          padding: 0;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
          background: #f0f0f0;
          display: flex;
          align-items: center;
          justify-content: center;
          height: 100vh;
        }
        .container {
          width: 100%;
          height: 100%;
          display: flex;
          flex-direction: column;
        }
        #inputArea {
          flex: 1;
          width: 100%;
          padding: 20px;
          font-size: 18px;
          border: none;
          resize: none;
          outline: none;
          background: white;
          line-height: 1.6;
        }
        #inputArea:focus {
          outline: none;
        }
        ::placeholder {
          color: #aaa;
          font-size: 16px;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <textarea id="inputArea" placeholder="Type or paste text here..." autofocus></textarea>
      </div>
      <script>
        const textarea = document.getElementById('inputArea');

        // Auto focus
        textarea.focus();

        // Select all text on focus
        textarea.select();

        // Handle keyboard shortcuts
        textarea.addEventListener('keydown', function(e) {
          // Cmd+Enter to translate
          if (e.metaKey && e.key === 'Enter') {
            e.preventDefault();
            const text = textarea.value.trim();
            if (text) {
              window.location.href = 'hammerspoon://translate?text=' + encodeURIComponent(text);
            }
          }
          // Escape to cancel
          if (e.key === 'Escape') {
            e.preventDefault();
            window.location.href = 'hammerspoon://cancel';
          }
        });

        // Show hint
        setTimeout(() => {
          if (textarea.value === '') {
            textarea.placeholder = 'Type or paste text here...';
          }
        }, 1000);
      </script>
    </body>
    </html>
  ]]

  webview:html(html)
  webview:allowTextEntry(true)
  webview:windowStyle({"borderless", "nonactivating"})  -- No title bar, minimal chrome
  webview:level(hs.drawing.windowLevels.modalPanel)

  -- URL handler
  webview:urlCallback(function(action, webview, url)
    if url:match("^hammerspoon://translate") then
      local text = url:match("text=(.+)")
      if text then
        text = hs.http.decodeForURL(text)
        webview:delete()
        callback(text)
      end
      return true
    elseif url:match("^hammerspoon://cancel") then
      webview:delete()
      return true
    end
    return false
  end)

  webview:show()
end

return createSimpleInputDialog