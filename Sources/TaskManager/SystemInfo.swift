import Foundation
import IOKit
import IOKit.ps

/// Read-only facts about this Mac. Hostname and serial number are deliberately not collected.
enum SystemInfo {
    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    static func sysctlInt(_ name: String) -> Int? {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &v, &size, nil, 0) == 0 ? Int(v) : nil
    }

    /// Marketing name such as "MacBook Air (15-inch, M5)"; falls back to the model identifier.
    static var modelName: String {
        let e = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        if e != 0 {
            defer { IOObjectRelease(e) }
            if let d = IORegistryEntryCreateCFProperty(e, "product-name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
               let s = String(data: d, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")), !s.isEmpty { return s }
        }
        return modelIdentifier
    }

    static var modelIdentifier: String { sysctlString("hw.model") ?? "Mac" }

    /// "10 (4 performance + 6 efficiency)" on Apple silicon, otherwise just the core count.
    static var cores: String {
        let total = sysctlInt("hw.physicalcpu") ?? ProcessInfo.processInfo.processorCount
        if let p = sysctlInt("hw.perflevel0.physicalcpu"), let e = sysctlInt("hw.perflevel1.physicalcpu") {
            return "\(total) (\(p) performance + \(e) efficiency)"
        }
        return "\(total)"
    }

    static var performanceCores: Int? { sysctlInt("hw.perflevel0.physicalcpu") }
    static var efficiencyCores: Int? { sysctlInt("hw.perflevel1.physicalcpu") }

    static var macOS: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
    }

    static var build: String { sysctlString("kern.osversion") ?? "–" }

    static var thermal: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    static func uptime() -> String {
        let s = Int(ProcessInfo.processInfo.systemUptime)
        return String(format: "%dd %02d:%02d:%02d", s / 86400, s % 86400 / 3600, s % 3600 / 60, s % 60)
    }

    static var storage: (total: Int64, available: Int64)? {
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let t = v.volumeTotalCapacity, let a = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return (Int64(t), a)
    }

    /// The internal battery, if this Mac has one.
    static var battery: (percent: Int, state: String)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0, full = max(d[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let state = (d[kIOPSIsChargingKey] as? Bool ?? false) ? "Charging"
                : (d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue ? "On power adapter" : "On battery")
            return (cur * 100 / full, state)
        }
        return nil
    }
}
