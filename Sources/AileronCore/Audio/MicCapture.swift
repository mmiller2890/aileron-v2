import AVFoundation
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
    private let engine = AVAudioEngine()
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

    public func start() async throws {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else {
            throw MicCaptureError.permissionDenied
        }

        lock.lock()
        defer { lock.unlock() }
        if isRunning { return }

        let inputNode = engine.inputNode
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
            if channels == 1 {
                let ptr = UnsafeBufferPointer(start: channelData[0], count: frameLength)
                capturedRing.write(ptr)
            } else {
                var mono = [Float](repeating: 0, count: frameLength)
                let scale = 1.0 / Float(channels)
                for ch in 0..<channels {
                    let src = channelData[ch]
                    for i in 0..<frameLength {
                        mono[i] += src[i] * scale
                    }
                }
                mono.withUnsafeBufferPointer { capturedRing.write($0) }
            }
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
