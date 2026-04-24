import AppKit

func makeStatusIcon(for status: AggregateStatus) -> NSImage {
    let size = NSSize(width: 16, height: 16)
    let image = NSImage(size: size, flipped: false) { rect in
        let color: NSColor
        switch status {
        case .allOnline:   color = .systemGreen
        case .someOffline: color = .systemOrange
        case .allOffline:  color = .systemRed
        }
        color.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
        return true
    }
    image.isTemplate = false
    return image
}
