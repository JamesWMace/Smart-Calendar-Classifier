#if DEBUG
import AppKit

/// Debug builds only: saves PNGs of the app's own visible windows when another process posts
/// the "SmartCalendarClassifier.debugSnapshot" distributed notification with a directory path
/// as its object. Lets UI changes be checked without screen-recording permission (an app may
/// always draw its own views).
@MainActor
enum DebugSnapshot {
    static func install(
        closing panel: @escaping @MainActor () -> NSPanel?, trace: @escaping @MainActor () -> [String],
        close: @escaping @MainActor () -> Void
    ) {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("SmartCalendarClassifier.debugSnapshot"), object: nil, queue: .main
        ) { notification in
            let directory = notification.object as? String ?? NSTemporaryDirectory()
            MainActor.assumeIsolated {
                for (index, window) in NSApp.windows.enumerated() where window.isVisible {
                    // The whole frame view, title bar included; SwiftUI draws into layers, so
                    // render the layer tree rather than asking views to draw.
                    guard let view = window.contentView?.superview ?? window.contentView, let layer = view.layer else { continue }
                    let scale = window.backingScaleFactor
                    let size = view.bounds.size
                    guard let context = CGContext(
                        data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    ) else { continue }
                    context.scaleBy(x: scale, y: scale)
                    layer.render(in: context)
                    guard let image = context.makeImage() else { continue }
                    let name = window is NSPanel ? "panel" : "window-\(index)"
                    try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: directory).appending(path: "\(name).png"))
                }
                try? trace().joined(separator: "\n").write(
                    to: URL(fileURLWithPath: directory).appending(path: "capture.txt"), atomically: true, encoding: .utf8
                )
                if panel()?.isVisible == true { close() }
            }
        }
    }
}
#endif
