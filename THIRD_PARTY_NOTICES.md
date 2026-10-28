# Third-party notices

BotPeek bundles no third-party code libraries or artwork. All avatar shapes,
the app icon and the menu-bar glyph are original drawings made for BotPeek.

## grok-bot-mcp

BotPeek's Accessibility integration (`Sources/BotPeek/Grok/GrokAccessibilityDriver.swift`
and `Sources/BotPeekCore/Grok/TranscriptParser.swift`) adapts techniques from
grok-bot-mcp (https://github.com/rthomas24/grok-bot-mcp, commit a43e14c): finding
the "Bots" sidebar, the "Conversation transcript" container, message groups
labelled "<sender> <time>", the "Dismiss question" button next to choices, the
"Prompt" text area, enabling `AXManualAccessibility`, and pasting replies while
preserving every clipboard item. The code was rewritten in Swift; this notice is
included because the approach and structure derive from that project.

    MIT License
    
    Copyright (c) 2026 Ryan Thomas
    
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    
    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.
    
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

## Other projects studied (no code used)

- grokbot-widget (https://github.com/imranbarbhuiya/grokbot-widget, MIT): documented the
  location of uploaded avatars (`roster-avatars/<key>` referenced by `avatarPhoto`) and the
  official BDK extension. No code was copied.
- djui/grokbot (https://github.com/djui/grokbot): documented the roster cache location and the
  `awaitingUserResponse` field. That repository has no license, so none of its code or
  artwork was copied; BotPeek's implementation and avatar drawings are independent.

## Trademarks

Grok, Grok Bot, xAI, SpaceXAI, Cursor and Anysphere are trademarks of their respective
owners. BotPeek is an independent community project and is not affiliated with, endorsed by
or sponsored by them.
