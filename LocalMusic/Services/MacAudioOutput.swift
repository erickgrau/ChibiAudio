#if os(macOS)
import CoreAudio
import Foundation
import Observation

/// Read-only view of the Mac's default output device for Settings and the
/// player bar. macOS has no `AVAudioSession`: AVPlayer renders to the
/// system default output, and the device's sample rate is whatever Audio
/// MIDI Setup says. This type reports those values and never changes
/// them, so the Mac never claims a DAC mode or bit-perfect path.
@Observable
@MainActor
final class MacAudioOutput {
    static let shared = MacAudioOutput()

    private(set) var deviceName = "System default output"
    /// Nominal sample rate of the output device in Hz, when CoreAudio reports one.
    private(set) var sampleRate: Double?
    private(set) var isUSB = false
    private(set) var transportLabel = "Unknown"

    @ObservationIgnored private var observedDevice = AudioObjectID(kAudioObjectUnknown)

    private init() {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main
        ) { _, _ in
            MainActor.assumeIsolated { MacAudioOutput.shared.refresh() }
        }
        refresh()
    }

    var sampleRateLabel: String {
        guard let sampleRate, sampleRate > 0 else { return "Unknown" }
        let k = sampleRate / 1000
        return abs(k.rounded() - k) < 0.05 ? "\(Int(k.rounded())) kHz" : String(format: "%.1f kHz", k)
    }

    /// One-line summary, e.g. "THX Onyx · 96 kHz".
    var summary: String {
        sampleRate == nil ? deviceName : "\(deviceName) · \(sampleRateLabel)"
    }

    func refresh() {
        let device = Self.defaultOutputDevice()
        guard device != kAudioObjectUnknown else {
            deviceName = "System default output"
            sampleRate = nil
            isUSB = false
            transportLabel = "Unknown"
            return
        }
        deviceName = Self.string(device, kAudioObjectPropertyName) ?? "System default output"
        sampleRate = Self.double(device, kAudioDevicePropertyNominalSampleRate)
        let transport = Self.uint32(device, kAudioDevicePropertyTransportType)
        isUSB = transport == kAudioDeviceTransportTypeUSB
        transportLabel = Self.label(forTransport: transport)
        observeSampleRate(of: device)
    }

    /// Re-reads when the user changes the device rate in Audio MIDI Setup.
    private func observeSampleRate(of device: AudioObjectID) {
        guard device != observedDevice else { return }
        observedDevice = device
        var address = Self.address(kAudioDevicePropertyNominalSampleRate)
        AudioObjectAddPropertyListenerBlock(device, &address, .main) { _, _ in
            MainActor.assumeIsolated { MacAudioOutput.shared.refresh() }
        }
    }

    // MARK: - CoreAudio reads

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func defaultOutputDevice() -> AudioObjectID {
        uint32(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice)
            .map { AudioObjectID($0) } ?? AudioObjectID(kAudioObjectUnknown)
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func double(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Double? {
        var address = address(selector)
        var value: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func label(forTransport transport: UInt32?) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: "Built-in"
        case kAudioDeviceTransportTypeUSB: "USB"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "Bluetooth"
        case kAudioDeviceTransportTypeAirPlay: "AirPlay"
        case kAudioDeviceTransportTypeHDMI: "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: "DisplayPort"
        case kAudioDeviceTransportTypeThunderbolt: "Thunderbolt"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: "Virtual or aggregate"
        default: "Other"
        }
    }
}
#endif
