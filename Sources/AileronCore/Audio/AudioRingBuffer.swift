import Foundation
import os

public final class AudioRingBuffer: @unchecked Sendable {
    private var buffer: [Float]
    private var readIndex: Int = 0
    private var writeIndex: Int = 0
    private var count: Int = 0
    private var droppedSamples: UInt64 = 0
    private let capacity: Int
    private var lock = os_unfair_lock_s()

    public init(capacity: Int) {
        let safeCap = max(1024, capacity)
        self.capacity = safeCap
        self.buffer = [Float](repeating: 0, count: safeCap)
    }

    public func write(_ samples: UnsafeBufferPointer<Float>) {
        guard let base = samples.baseAddress, !samples.isEmpty else { return }
        let incomingCount = samples.count
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let available = capacity - count
        let toWrite = min(incomingCount, available)
        let dropped = incomingCount - toWrite
        if dropped > 0 {
            droppedSamples &+= UInt64(dropped)
        }
        guard toWrite > 0 else { return }

        let firstChunk = min(toWrite, capacity - writeIndex)
        buffer.withUnsafeMutableBufferPointer { dst in
            guard let dstBase = dst.baseAddress else { return }
            dstBase.advanced(by: writeIndex).update(from: base, count: firstChunk)
            let remainder = toWrite - firstChunk
            if remainder > 0 {
                dstBase.update(from: base.advanced(by: firstChunk), count: remainder)
            }
        }
        writeIndex = (writeIndex + toWrite) % capacity
        count += toWrite
    }

    public func writeMonoDownmix(interleaved: UnsafeBufferPointer<Float>, channels: Int) {
        guard let base = interleaved.baseAddress, channels > 0, !interleaved.isEmpty else { return }
        if channels == 1 {
            write(interleaved)
            return
        }
        let frames = interleaved.count / channels
        guard frames > 0 else { return }
        let invChannels = 1.0 / Float(channels)

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let available = capacity - count
        let toWrite = min(frames, available)
        let dropped = frames - toWrite
        if dropped > 0 {
            droppedSamples &+= UInt64(dropped)
        }
        guard toWrite > 0 else { return }

        for frame in 0..<toWrite {
            var sum: Float = 0
            let offset = frame * channels
            for ch in 0..<channels {
                sum += base[offset + ch]
            }
            buffer[writeIndex] = sum * invChannels
            writeIndex += 1
            if writeIndex == capacity {
                writeIndex = 0
            }
        }
        count += toWrite
    }

    public func drain(into output: inout [Float]) -> UInt64 {
        output.removeAll(keepingCapacity: true)
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let dropped = droppedSamples
        droppedSamples = 0
        guard count > 0 else { return dropped }

        output.reserveCapacity(count)
        let firstChunk = min(count, capacity - readIndex)
        output.append(contentsOf: buffer[readIndex..<(readIndex + firstChunk)])
        let remainder = count - firstChunk
        if remainder > 0 {
            output.append(contentsOf: buffer[0..<remainder])
        }
        readIndex = (readIndex + count) % capacity
        count = 0
        return dropped
    }

    public func reset() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        readIndex = 0
        writeIndex = 0
        count = 0
        droppedSamples = 0
    }
}
