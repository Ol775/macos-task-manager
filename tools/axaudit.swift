// Lists interactive controls in the running Task Manager window that have no accessibility label.
// Run: swiftc -O tools/axaudit.swift -o /tmp/axaudit && /tmp/axaudit   (the app must be running; the terminal needs Accessibility access)
import ApplicationServices
import AppKit

func attr(_ e: AXUIElement, _ k: String) -> Any? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil
}
func text(_ v: Any?) -> String {
    if let s = v as? String { return s }
    if let a = v as? NSAttributedString { return a.string }
    return ""
}
let interactive: Set<String> = ["AXButton", "AXCheckBox", "AXPopUpButton", "AXRadioButton", "AXTextField", "AXColorWell", "AXMenuButton", "AXSlider", "AXSwitch", "AXTextArea", "AXComboBox"]
var bad = 0, total = 0
func walk(_ e: AXUIElement, _ depth: Int) {
    let role = text(attr(e, "AXRole"))
    if interactive.contains(role) {
        total += 1
        let label = [text(attr(e, "AXAttributedDescription")), text(attr(e, "AXDescription")), text(attr(e, "AXTitle")), text(attr(e, "AXLabel"))].first { !$0.isEmpty } ?? ""
        let help = text(attr(e, "AXHelp")), val = text(attr(e, "AXValue"))
        let sub = text(attr(e, "AXSubrole"))
        if label.isEmpty && !["AXIncrementArrow", "AXDecrementArrow", "AXIncrementPage", "AXDecrementPage", "AXCloseButton", "AXMinimizeButton", "AXFullScreenButton", "AXZoomButton"].contains(sub) {
            bad += 1; print("UNLABELED \(role) sub=\(sub) rd=\(text(attr(e, "AXRoleDescription"))) frame=\(String(describing: attr(e, "AXFrame"))) help=\(help) value=\(val) id=\(text(attr(e, "AXIdentifier")))")
        }
    }
    if let kids = attr(e, "AXChildren") as? [AXUIElement] { for k in kids { walk(k, depth + 1) } }
}
// PID=<pid> picks one copy when several are running (the installed app and a build); otherwise the first one found.
let wantPID = Int32(ProcessInfo.processInfo.environment["PID"] ?? "")
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "io.github.ol775.taskmanager" && (wantPID == nil || $0.processIdentifier == wantPID) }) else { print("not running"); exit(1) }
let ax = AXUIElementCreateApplication(app.processIdentifier)
guard let wins = attr(ax, "AXWindows") as? [AXUIElement] else { print("no windows (is Accessibility allowed for this terminal?)"); exit(1) }
for w in wins { walk(w, 0) }
print("checked \(total) interactive elements, \(bad) unlabeled")
