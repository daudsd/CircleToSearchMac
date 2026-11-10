# Circle Search for Mac

A menu-bar app that brings Android's Circle to Search to macOS. Press **⌥ Space**, circle anything on screen, then:

| Button | What it does |
|---|---|
| **Copy text** | Reads text in the circled area on-device (Apple Vision). Select part of it with ⌘C, or press Return to copy everything and close. |
| **Translate** | Translates that text on-device with Apple Translation. It tries the Apple Intelligence models first (macOS 26.4+, `highFidelity` strategy), which cover more languages, such as Norwegian. If Apple can't handle a language, Claude translates it instead. Pick the target language from the dropdown. |
| **Lens** | Opens the circled image in Google Lens in your default browser. |
| **Ask Claude** | Asks Claude about the image, and you can ask follow-ups. Needs an Anthropic API key. |
| 🖼 | Copies the circled area as an image. |

Esc or right-click closes the overlay. Pressing the shortcut again also closes it.

## Requirements

- macOS 15 or later
- Xcode or the Command Line Tools (`xcode-select --install`)

## Build and install

```bash
cd ~/Documents/CircleSearch
chmod +x build.sh
./build.sh --install
```

On first launch, macOS asks for **Screen Recording** permission. Allow it, then quit and reopen Circle Search from /Applications. A dashed circle icon appears in the menu bar.

Then open **Settings…** from the menu bar icon to:
- change the shortcut if ⌥ Space clashes with another app (Raycast and ChatGPT both like it)
- paste your Anthropic API key (it's stored in the Keychain)
- choose the translation language
- turn on Launch at login

## Notes

- **After every rebuild**, macOS treats the app as new because it's ad-hoc signed. `--install` resets the old Screen Recording entry for you; just allow it again when asked.
- **Lens** works by uploading through Google's normal web upload form in your browser. Google can change that form at any time. If it breaks, use 🖼 to copy the image and paste it into lens.google.com.
- **Claude** uses `claude-haiku-5-5` by default because it's fast and cheap. You can switch to `claude-sonnet-5-5` in Settings for harder questions.
- Text recognition and translation run entirely on your Mac. Only Lens and Claude send the image anywhere.

## Code map

| File | Purpose |
|---|---|
| `AppDelegate.swift` | Menu bar item, shortcut, Settings window |
| `HotKey.swift` | Global shortcut (Carbon `RegisterEventHotKey`) |
| `CaptureController.swift` / `ScreenCapturer.swift` | Freezes every display with ScreenCaptureKit |
| `Overlay.swift` | Full-screen overlay, lasso drawing, cropping, panel placement |
| `Panel.swift` | SwiftUI action panel: OCR text, translation, Claude chat |
| `Services.swift` | Vision OCR, Google Lens upload, Anthropic Messages API |
| `SettingsView.swift` / `Prefs.swift` | Settings, UserDefaults keys, Keychain |
