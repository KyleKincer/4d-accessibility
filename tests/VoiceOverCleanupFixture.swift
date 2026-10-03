import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 150),
                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = CommandLine.arguments[1]
window.isReleasedWhenClosed = false
let label = NSTextField(labelWithString: "Owned VoiceOver cleanup fixture")
label.frame = NSRect(x: 20, y: 50, width: 360, height: 40)
window.contentView?.addSubview(label)
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
app.run()
