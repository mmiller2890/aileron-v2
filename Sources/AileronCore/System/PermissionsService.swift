import AppKit
import AVFoundation
import CoreGraphics
import Foundation

public enum PermissionState: String, Equatable, Sendable {
    case granted
    case denied
    case notDetermined
    case needsVerification
}

public enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    case microphone
    case systemAudio
    case screenRecording

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .systemAudio: return "System Audio Recording"
        case .screenRecording: return "Screen Recording"
        }
    }

    public var detail: String {
        switch self {
        case .microphone:
            return "Used for live streaming voice questions (⌘⇧M)."
        case .systemAudio:
            return "Taps call audio locally on your Mac with CoreAudio — no virtual drivers."
        case .screenRecording:
            return "Captures your active display for visual Q&A (⌘⇧S), excluding Aileron."
        }
    }

    public var systemSettingsURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .systemAudio:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }
}

public struct PermissionsSnapshot: Equatable, Sendable {
    public var microphone: PermissionState
    public var systemAudio: PermissionState
    public var screenRecording: PermissionState

    public init(
        microphone: PermissionState = .notDetermined,
        systemAudio: PermissionState = .needsVerification,
        screenRecording: PermissionState = .notDetermined
    ) {
        self.microphone = microphone
        self.systemAudio = systemAudio
        self.screenRecording = screenRecording
    }
}

public enum PermissionsService {
    public static func currentMicrophoneState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    public static func currentScreenRecordingState() -> PermissionState {
        CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
    }

    public static func requestMicrophone() async -> PermissionState {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .denied
    }

    @discardableResult
    public static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static func probeSystemAudioTap() -> PermissionState {
        do {
            let tap = try SystemAudioTap(preferredOutputUID: nil)
            tap.stop()
            return .granted
        } catch {
            return .denied
        }
    }

    @MainActor
    public static func openSystemSettings(for kind: PermissionKind) {
        if let url = kind.systemSettingsURL {
            NSWorkspace.shared.open(url)
        }
    }
}
