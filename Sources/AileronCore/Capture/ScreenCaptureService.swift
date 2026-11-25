import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

public struct CapturedScreenshot: Identifiable, Sendable {
    public let id: UUID
    public let jpegData: Data
    public let width: Int
    public let height: Int
    public let capturedAt: Date

    public init(id: UUID = UUID(), jpegData: Data, width: Int, height: Int, capturedAt: Date = Date()) {
        self.id = id
        self.jpegData = jpegData
        self.width = width
        self.height = height
        self.capturedAt = capturedAt
    }
}

public enum ScreenCaptureError: LocalizedError {
    case noDisplayFound
    case encodingFailed
    case permissionRequired(String)

    public var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "No active display was found to capture."
        case .encodingFailed:
            return "Could not encode the screen capture image."
        case .permissionRequired(let detail):
            return "Screen capture unavailable: \(detail). Grant Screen Recording permission in System Settings > Privacy & Security."
        }
    }
}

public enum ScreenCaptureService {
    public static func captureActiveDisplay(maxWidth: Int = 1600, jpegQuality: CGFloat = 0.82) async throws -> CapturedScreenshot {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw ScreenCaptureError.permissionRequired(error.localizedDescription)
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == currentPID }

        let targetDisplay: SCDisplay
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }),
           let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
           let matched = content.displays.first(where: { $0.displayID == screenNumber }) {
            targetDisplay = matched
        } else if let primary = content.displays.first {
            targetDisplay = primary
        } else {
            throw ScreenCaptureError.noDisplayFound
        }

        let filter = SCContentFilter(display: targetDisplay, excludingWindows: ownWindows)
        let config = SCStreamConfiguration()
        let srcWidth = max(1, targetDisplay.width)
        let srcHeight = max(1, targetDisplay.height)
        if srcWidth > maxWidth {
            let scale = Double(maxWidth) / Double(srcWidth)
            config.width = maxWidth
            config.height = max(1, Int(Double(srcHeight) * scale))
        } else {
            config.width = srcWidth
            config.height = srcHeight
        }
        config.showsCursor = false

        let cgImage: CGImage
        do {
            cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw ScreenCaptureError.permissionRequired(error.localizedDescription)
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality]) else {
            throw ScreenCaptureError.encodingFailed
        }

        return CapturedScreenshot(
            jpegData: jpeg,
            width: cgImage.width,
            height: cgImage.height
        )
    }
}
