# AGENTS.md — Blossome iOS App

## Project Overview

**Blossome** is a SwiftUI iOS app that transforms user text input into animated P5.js visualizations. Users write "碎片" (fragments) that are persisted locally, select an art effect, watch the text come alive in a WebView canvas, then export the animation as a video or LivePhoto to their photo library. An in-app portfolio lets users browse and replay all saved works.

**Stack:** Swift/SwiftUI + WKWebView + P5.js (JavaScript) + AVFoundation + Photos framework
**Minimum target:** iOS 26+ (uses `.glassEffect()` liquid glass API)
**Xcode version:** 26.1 (uses `PBXFileSystemSynchronizedRootGroup`, Xcode 16+ feature)
**No external dependencies** — no SPM packages, no CocoaPods

---

## Directory Structure

```
blossome/
├── blossome.xcodeproj/          Xcode project file
└── blossome/                    Main source directory (auto-synced by Xcode)
    ├── blossomeApp.swift         @main entry point
    ├── Fragment.swift            碎片 data model (Codable struct)
    ├── FragmentStore.swift       Singleton ObservableObject, local persistence for fragments
    ├── FragmentListView.swift    碎片 list (home page, swipe-to-delete)
    ├── ContentView.swift         碎片 full-text editor (art picker, recording controls)
    ├── P5WebView.swift           UIViewRepresentable WKWebView bridge
    ├── MediaSaver.swift          WebViewManager + MediaSaver + LivePhotoVideoWriter
    ├── PortfolioItem.swift       Portfolio data model (Codable struct)
    ├── PortfolioStore.swift      Singleton ObservableObject, local persistence for portfolio
    ├── PortfolioView.swift       2-column grid portfolio browser
    ├── PortfolioDetailView.swift Full-screen paging player (video + LivePhoto)
    ├── SaveSuccessOverlay.swift  Post-save success UI overlay
    ├── sketch.html               P5.js art: "音乐的诞生" (Birth of Music)
    ├── mcdonald.html             P5.js art: "麦门" (McDonald's Fries)
    ├── rainynight.html           P5.js art: "潮湿的雨夜" (Rainy Night)
    ├── Fonts/
    │   ├── LXGWWenKai-Light.ttf  Chinese handwriting font
    │   └── McDonald_s_Fries_Font.ttf
    ├── Assets.xcassets/          App icon (light + dark), accent color
    └── Info.plist                Photo library permission, font registration
```

---

## Architecture

The app follows a **SwiftUI + WebView hybrid** pattern with four distinct layers:

### 1. Fragment Layer (`FragmentListView.swift`, `ContentView.swift`)
- **`FragmentListView`** — default home page listing all 碎片 (fragments) sorted by last-edit time.
  - Left swipe to delete (short swipe reveals button, long swipe deletes with haptic).
  - Floating `+` button creates a new fragment.
  - Top-left: portfolio entrance; top-right: blank.
- **`ContentView`** — full-text editor for a single fragment.
  - Receives `fragmentID`, loads/saves content via `FragmentStore` with debounce.
  - Top-left: system back button; top-right: Art menu → `ArtEffect` picker.
  - `fullScreenCover` renders the selected art via `P5WebView`.
  - Bottom bar with liquid glass buttons: "保存为视频" (5/15/30s) and "LivePhoto".
  - `SaveSuccessOverlay` shown after successful save.

### 1b. Fragment Persistence (`Fragment.swift`, `FragmentStore.swift`)
- **`Fragment`** — `Identifiable, Codable` struct with `id`, `content`, `createdAt`, `updatedAt`.
- **`FragmentStore`** — singleton, persists to `Documents/Fragments/fragments.json`.
  - CRUD operations: `create()`, `update(id:content:)`, `delete(id:)`, `fragment(by:)`.
  - Auto-sorts by `updatedAt` descending.

### 2. WebView Bridge (`P5WebView.swift`)
`UIViewRepresentable` wrapping `WKWebView`.
- **JS → Swift message handlers:** `p5Ready`, `action`, `videoCallback`
- On `p5Ready`: calls `startArt(text, fontName)` via `evaluateJavaScript`
- On `videoCallback`: passes base64 video string to the `onVideoGenerated` closure
- Text is escaped for JS (backslashes, quotes, newlines) before injection.

### 3. Recording / Media Layer (`MediaSaver.swift`)
- **`WebViewManager: ObservableObject`** — wraps `evaluateJavaScript` calls:
  - `startRecording()` → triggers `startRecording()` in JS
  - `stopRecording()` → triggers `stopRecordingAndGetResult()` in JS
- **`MediaSaver`** — handles Photos library saving:
  - `saveVideo(base64String:)` — decodes base64 → `.mp4`, saves via `PHPhotoLibrary`
  - `saveLivePhoto(base64String:)` — full LivePhoto pipeline (see below)
- **`LivePhotoVideoWriter`** — injects `quickTimeMetadataContentIdentifier` into `.mov` via `AVAssetExportSession`

### 4. Portfolio Layer
- **`PortfolioStore`** — singleton, persists to `Documents/Portfolio/`, stores `portfolio.json` manifest.
- **`PortfolioView`** — `LazyVGrid` thumbnail browser with context menu for deletion.
- **`PortfolioDetailView`** — horizontal paging scroll view; video via `AVPlayerLayer`, LivePhoto via `PHLivePhotoView`.

---

## Data Flow

