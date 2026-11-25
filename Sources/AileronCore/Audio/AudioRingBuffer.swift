import Foundation
import os

public final class AudioRingBuffer: @unchecked Sendable {
    private struct State {
        var buffer: [Float]
        var readIndex: Int = 0
        var writeIndex: Int = 0
        var count: Int = 0
        var droppedSamples: UInt64 = 0
    }

    private let capacity: Int
    private let lock: OSAllocatedUnfairLock<State>

    public init(capacity: Int) {
        let safeCap = max(1024, capacity)
        self.capacity = safeCap
        self.lock = OSAllocatedUnfairLock(initialState: State(buffer: [Float](repeating: 0, count: safeCap)))
    }

    public func write(_ samples: UnsafeBufferPointer<Float>) {
        guard let base = samples.baseAddress, !samples.isEmpty else { return }
        let incomingCount = samples.count
        lock.withLock { state in
            let available = capacity - state.count
            let toWrite = min(incomingCount, available)
            let dropped = incomingCount - toWrite
            if dropped > 0 {
                state.droppedSamples &+= UInt64(dropped)
            }
            guard toWrite > 0 else { return }
            let firstChunk = min(toWrite, capacity - state.writeIndex)
            state.buffer.withUnsafeMutableBufferPointer { dst in
                guard let dstBase = dst.baseAddress else { return }
                dstBase.advanced(by: state.writeIndex).update(from: base, count: firstChunk)
                let remainder = toWrite - firstChunk
                if remainder > 0 {
                    dstBase.update(from: base.advanced(by: firstChunk), count: remainder)
                }
            }
            state.writeIndex = (state.writeIndex + toWrite) % capacity
            state.count += toWrite
        }
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
        lock.withLock { state in
            let available = capacity - state.count
            let toWrite = min(frames, available)
            let dropped = frames - toWrite
            if dropped > 0 {
                state.droppedSamples &+= UInt64(dropped)
            }
            guard toWrite > 0 else { return }
            for frame in 0..<toWrite {
                var sum: Float = 0
                let offset = frame * channels
                for ch in 0..<channels {
                    sum += base[offset + ch]
                }
                state.buffer[state.writeIndex] = sum * invChannels
                state.writeIndex += 1
                if state.writeIndex == capacity {
                    state.writeIndex = 0
                }
            }
            state.count += toWrite
        }
    }

    public func drain(into output: inout [Float]) -> UInt64 {
        let (samples, dropped): ([Float], UInt64) = lock.withLock { state in
            let droppedCount = state.droppedSamples
            state.droppedSamples = 0
            guard state.count > 0 else { return ([], droppedCount) }
            var extracted: [Float] = []
            extracted.reserveCapacity(state.count)
            let firstChunk = min(state.count, capacity - state.readIndex)
            extracted.append(contentsOf: state.buffer[state.readIndex..<(state.readIndex + firstChunk)])
            let remainder = state.count - firstChunk
            if remainder > 0 {
                extracted.append(contentsOf: state.buffer[0..<remainder])
            }
            state.readIndex = (state.readIndex + state.count) % capacity
            state.count = 0
            return (extracted, droppedCount)
        }
        output.removeAll(keepingCapacity: true)
        output.append(contentsOf: samples)
        return dropped
    }

    public func reset() {
        lock.withLock { state in
            state.readIndex = 0
            state.writeIndex = 0
            state.count = 0
            state.droppedSamples = 0
        }
    }
}
