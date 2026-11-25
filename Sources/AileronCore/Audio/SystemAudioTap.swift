import AudioToolbox
import CoreAudio
import Foundation
import os

public enum SystemAudioTapError: LocalizedError {
    case noOutputDevice
    case processTapCreationFailed(OSStatus)
    case tapUIDReadFailed(OSStatus)
    case tapFormatReadFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .noOutputDevice:
            return "No macOS audio output device is currently available."
        case .processTapCreationFailed(let status):
            return "Could not create macOS system audio tap (OSStatus \(status)). Check System Audio Recording permission in System Settings > Privacy & Security."
        case .tapUIDReadFailed(let status):
            return "Failed to read CoreAudio tap UID (OSStatus \(status))."
        case .tapFormatReadFailed(let status):
            return "Failed to read CoreAudio tap stream format (OSStatus \(status))."
        case .aggregateDeviceCreationFailed(let status):
            return "Failed to create CoreAudio aggregate capture device (OSStatus \(status))."
        case .ioProcCreationFailed(let status):
            return "Failed to attach CoreAudio IO callback (OSStatus \(status))."
        case .deviceStartFailed(let status):
            return "Failed to start CoreAudio tap device (OSStatus \(status))."
        }
    }
}

public final class SystemAudioTap: @unchecked Sendable {
    public let boundOutputUID: String
    public let boundDeviceName: String

    private let ringBuffer: AudioRingBuffer
    private let sampleRateLock: OSAllocatedUnfairLock<Double>
    private let stateLock = NSLock()
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var isRunning: Bool = false

    public var currentSampleRate: Double {
        sampleRateLock.withLock { $0 }
    }

    public init(preferredOutputUID: String? = nil) throws {
        let outputDeviceID: AudioDeviceID
        if let uid = preferredOutputUID, !uid.isEmpty, uid != "default",
           let found = AudioDeviceManager.findOutputDeviceID(uid: uid) {
            outputDeviceID = found
        } else if let def = AudioDeviceManager.defaultOutputDeviceID() {
            outputDeviceID = def
        } else {
            throw SystemAudioTapError.noOutputDevice
        }

        guard let outputUID = AudioDeviceManager.deviceUID(for: outputDeviceID) else {
            throw SystemAudioTapError.noOutputDevice
        }
        self.boundOutputUID = outputUID
        self.boundDeviceName = AudioDeviceManager.deviceName(for: outputDeviceID) ?? "System Output"

        let tapDescription = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        tapDescription.muteBehavior = .unmuted
        tapDescription.name = "Aileron System Audio Tap"
        tapDescription.isPrivate = true

        var createdTapID = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &createdTapID)
        guard tapStatus == noErr, createdTapID != kAudioObjectUnknown else {
            throw SystemAudioTapError.processTapCreationFailed(tapStatus)
        }
        self.tapID = createdTapID

        var tapUIDAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfTapUID: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let uidStatus = AudioObjectGetPropertyData(createdTapID, &tapUIDAddress, 0, nil, &uidSize, &cfTapUID)
        guard uidStatus == noErr, let tapUID = cfTapUID?.takeRetainedValue() as String? else {
            AudioHardwareDestroyProcessTap(createdTapID)
            throw SystemAudioTapError.tapUIDReadFailed(uidStatus)
        }

        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let fmtStatus = AudioObjectGetPropertyData(createdTapID, &formatAddress, 0, nil, &formatSize, &asbd)
        guard fmtStatus == noErr, asbd.mSampleRate > 0 else {
            AudioHardwareDestroyProcessTap(createdTapID)
            throw SystemAudioTapError.tapFormatReadFailed(fmtStatus)
        }

        let initialRate = asbd.mSampleRate
        self.sampleRateLock = OSAllocatedUnfairLock(initialState: initialRate)
        self.ringBuffer = AudioRingBuffer(capacity: max(96_000, Int(initialRate) * 6))

        let aggregateUID = "com.aileron.tap.\(UUID().uuidString)"
        let aggregateDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Aileron Capture Aggregate",
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey as String: outputUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceSubDeviceListKey as String: [
                [kAudioSubDeviceUIDKey as String: outputUID]
            ],
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapDriftCompensationKey as String: true,
                    kAudioSubTapUIDKey as String: tapUID
                ]
            ]
        ]

        var createdAggID = AudioDeviceID(kAudioObjectUnknown)
        let aggStatus = AudioHardwareCreateAggregateDevice(aggregateDesc as CFDictionary, &createdAggID)
        guard aggStatus == noErr, createdAggID != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(createdTapID)
            throw SystemAudioTapError.aggregateDeviceCreationFailed(aggStatus)
        }
        self.aggregateDeviceID = createdAggID

        let channelsPerFrame = max(1, Int(asbd.mChannelsPerFrame))
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let capturedRing = self.ringBuffer
        let capturedRateLock = self.sampleRateLock
        let capturedAggID = createdAggID

        var createdProcID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&createdProcID, createdAggID, nil) { _, inInputData, _, _, _ in
            if let liveRate = AudioDeviceManager.actualSampleRate(for: capturedAggID), liveRate > 0 {
                capturedRateLock.withLock { $0 = liveRate }
            }
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            guard let first = buffers.first, let rawData = first.mData, first.mDataByteSize > 0 else {
                return
            }
            if isFloat {
                let floatCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size
                guard floatCount > 0 else { return }
                let ptr = rawData.assumingMemoryBound(to: Float.self)
                let buf = UnsafeBufferPointer(start: ptr, count: floatCount)
                if isNonInterleaved || channelsPerFrame == 1 || first.mNumberChannels == 1 {
                    capturedRing.write(buf)
                } else {
                    capturedRing.writeMonoDownmix(interleaved: buf, channels: Int(first.mNumberChannels))
                }
            }
        }
        guard procStatus == noErr, let validProcID = createdProcID else {
            AudioHardwareDestroyAggregateDevice(createdAggID)
            AudioHardwareDestroyProcessTap(createdTapID)
            throw SystemAudioTapError.ioProcCreationFailed(procStatus)
        }
        self.ioProcID = validProcID

        let startStatus = AudioDeviceStart(createdAggID, validProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(createdAggID, validProcID)
            AudioHardwareDestroyAggregateDevice(createdAggID)
            AudioHardwareDestroyProcessTap(createdTapID)
            throw SystemAudioTapError.deviceStartFailed(startStatus)
        }
        self.isRunning = true
    }

    public func drain(into buffer: inout [Float]) -> UInt64 {
        ringBuffer.drain(into: &buffer)
    }

    public func stop() {
        stateLock.lock()
        defer { stateLock.unlock() }
        if isRunning, aggregateDeviceID != kAudioObjectUnknown, let proc = ioProcID {
            AudioDeviceStop(aggregateDeviceID, proc)
            isRunning = false
        }
        if aggregateDeviceID != kAudioObjectUnknown, let proc = ioProcID {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, proc)
            ioProcID = nil
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        ringBuffer.reset()
    }

    deinit {
        stop()
    }
}
