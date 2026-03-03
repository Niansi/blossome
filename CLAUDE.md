# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Blossome is a SwiftUI iOS app that transforms user text input into animated visualizations using P5.js. Users can type notes, select fonts, and export the generated animations as videos or LivePhotos to their photo library.

## Build and Run

This is an Xcode project. Open `blossome.xcodeproj` in Xcode to build and run on a physical device or iOS simulator.

## Architecture

The app follows a SwiftUI + WebView hybrid architecture:

- **SwiftUI Layer**: Handles the main UI, state management, and user interactions
- **WebView Layer**: P5.js running in WKWebView handles the animated visualization and canvas recording
- **Communication Layer**: JavaScript-Swift bidirectional communication via WKScriptMessageHandler

### Key Components

- `blossomeApp.swift`: Entry point with `@main` attribute
- `ContentView.swift`: Main UI containing the notepad, font picker, and art preview sheet
- `P5WebView.swift`: `UIViewRepresentable` wrapper for WKWebView that loads `sketch.html` and bridges JS-Swift communication
- `MediaSaver.swift`: Handles saving videos and LivePhotos using PHPhotoLibrary and AVFoundation
- `WebViewManager`: `ObservableObject` that controls recording start/stop via JavaScript calls

### Bundled Assets

- `Fonts/McDonald_s_Fries_Font.ttf`: Custom bundled font
- `sketch.html`: P5.js canvas animation with embedded recording logic
- `Assets.xcassets`: Image and color assets

## JavaScript-Swift Communication

The WebView communicates with Swift using `WKScriptMessageHandler`:

1. **Swift → JavaScript**: Call `evaluateJavaScript()` on the WKWebView
   - `startArt(text, fontName)`: Initialize the P5.js visualization with text and font
   - `startRecording()`: Begin canvas recording via MediaRecorder API
   - `stopRecordingAndGetResult()`: Stop recording and send base64 video back to Swift

2. **JavaScript → Swift**: Post messages via `webkit.messageHandlers`
   - `action`: Triggered on canvas tap to show action sheet
   - `videoCallback`: Returns base64-encoded video data for saving

## LivePhoto Creation

LivePhotos require special metadata linking the video and photo:

1. Extract a key frame from the video using `AVAssetImageGenerator`
2. Add MakerNote metadata to the JPEG image with the asset identifier
3. Inject QuickTime metadata (ContentIdentifier) into the video using AVAssetWriter
4. Save both resources together using `PHAssetCreationRequest` with `.pairedVideo`

The video from WebView is typically in WebM format and must be transcoded to `.mov` via `AVAssetExportSession` before AVFoundation can process it for LivePhoto metadata injection.

## Font Integration

Custom fonts are registered by:
1. Adding TTF files to the `Fonts` directory
2. Including them in the Xcode project with "Copy Bundle Resources" and "Copy to Destination"
3. Updating the `bundledFonts` array in `ContentView.swift` with the display name and PostScript name
