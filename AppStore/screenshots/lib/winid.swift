// Prints the CGWindowID of the largest on-screen window owned by the given app.
// Window number + owner name need no Screen Recording permission.
import CoreGraphics
import Foundation

let target = CommandLine.arguments.dropFirst().first ?? "Petals"

// .optionAll so a (mis)restored off-screen window is still found.
guard let list = CGWindowListCopyWindowInfo(
    [.optionAll], kCGNullWindowID
) as? [[String: Any]] else {
    exit(1)
}

var best: (id: Int, area: Double)?
for window in list {
    guard let owner = window[kCGWindowOwnerName as String] as? String, owner == target,
          let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
          let id = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double else { continue }
    // Ignore tiny transient windows; the main window is large.
    guard width >= 700, height >= 450 else { continue }
    let area = width * height
    if best == nil || area > best!.area { best = (id, area) }
}

if let best {
    print(best.id)
    exit(0)
}
exit(1)
