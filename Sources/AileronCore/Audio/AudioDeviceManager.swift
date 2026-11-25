import CoreAudio
import Foundation

public enum AudioDeviceManager {
    public static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    public static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    public static func defaultOutputUID() -> String? {
        guard let id = defaultOutputDeviceID() else { return nil }
        return deviceUID(for: id)
    }

    public static func defaultOutputName() -> String {
        guard let id = defaultOutputDeviceID() else { return "System Default" }
        return deviceName(for: id) ?? "System Default"
    }

    public static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &ids
        ) == noErr else {
            return []
        }
        return ids
    }

    public static func outputDevices() -> [AudioDeviceInfo] {
        let defaultUID = defaultOutputUID()
        return allDeviceIDs().compactMap { id in
            guard channelCount(for: id, scope: kAudioDevicePropertyScopeOutput) > 0,
                  let uid = deviceUID(for: id),
                  let name = deviceName(for: id) else {
                return nil
            }
            return AudioDeviceInfo(
                id: uid,
                name: name,
                isDefault: uid == defaultUID,
                isInput: false
            )
        }
    }

    public static func inputDevices() -> [AudioDeviceInfo] {
        let defaultUID = defaultInputDeviceID().flatMap { deviceUID(for: $0) }
        return allDeviceIDs().compactMap { id in
            guard channelCount(for: id, scope: kAudioDevicePropertyScopeInput) > 0,
                  let uid = deviceUID(for: id),
                  let name = deviceName(for: id) else {
                return nil
            }
            return AudioDeviceInfo(
                id: uid,
                name: name,
                isDefault: uid == defaultUID,
                isInput: true
            )
        }
    }

    public static func findOutputDeviceID(uid: String) -> AudioDeviceID? {
        for id in allDeviceIDs() {
            if channelCount(for: id, scope: kAudioDevicePropertyScopeOutput) > 0,
               deviceUID(for: id) == uid {
                return id
            }
        }
        return nil
    }

    public static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        stringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID)
    }

    public static func deviceName(for deviceID: AudioDeviceID) -> String? {
        stringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName)
    }

    public static func actualSampleRate(for deviceID: AudioDeviceID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyActualSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate) == noErr, rate > 0 {
            return rate
        }
        address.mSelector = kAudioDevicePropertyNominalSampleRate
        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate) == noErr, rate > 0 {
            return rate
        }
        return nil
    }

    private static func stringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfStr: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &cfStr)
        guard status == noErr, let unwrapped = cfStr?.takeRetainedValue() else { return nil }
        return unwrapped as String
    }

    private static func channelCount(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let rawPtr = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPtr.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, rawPtr) == noErr else {
            return 0
        }
        let bufferList = UnsafeMutableAudioBufferListPointer(rawPtr.assumingMemoryBound(to: AudioBufferList.self))
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
