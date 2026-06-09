// Capture a specific app's main window via ScreenCaptureKit and save it as PNG.
//
// On macOS 15+ `screencapture -l <windowID>` single-window capture is blocked,
// and region capture (`-R`) grabs whatever app sits on top of those coordinates.
// SCContentFilter(desktopIndependentWindow:) points at the window itself, so it
// captures only that window's content even when other windows overlap it.
//
// Usage: capture-window.swift <out.png> [ownerName=Petals]

import AppKit
import ScreenCaptureKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: capture-window.swift <out.png> [ownerName]\n".utf8))
    exit(2)
}
let outPath = CommandLine.arguments[1]
let owner = CommandLine.arguments.count >= 3 ? CommandLine.arguments[2] : "Petals"

// ScreenCaptureKit requires a WindowServer connection. In a CLI process you must
// bring up NSApplication to initialize it (otherwise CGS_REQUIRE_INIT crashes).
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        // Match owner + normal window layer (0), pick the largest.
        let candidates = content.windows.filter {
            $0.owningApplication?.applicationName == owner
                && $0.isOnScreen
                && $0.windowLayer == 0
        }
        guard let win = candidates.max(by: {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }) else {
            FileHandle.standardError.write(Data("no on-screen window for owner '\(owner)'\n".utf8))
            exit(1)
        }

        let filter = SCContentFilter(desktopIndependentWindow: win)
        let config = SCStreamConfiguration()
        let scale = 2 // Retina 2x
        config.width = Int(win.frame.width) * scale
        config.height = Int(win.frame.height) * scale
        config.scalesToFit = true
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        guard let dest = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            FileHandle.standardError.write(Data("cannot create PNG destination\n".utf8))
            exit(1)
        }
        CGImageDestinationAddImage(dest, image, nil)
        if CGImageDestinationFinalize(dest) {
            exit(0)
        } else {
            FileHandle.standardError.write(Data("PNG finalize failed\n".utf8))
            exit(1)
        }
    } catch {
        FileHandle.standardError.write(Data("capture error: \(error)\n".utf8))
        exit(1)
    }
}

app.run()
