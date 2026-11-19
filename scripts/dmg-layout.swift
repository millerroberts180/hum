// Lays out the Finder window of Hum's disk image: the app on the left and the
// Applications shortcut on the right, in a window just big enough for both.
//
//   swift scripts/dmg-layout.swift /Volumes/Hum
//
// scripts/release.sh --dmg-layout runs it on the read-write image, before the
// image is compressed. Finder keeps a window's layout in the folder's
// .DS_Store, a file only Finder writes, so this asks Finder to set the layout,
// with Apple Events. The first run asks whether the terminal may control
// Finder; it needs that once.
//
// The window has no background picture. Finder draws the names under the icons
// in the current appearance's text color, black in light mode and white in
// dark, and no single picture keeps both readable.
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 1, let volume = arguments.first else {
    FileHandle.standardError.write(Data("usage: swift scripts/dmg-layout.swift /Volumes/NAME\n".utf8))
    exit(64)
}
let mountPoint = URL(fileURLWithPath: volume).standardizedFileURL
// Finder finds a disk by its name, which is the folder it's mounted at.
guard mountPoint.deletingLastPathComponent().path == "/Volumes" else {
    fail("\(volume) isn't mounted in /Volumes, so Finder can't find it by name")
}
let diskName = mountPoint.lastPathComponent
let items = (app: "Hum.app", applications: "Applications")
for item in [items.app, items.applications]
where !FileManager.default.fileExists(atPath: mountPoint.appendingPathComponent(item).path) {
    fail("\(volume) has no \(item)")
}

// MARK: Layout

// In Finder's points. Bounds are the window's frame on screen, from the top
// left; positions are icon centers in the window's content.
let iconSize = 128
let windowFrame = (left: 200, top: 120, width: 600, height: 380)
let appPosition = (x: 160, y: 170)
let applicationsPosition = (x: 440, y: 170)

func quoted(_ text: String) -> String {
    "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

let script = """
tell application "Finder"
    tell disk \(quoted(diskName))
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {\(windowFrame.left), \(windowFrame.top), \
\(windowFrame.left + windowFrame.width), \(windowFrame.top + windowFrame.height)}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to \(iconSize)
        set label position of viewOptions to bottom
        set shows item info of viewOptions to false
        set position of item \(quoted(items.app)) of container window to {\(appPosition.x), \(appPosition.y)}
        set position of item \(quoted(items.applications)) of container window to \
{\(applicationsPosition.x), \(applicationsPosition.y)}
        update without registering applications
        close
        -- Reopening and closing again makes Finder write the layout out now.
        open
        delay 1
        close
    end tell
end tell
"""

guard let appleScript = NSAppleScript(source: script) else {
    fail("couldn't build the Finder script")
}
var errorInfo: NSDictionary?
appleScript.executeAndReturnError(&errorInfo)
if let errorInfo {
    let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown error"
    let number = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
    // -1743: the user (or a policy) hasn't allowed this terminal to control Finder.
    let hint = number == -1743
        ? " Allow your terminal to control Finder in System Settings › Privacy & Security › Automation, then run this again."
        : ""
    fail("Finder couldn't lay out the window (\(number)): \(message).\(hint)")
}

// Finder writes .DS_Store a moment after the window closes.
let layoutFile = mountPoint.appendingPathComponent(".DS_Store")
let deadline = Date().addingTimeInterval(10)
while !FileManager.default.fileExists(atPath: layoutFile.path) {
    if Date() > deadline {
        fail("Finder didn't save the layout to \(layoutFile.path)")
    }
    Thread.sleep(forTimeInterval: 0.2)
}
print("Laid out \(volume): \(items.app) and \(items.applications) at \(iconSize)-point icons")