```
User types text
       ↓
Selects ArtEffect → fullScreenCover opens P5WebView
       ↓
P5.js canvas loads → sends "p5Ready" to Swift
       ↓
Swift calls startArt(text, fontName) → animation plays
       ↓
User taps save → WebViewManager.startRecording()
       ↓
After N seconds → WebViewManager.stopRecording()
       ↓
JS encodes canvas stream as base64 → videoCallback message
       ↓
MediaSaver decodes/transcodes/saves to Photos + PortfolioStore
       ↓
SaveSuccessOverlay shown
```

---

## Art Effects (`ArtEffect` enum)

| Enum case   | Display name (CN)  | HTML file        | Font                   | Description |
|-------------|-------------------|------------------|------------------------|-------------|
| `.sketch`   | 音乐的诞生         | `sketch.html`    | LXGWWenKai-Light       | Text characters ride animated sine-wave curves scrolling across a warm white background |
| `.mcdonald` | 麦门              | `mcdonald.html`  | McDonald_s_Fries_Font  | Animated McDonald's fries box launches words as physics particles with arc trajectories |
| `.rainynight`| 潮湿的雨夜        | `rainynight.html`| LXGWWenKai-Light       | Rain streaks progressively reveal sharp text through a blurred background on a blue canvas |

---

## JavaScript ↔ Swift Communication API

### Swift → JS (via `evaluateJavaScript`)
| Call | Purpose |
|------|---------|
| `startArt(text, fontName)` | Initialize the P5.js sketch with the user's text and chosen font |
| `startRecording()` | Begin `MediaRecorder` capture of the canvas stream |
| `stopRecordingAndGetResult()` | Stop recording; JS will post the result back via `videoCallback` |

### JS → Swift (via `webkit.messageHandlers.<name>.postMessage`)
| Handler | Payload | Purpose |
|---------|---------|---------|
| `p5Ready` | none | P5.js is initialized and ready to receive `startArt` |
| `action` | none | Canvas was tapped; Swift shows action sheet |
| `videoCallback` | base64 string | Encoded video data (WebM or MP4) ready for saving |

---

## LivePhoto Creation Pipeline

LivePhotos require paired JPEG + MOV files with matching `assetIdentifier` in metadata:

1. Decode base64 → raw video file (often WebM from browser)
2. Transcode to `.mov` via `AVAssetExportSession` (WebM not supported by AVFoundation)
3. Extract mid-point keyframe with `AVAssetImageGenerator` → JPEG
4. Inject Apple MakerNote metadata (key `"17"` = assetIdentifier UUID) into JPEG via `CGImageDestination`
5. Inject `AVMetadataIdentifier.quickTimeMetadataContentIdentifier` into `.mov` via `AVAssetExportSession` passthrough
6. Save paired resources with `PHAssetCreationRequest.addResource(.photo, ...)` + `.addResource(.pairedVideo, ...)`

> **PortfolioStore** also saves LivePhotos locally (independent of Photos library) using the same metadata pipeline so `PHLivePhotoView` can display them from the app bundle.

---

## Adding a New Art Effect

1. Create a new `.html` file in `blossome/` with P5.js sketch. Required JS interface:
   - Must call `window.webkit.messageHandlers.p5Ready.postMessage({})` when ready
   - Must implement `startArt(text, fontName)` global function
   - Must implement `startRecording()` and `stopRecordingAndGetResult()` global functions
   - `stopRecordingAndGetResult()` must post base64 video to `window.webkit.messageHandlers.videoCallback.postMessage(base64String)`

2. Add the case to `ArtEffect` enum in `ContentView.swift`:
   ```swift
   case myEffect = "myEffect"
   var displayName: String { /* Chinese name */ }
   var htmlFile: String { "myEffect.html" }
   var fontName: String { /* PostScript font name */ }
   ```

3. If using a new font, add the `.ttf` to `blossome/Fonts/`, register it in `Info.plist` under `UIAppFonts`.

---

## Adding a New Font

1. Copy the `.ttf` file into `blossome/Fonts/`.
2. Add the filename to `UIAppFonts` array in `Info.plist`.
3. Use the **PostScript name** (not file name) when calling `startArt`. Find it with Font Book → "PostScript Name".

---

## Build and Run

```bash
# Open in Xcode
open blossome.xcodeproj
```

- Build with Xcode 16+ (project uses `PBXFileSystemSynchronizedRootGroup`).
- Requires Xcode 26.1+ to use `.glassEffect()` API (iOS 26 SDK).
- Deploy to a physical device or iOS 26 simulator.
- Photo library permission is required at runtime for saving; granted via `NSPhotoLibraryAddUsageDescription` in `Info.plist`.

---

## Key Conventions

- **Chinese UI strings** — all user-visible text is in Chinese (Simplified). Keep this convention for new UI text.
- **Singleton stores** — `PortfolioStore.shared` and `FragmentStore.shared` are created once in `blossomeApp` and injected as `@EnvironmentObject`.
- **No SPM/external dependencies** — keep the project dependency-free.
- **Liquid glass buttons** — use the iOS 26 native `.buttonStyle(.glass)` for primary action buttons.
- **File auto-sync** — Xcode auto-discovers files added to the `blossome/` folder via `PBXFileSystemSynchronizedRootGroup`. No need to manually add sources to `project.pbxproj`.
- **Local portfolio storage** — `Documents/Portfolio/` layout: `<id>.mp4`, `<id>_thumb.jpg`, `<id>_live.jpg`, `<id>_live.mov`, `portfolio.json`.
- **Local fragment storage** — `Documents/Fragments/fragments.json` stores all fragment data.
