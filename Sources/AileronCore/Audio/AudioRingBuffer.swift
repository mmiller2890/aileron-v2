import CSileroVad
import Foundation

public final class AudioRingBuffer: @unchecked Sendable {
    public let capacity: Int
    private let mask: UInt64
    private let storage: UnsafeMutablePointer<Float>
    private let readPos: UnsafeMutablePointer<aileron_atomic_u64>
    private let writePos: UnsafeMutablePointer<aileron_atomic_u64>
    private let droppedCount: UnsafeMutablePointer<aileron_atomic_u64>

    public init(capacity: Int) {
        var pow2 = 1024
        let target = max(1024, capacity)
        while pow2 < target && pow2 < (1 << 28) {
            pow2 <<= 1
        }
        self.capacity = pow2
        self.mask = UInt64(pow2 - 1)
        self.storage = .allocate(capacity: pow2)
        self.storage.initialize(repeating: 0, count: pow2)
        self.readPos = .allocate(capacity: 1)
        self.writePos = .allocate(capacity: 1)
        self.droppedCount = .allocate(capacity: 1)
        aileron_atomic_init(self.readPos, 0)
        aileron_atomic_init(self.writePos, 0)
        aileron_atomic_init(self.droppedCount, 0)
    }

    deinit {
        storage.deallocate()
        readPos.deallocate()
        writePos.deallocate()
        droppedCount.deallocate()
    }

    public func write(_ samples: UnsafeBufferPointer<Float>) {
        guard let base = samples.baseAddress, !samples.isEmpty else { return }
        let incomingCount = samples.count
        let w = aileron_atomic_load_relaxed(writePos)
        let r = aileron_atomic_load_acquire(readPos)
        let used = Int(w &- r)
        let available = max(0, capacity - used)
        let toWrite = min(incomingCount, available)
        let dropped = incomingCount - toWrite
        if dropped > 0 {
            _ = aileron_atomic_fetch_add_relaxed(droppedCount, UInt64(dropped))
        }
        guard toWrite > 0 else { return }

        let startIndex = Int(w & mask)
        let firstChunk = min(toWrite, capacity - startIndex)
        storage.advanced(by: startIndex).update(from: base, count: firstChunk)
        let remainder = toWrite - firstChunk
        if remainder > 0 {
            storage.update(from: base.advanced(by: firstChunk), count: remainder)
        }
        aileron_atomic_store_release(writePos, w &+ UInt64(toWrite))
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

        let w = aileron_atomic_load_relaxed(writePos)
        let r = aileron_atomic_load_acquire(readPos)
        let used = Int(w &- r)
        let available = max(0, capacity - used)
        let toWrite = min(frames, available)
        let dropped = frames - toWrite
        if dropped > 0 {
            _ = aileron_atomic_fetch_add_relaxed(droppedCount, UInt64(dropped))
        }
        guard toWrite > 0 else { return }

        var writeIndex = Int(w & mask)
        for frame in 0..<toWrite {
            var sum: Float = 0
            let offset = frame * channels
            for ch in 0..<channels {
                sum += base[offset + ch]
            }
            storage[writeIndex] = sum * invChannels
            writeIndex = (writeIndex + 1) & Int(mask)
        }
        aileron_atomic_store_release(writePos, w &+ UInt64(toWrite))
    }

    public func writeNonInterleavedMonoDownmix(
        channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frameLength: Int
    ) {
        guard channelCount > 0, frameLength > 0 else { return }
        if channelCount == 1 {
            write(UnsafeBufferPointer(start: channels[0], count: frameLength))
            return
        }
        let invChannels = 1.0 / Float(channelCount)
        let w = aileron_atomic_load_relaxed(writePos)
        let r = aileron_atomic_load_acquire(readPos)
        let used = Int(w &- r)
        let available = max(0, capacity - used)
        let toWrite = min(frameLength, available)
        let dropped = frameLength - toWrite
        if dropped > 0 {
            _ = aileron_atomic_fetch_add_relaxed(droppedCount, UInt64(dropped))
        }
        guard toWrite > 0 else { return }

        var writeIndex = Int(w & mask)
        for frame in 0..<toWrite {
            var sum: Float = 0
            for ch in 0..<channelCount {
                sum += channels[ch][frame]
            }
            storage[writeIndex] = sum * invChannels
            writeIndex = (writeIndex + 1) & Int(mask)
        }
        aileron_atomic_store_release(writePos, w &+ UInt64(toWrite))
    }

    public func drain(into output: inout [Float]) -> UInt64 {
        output.removeAll(keepingCapacity: true)
        let r = aileron_atomic_load_relaxed(readPos)
        let w = aileron_atomic_load_acquire(writePos)
        let available = Int(w &- r)
        let dropped = aileron_atomic_exchange_relaxed(droppedCount, 0)
        guard available > 0 else { return dropped }

        output.reserveCapacity(available)
        let startIndex = Int(r & mask)
        let firstChunk = min(available, capacity - startIndex)
        output.append(contentsOf: UnsafeBufferPointer(start: storage.advanced(by: startIndex), count: firstChunk))
        let remainder = available - firstChunk
        if remainder > 0 {
            output.append(contentsOf: UnsafeBufferPointer(start: storage, count: remainder))
        }
        aileron_atomic_store_release(readPos, r &+ UInt64(available))
        return dropped
    }

    public func reset() {
        let w = aileron_atomic_load_acquire(writePos)
        aileron_atomic_store_release(readPos, w)
        _ = aileron_atomic_exchange_relaxed(droppedCount, 0)
    }
}
