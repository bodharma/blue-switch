import CoreAudio
import Foundation

final class AudioManager {
    private var previousOutputDeviceID: AudioDeviceID?
    private var previousInputDeviceID: AudioDeviceID?

    func switchAudioOutput(to deviceName: String) {
        guard let deviceID = findAudioDevice(named: deviceName, isInput: false) else {
            Log.audio.warning("Audio output device not found: \(deviceName)")
            return
        }
        previousOutputDeviceID = getDefaultDevice(isInput: false)
        setDefaultDevice(deviceID, isInput: false)
        Log.audio.info("Switched audio output to \(deviceName)")
    }

    func switchAudioInput(to deviceName: String) {
        guard let deviceID = findAudioDevice(named: deviceName, isInput: true) else {
            Log.audio.warning("Audio input device not found: \(deviceName)")
            return
        }
        previousInputDeviceID = getDefaultDevice(isInput: true)
        setDefaultDevice(deviceID, isInput: true)
        Log.audio.info("Switched audio input to \(deviceName)")
    }

    func revertAudioOutput() {
        guard let prev = previousOutputDeviceID else { return }
        setDefaultDevice(prev, isInput: false)
        previousOutputDeviceID = nil
        Log.audio.info("Reverted audio output to previous device")
    }

    func revertAudioInput() {
        guard let prev = previousInputDeviceID else { return }
        setDefaultDevice(prev, isInput: true)
        previousInputDeviceID = nil
        Log.audio.info("Reverted audio input to previous device")
    }

    private func getDefaultDevice(isInput: Bool) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : nil
    }

    private func setDefaultDevice(_ deviceID: AudioDeviceID, isInput: Bool) {
        var address = AudioObjectPropertyAddress(
            mSelector: isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = deviceID
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        if status != noErr {
            Log.audio.error("Failed to set default \(isInput ? "input" : "output") device: \(status)")
        }
    }

    private func findAudioDevice(named name: String, isInput: Bool) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)

        for deviceID in devices {
            if let deviceName = getDeviceName(deviceID), deviceName.contains(name) {
                return deviceID
            }
        }
        return nil
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        return status == noErr ? name as String : nil
    }

    // MARK: - Codec Preference (Phase 2 — experimental)
    // TODO: Research and implement private API codec switching
    // This is best-effort and may not work on all macOS versions
}
