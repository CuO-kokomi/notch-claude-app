import Foundation
import CoreAudio

@MainActor
final class VolumeProvider: ObservableObject {
    @Published var volume: Float = 0.5
    @Published var isMuted: Bool = false

    private var timer: Timer?
    private var volumeBeforeMute: Float = 0.5

    init() {
        volume = getVolume()
        isMuted = getMuted()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.volume = self?.getVolume() ?? 0.5
                self?.isMuted = self?.getMuted() ?? false
            }
        }
    }

    func setVolume(_ value: Float) {
        volume = value
        if value > 0 && isMuted {
            setMuted(false)
            isMuted = false
        }
        let deviceID = defaultOutputDevice()
        let element = workingVolumeElement(device: deviceID)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        var vol = value
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &vol)
    }

    func toggleMute() {
        if isMuted {
            setMuted(false)
            isMuted = false
            if volume <= 0 {
                setVolume(volumeBeforeMute > 0 ? volumeBeforeMute : 0.3)
            }
        } else {
            volumeBeforeMute = volume
            setMuted(true)
            isMuted = true
        }
    }

    private func getVolume() -> Float {
        let deviceID = defaultOutputDevice()
        let element = workingVolumeElement(device: deviceID)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        var volume: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        return volume
    }

    private func workingVolumeElement(device: AudioObjectID) -> AudioObjectPropertyElement {
        for element: AudioObjectPropertyElement in [0, 1] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            if AudioObjectHasProperty(device, &address) {
                return element
            }
        }
        return 0
    }

    private func getMuted() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let deviceID = defaultOutputDevice()
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        return muted != 0
    }

    private func setMuted(_ muted: Bool) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = muted ? 1 : 0
        let deviceID = defaultOutputDevice()
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private func defaultOutputDevice() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }
}
