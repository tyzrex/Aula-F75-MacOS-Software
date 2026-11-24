import SwiftUI
import KeylumeKit

/// A plain-text report to paste into a bug report. Contains no personal data: versions, what macOS sees, the keyboard's state.
@MainActor
enum Diagnostics {
    static func report(_ model: HubModel) -> String {
        let info = Bundle.main.infoDictionary
        var lines = [
            "Keylume \(info?["CFBundleShortVersionString"] as? String ?? "dev") (\(info?["CFBundleVersion"] as? String ?? "-"))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "",
            "Connection: \(model.connection?.title ?? "not connected")\(model.isDemo ? " (demo)" : "")",
            "Seen by macOS: \(model.present.map(\.title).sorted().joined(separator: ", ").nonEmpty ?? "nothing")",
        ]
        for c in HIDDiscovery.enumerate() {
            lines.append(String(format: "  %04x:%04x %@ usagePage 0x%04x maxFeature %d collections %@", c.info.vendorID, c.info.productID,
                                c.info.connection.title, c.usagePage, c.maxFeature, c.usagePages.sorted().map { String($0, radix: 16) }.joined(separator: ",")))
        }
        if let f = model.firmware { lines.append("Firmware: \(f)") }
        if let l = model.led {
            lines.append("Effect: \(Effects.byHW(l.effect)?.name ?? "unknown") (\(l.effect)), mode: \(["windows", "android", "mac"][min(l.osMode, 2)]), side light: \(l.sideMode), knob: \(l.knobMode), sleep: \(l.sleep) s")
        }
        if let b = model.battery { lines.append("Battery: \(b.level)%\(b.charging ? " charging" : "")") }
        if let e = model.connectError { lines.append("Last connect error: \(e)") }
        if let n = model.notice, n.isError { lines.append("Last error: \(n.text)") }
        return lines.joined(separator: "\n")
    }

    static func copy(_ model: HubModel) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report(model), forType: .string)
        model.notice = Notice(text: "Diagnostics copied to the clipboard", isError: false)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
