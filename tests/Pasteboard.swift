// Save or restore every item and type on the general pasteboard, so a test
// that pastes or copies leaves the user's clipboard as it found it.
//   pasteboard save <file>      pasteboard restore <file>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, ["save", "restore"].contains(arguments[1]) else {
    FileHandle.standardError.write("usage: pasteboard save|restore <file>\n".data(using: .utf8)!)
    exit(2)
}
let file = URL(fileURLWithPath: arguments[2])
let pasteboard = NSPasteboard.general
if arguments[1] == "save" {
    let items = (pasteboard.pasteboardItems ?? []).map { item -> [String: Data] in
        var types: [String: Data] = [:]
        for type in item.types { if let data = item.data(forType: type) { types[type.rawValue] = data } }
        return types
    }
    let data = try PropertyListSerialization.data(fromPropertyList: items, format: .binary, options: 0)
    try data.write(to: file, options: .atomic)
} else {
    let data = try Data(contentsOf: file)
    let items = try PropertyListSerialization.propertyList(from: data, format: nil) as! [[String: Data]]
    pasteboard.clearContents()
    let restored = items.map { types -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for (type, value) in types { item.setData(value, forType: NSPasteboard.PasteboardType(type)) }
        return item
    }
    if !restored.isEmpty && !pasteboard.writeObjects(restored) { exit(1) }
}
