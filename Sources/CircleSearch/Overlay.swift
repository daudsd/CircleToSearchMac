import AppKit
import SwiftUI

/// Borderless full-screen window showing the frozen screenshot.
final class OverlayWindow: NSWindow {
    private weak var controller: CaptureController?

    init(screen: NSScreen, image: CGImage, controller: CaptureController) {
        self.controller = controller
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // Above the menu bar and Dock, but below pop-up menus so pickers still work.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = OverlayView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            image: image,
            controller: controller
        )
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        controller?.close()
    }
}

/// Draws the screenshot, the glowing lasso, and hosts the action panel.
final class OverlayView: NSView {
    private let screenshot: CGImage
    private let displayImage: NSImage
    private weak var controller: CaptureController?

    private var points: [CGPoint] = []
    private var isDrawing = false
    private var mouseDownPoint: CGPoint?
    private var trackingInPanel = false
    private var selection: CGRect?
    private var panelView: NSView?

    init(frame: NSRect, image: CGImage, controller: CaptureController) {
        self.screenshot = image
        self.displayImage = NSImage(cgImage: image, size: frame.size)
        self.controller = controller
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Mouse

    // A plain click never changes anything (so clicking inside the selection or the
    // panel keeps them open). Only a real drag starts a new circle.

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        isDrawing = false
        // Clicks on empty parts of the SwiftUI panel bubble up to us: ignore them.
        if let panelView, panelView.frame.contains(p) {
            trackingInPanel = true
            mouseDownPoint = nil
            return
        }
        trackingInPanel = false
        mouseDownPoint = p
    }

    override func mouseDragged(with event: NSEvent) {
        guard !trackingInPanel, let start = mouseDownPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        if !isDrawing {
            guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
            // A real drag: replace the old selection with a new circle.
            removePanel()
            selection = nil
            points = [start]
            isDrawing = true
            controller?.selectionStarted(in: self)
        }
        points.append(p)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownPoint = nil
            trackingInPanel = false
        }
        guard isDrawing else { return } // plain click: keep everything as is
        isDrawing = false
        let rect = boundingRect(of: points)
        // A plain click (no real drag) does nothing.
        guard rect.width > 8 || rect.height > 8 else {
            points = []
            needsDisplay = true
            return
        }
        var padded = rect.insetBy(dx: -10, dy: -10)
        // Give thin strokes (e.g. underlining a line of text) some height.
        if padded.height < 40 { padded = padded.insetBy(dx: 0, dy: -(40 - padded.height) / 2) }
        if padded.width < 40 { padded = padded.insetBy(dx: -(40 - padded.width) / 2, dy: 0) }
        padded = padded.intersection(bounds)
        selection = padded
        needsDisplay = true
        if let crop = crop(padded) {
            showPanel(for: padded, image: crop)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            controller?.close()
        } else {
            super.keyDown(with: event)
        }
    }

    func clearSelection() {
        removePanel()
        selection = nil
        points = []
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        displayImage.draw(
            in: bounds,
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )

        // Dim everything except the selection.
        let dim = NSBezierPath(rect: bounds)
        if let selection {
            dim.append(NSBezierPath(roundedRect: selection, xRadius: 14, yRadius: 14))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(selection == nil ? 0.18 : 0.45).setFill()
        dim.fill()

        if let selection {
            strokeGlow(NSBezierPath(roundedRect: selection, xRadius: 14, yRadius: 14))
        } else if points.count > 1 {
            let path = NSBezierPath()
            path.move(to: points[0])
            for p in points.dropFirst() { path.line(to: p) }
            strokeGlow(path)
        }

        if selection == nil && !isDrawing {
            drawHint()
        }
    }

    private func strokeGlow(_ path: NSBezierPath) {
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.systemTeal.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = .zero
        shadow.set()
        NSColor.systemTeal.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 7
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.setStroke()
        path.lineWidth = 2.5
        path.stroke()
    }

    private func drawHint() {
        let text = "Circle anything  ·  Esc to close" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let pill = NSRect(
            x: bounds.midX - size.width / 2 - 18,
            y: 48,
            width: size.width + 36,
            height: size.height + 16
        )
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        text.draw(at: NSPoint(x: pill.minX + 18, y: pill.minY + 8), withAttributes: attrs)
    }

    // MARK: Helpers

    private func boundingRect(of pts: [CGPoint]) -> CGRect {
        guard let first = pts.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Converts a rect in view points (top-left origin) to a pixel crop of the screenshot.
    private func crop(_ rect: CGRect) -> CGImage? {
        let sx = CGFloat(screenshot.width) / bounds.width
        let sy = CGFloat(screenshot.height) / bounds.height
        let pixelRect = CGRect(
            x: rect.minX * sx,
            y: rect.minY * sy,
            width: rect.width * sx,
            height: rect.height * sy
        ).integral
        return screenshot.cropping(to: pixelRect)
    }

    // MARK: Action panel

    private func removePanel() {
        panelView?.removeFromSuperview()
        panelView = nil
    }

    private func showPanel(for selection: CGRect, image: CGImage) {
        removePanel()
        let model = PanelModel(image: image) { [weak self] in
            self?.controller?.close()
        }
        let host = NSHostingView(rootView: ActionPanel(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        panelView = host

        let width = ActionPanel.width
        let margin: CGFloat = 16
        let gap: CGFloat = 14
        let expectedHeight: CGFloat = 380

        let x = min(max(selection.midX - width / 2, margin), bounds.width - width - margin)
        var constraints = [
            host.widthAnchor.constraint(equalToConstant: width),
            host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: x),
        ]
        if bounds.height - selection.maxY - gap >= expectedHeight {
            // Room below the selection.
            constraints.append(host.topAnchor.constraint(equalTo: topAnchor, constant: selection.maxY + gap))
        } else if selection.minY - gap >= expectedHeight {
            // Room above: grow upward from just above the selection.
            constraints.append(host.bottomAnchor.constraint(equalTo: topAnchor, constant: selection.minY - gap))
        } else {
            // Big selection: pin to the bottom of the screen.
            constraints.append(host.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -margin * 2))
        }
        NSLayoutConstraint.activate(constraints)
    }
}
