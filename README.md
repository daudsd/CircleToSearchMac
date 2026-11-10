# Circle to Search for Mac

Android's **Circle to Search**, for macOS. Press a shortcut, circle anything on your screen, and then copy its text, translate it, look it up with Google Lens, or ask Claude about it.

It's a small native menu-bar app written in Swift with AppKit and SwiftUI. There's no Electron and nothing else to install.

## Features

- **Circle anything.** The shortcut (⌥ Space by default) freezes every display. Draw around anything with a glowing lasso, and an action panel appears next to it.
- **Copy text.** Text in the circled area is read on your Mac with Apple Vision. You can select part of it with ⌘C, or press Return to copy everything and close.
- **Translate.**
  - Translation happens on your Mac with Apple's Translation framework. It prefers the **Apple Intelligence** models (macOS 26.4+), which cover extra languages such as **Norwegian Bokmål**.
  - The app works out the source language itself with Apple's NaturalLanguage framework.
  - If Apple can't handle a language, **Claude** translates it instead.
- **Google Lens.** Opens the circled image in Google Lens in your default browser.
- **Ask Claude.** Ask what's in the image, then keep asking follow-up questions in the same panel.
- **Copy image.** Puts the circled area on the clipboard as an image.
- **Multi-display**, **Launch at login**, and a choice of shortcut.

## Requirements

- macOS 15 or later. Apple Intelligence translation needs macOS 26.4+ with Apple Intelligence turned on.
- Xcode or the Command Line Tools (`xcode-select --install`)
- Optional: an [Anthropic API key](https://console.anthropic.com/settings/keys) for Ask Claude and the Claude translation fallback

## Install

```bash
git clone git@github.com:daudsd/CircleToSearchMac.git
cd CircleToSearchMac
./build.sh --install
```

This builds `Circle Search.app`, copies it to `/Applications` and launches it. A dashed circle icon appears in the menu bar.

On first launch, macOS asks for **Screen Recording** permission. Allow it in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen the app.

Run `./build.sh` without `--install` to build into `build/` only.

## Usage

| Action | How |
|---|---|
| Start | ⌥ Space, or the menu-bar icon → Circle to Search |
| Select | Click and drag around anything. Dragging again replaces the selection. |
| Copy all text | **Copy text**, then Return |
| Translate | **Translate**, then pick the target language from the dropdown |
| Visual search | **Lens** or **Ask Claude** |
| Close | Esc, ✕, right-click, or press the shortcut again |

A plain click never closes the overlay, so you can click into the panel and select text freely.

## Settings

Open **Settings…** from the menu-bar icon to:

- choose the shortcut: ⌥ Space, ⌥⇧ Space, ⌘⇧2 or ⌃⌥S. ⌥ Space clashes with Raycast and ChatGPT.
- pick the default translation language. Languages marked **· Claude** aren't available from Apple on your Mac.
- add your Anthropic API key. It's stored in the macOS Keychain, never in the code.
- choose the Claude model (default `claude-haiku-5-5`, which is fast and cheap) and the first question it's asked
- turn on Launch at login

## Privacy

| Feature | Where it runs |
|---|---|
| Screen capture, text recognition | On your Mac |
| Translation (Apple) | On your Mac |
| Translation (Claude fallback) | Sends the recognised text to the Anthropic API |
| Ask Claude | Sends the circled image to the Anthropic API |
| Lens | Uploads the circled image to Google Lens from your browser |

Nothing leaves your Mac unless you press Lens, Ask Claude, or translate a language that Apple doesn't support.

## Troubleshooting

**Screen Recording keeps asking after a rebuild.** The app is ad-hoc signed, so macOS treats every build as a new app. `./build.sh --install` resets the old entry for you, so just allow it again.

**Shortcut does nothing.** Another app probably uses it. You'll get an alert on launch. Pick a different shortcut in Settings.

**Translation says a language isn't supported.** Run the check script to see exactly what macOS offers on your Mac:

```bash
swift Tools/translation-check.swift
```

It prints whether Apple Intelligence is on, which languages each Apple model supports, and the result of a test Norwegian → English translation. To translate languages Apple doesn't support, add an API key so Claude can handle them.

**Lens shows an error page.** Lens works by uploading through Google's normal web form, which Google can change at any time. Use the copy-image button instead and paste the image into [lens.google.com](https://lens.google.com).

## How it works

```
⌥ Space ─► HotKeyManager (Carbon)
        ─► CaptureController ─► ScreenCaptureKit screenshot of each display
        ─► OverlayWindow per display (frozen image + lasso)
        ─► crop ─► ActionPanel (SwiftUI)
                    ├─ Vision           text recognition
                    ├─ Translation      Apple Intelligence / standard models
                    ├─ Anthropic API    Ask Claude + translation fallback
                    └─ Google Lens      browser upload
```

| File | Purpose |
|---|---|
| `AppDelegate.swift` | Menu-bar item, shortcut registration, Settings window |
| `HotKey.swift` | Global shortcut via Carbon `RegisterEventHotKey`, so no Accessibility permission is needed |
| `CaptureController.swift`, `ScreenCapturer.swift` | Freezes every display with ScreenCaptureKit |
| `Overlay.swift` | Full-screen overlay, lasso drawing, cropping, panel placement |
| `Panel.swift` | SwiftUI action panel: text, translation, Claude chat |
| `AppleTranslation.swift` | Language detection and Apple translation model selection |
| `Services.swift` | Vision text recognition, Google Lens upload, Anthropic Messages API |
| `SettingsView.swift`, `Prefs.swift` | Settings UI, UserDefaults keys, Keychain |
| `Tools/translation-check.swift` | Diagnostic script for Apple translation support |

## Credits

Inspired by Google's Circle to Search and [AKS-Labs/CircleToSearch](https://github.com/AKS-Labs/CircleToSearch) for Android.
