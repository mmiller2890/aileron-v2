import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

public enum MicCaptureError: LocalizedError {
    case permissionDenied
    case invalidInputFormat
    case engineStartFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission is required for voice dictation. Grant access in System Settings > Privacy & Security > Microphone."
        case .invalidInputFormat:
            return "Could not read microphone audio format."
        case .engineStartFailed(let reason):
            return "Microphone capture failed to start: \(reason)"
        }
    }
}

public final class MicCapture: @unchecked Sendable {
    private var engine = AVAudioEngine()
    private let ringBuffer = AudioRingBuffer(capacity: 48_000 * 10)
    private let lock = NSLock()
    private var isRunning = false
    private var inputSampleRate: Double = 48_000

    public init() {}

    public var sampleRate: Double {
        lock.lock()
        defer { lock.unlock() }
        return inputSampleRate
    }

    public func start(preferredInputUID: String? = nil) async throws {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else {
            throw MicCaptureError.permissionDenied
        }
        try startEngineLocked(preferredInputUID: preferredInputUID)
    }

    private func startEngineLocked(preferredInputUID: String?) throws {
        lock.lock()
        defer { lock.unlock() }
        if isRunning { return }

        engine = AVAudioEngine()
        let inputNode = engine.inputNode

        if let uid = preferredInputUID,
           !uid.isEmpty,
           uid != "default",
           var deviceID = AudioDeviceManager.findInputDeviceID(uid: uid),
           let audioUnit = inputNode.audioUnit {
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                DiagnosticsLog.shared.record(
                    category: "mic",
                    message: "Preferred input device bind failed (OSStatus \(status)); falling back to default"
                )
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MicCaptureError.invalidInputFormat
        }
        inputSampleRate = format.sampleRate
        ringBuffer.reset()

        let capturedRing = ringBuffer
        let channels = Int(format.channelCount)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }
            capturedRing.writeNonInterleavedMonoDownmix(
                channels: channelData,
                channelCount: channels,
                frameLength: frameLength
            )
        }

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
        } catch {
            inputNode.removeTap(onBus: 0)
            throw MicCaptureError.engineStartFailed(error.localizedDescription)
        }
    }

    public func drainRaw(into buffer: inout [Float]) -> UInt64 {
        ringBuffer.drain(into: &buffer)
    }

    public func stopAndDrainRaw() -> (samples: [Float], sampleRate: Double) {
        lock.lock()
        let rate = inputSampleRate
        if isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            isRunning = false
        }
        lock.unlock()

        var raw: [Float] = []
        _ = ringBuffer.drain(into: &raw)
        return (raw, rate)
    }

    public func cancel() {
        lock.lock()
        if isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            isRunning = false
        }
        lock.unlock()
        ringBuffer.reset()
    }
}
