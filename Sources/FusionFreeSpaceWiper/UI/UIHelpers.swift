//
//  UIHelpers.swift
//  Fusion Free Space Wiper
//
//  AppKit building blocks + modern visual components (cards, tinted icon chips,
//  gradient-less-but-crisp filled buttons, a step indicator and a live free-space
//  block map). Everything here is available on macOS 10.15 (Catalina): CALayer
//  corner radii, NSVisualEffectView vibrancy, custom NSView drawing, tracking
//  areas for hover. No SF Symbols (11+) are used — glyphs are emoji/drawn.
//

import AppKit

// MARK: - Fixed palette (independent of the system accent colour)

enum Palette {
    static func hex(_ s: String) -> NSColor {
        var h = s; if h.hasPrefix("#") { h.removeFirst() }
        var v: UInt64 = 0; Scanner(string: h).scanHexInt64(&v)
        return NSColor(srgbRed: CGFloat((v>>16)&0xff)/255, green: CGFloat((v>>8)&0xff)/255,
                       blue: CGFloat(v&0xff)/255, alpha: 1)
    }
    static let blue   = hex("#0A72E8")
    static let blueHi = hex("#2C86F2")
    static let green  = hex("#1A8A3F")
    static let red    = hex("#C8362F")
    static let amber  = hex("#B9842A")
    static let tileOff = NSColor.quaternaryLabelColor
}

enum UI {
    static func label(_ text: String, size: CGFloat = 13, bold: Bool = false, color: NSColor = .labelColor) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = bold ? NSFont.systemFont(ofSize: size, weight: .semibold) : NSFont.systemFont(ofSize: size)
        f.textColor = color
        f.lineBreakMode = .byWordWrapping
        f.maximumNumberOfLines = 0
        f.cell?.wraps = true
        return f
    }
    static func title(_ text: String, size: CGFloat = 22) -> NSTextField {
        let f = label(text, size: size)
        f.font = NSFont.systemFont(ofSize: size, weight: .bold)
        return f
    }
    static func multiline(_ text: String, size: CGFloat = 13, color: NSColor = .secondaryLabelColor, maxWidth: CGFloat = 560) -> NSTextField {
        let f = label(text, size: size, color: color)
        f.preferredMaxLayoutWidth = maxWidth
        return f
    }
    static func vstack(_ views: [NSView], spacing: CGFloat = 12, alignment: NSLayoutConstraint.Attribute = .leading) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical; s.alignment = alignment; s.spacing = spacing
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }
    static func hstack(_ views: [NSView], spacing: CGFloat = 10, alignment: NSLayoutConstraint.Attribute = .centerY) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal; s.alignment = alignment; s.spacing = spacing
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }
    static func logView() -> (scroll: NSScrollView, text: NSTextView) {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let tv = NSTextView()
        tv.isEditable = false; tv.isRichText = false; tv.drawsBackground = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.autoresizingMask = [.width]
        scroll.documentView = tv
        return (scroll, tv)
    }
    static func appendLog(_ tv: NSTextView, _ line: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        tv.string += "[\(ts)] \(line)\n"
        tv.scrollToEndOfDocument(nil)
    }
}

/// Flipped so stacked content flows from the top inside a scroll view.
final class FlippedView: NSView { override var isFlipped: Bool { true } }

extension NSControl.StateValue { var isOn: Bool { self == .on } }

extension NSBox {
    static func separator() -> NSBox {
        let b = NSBox(); b.boxType = .separator
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }
}

// MARK: - Card

final class CardView: NSView {
    init(padding: CGFloat = 18) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.masksToBounds = false
        updateColors()
        // soft shadow
        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.10).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 10
        layer?.shadowOffset = NSSize(width: 0, height: -3)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { updateColors() }
    private func updateColors() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
    }
}

// MARK: - Icon chip (tinted rounded square with an emoji glyph)

final class IconChip: NSView {
    init(_ glyph: String, tint: NSColor, size: CGFloat = 52) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = size * 0.27
        layer?.backgroundColor = tint.withAlphaComponent(0.14).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = tint.withAlphaComponent(0.28).cgColor
        let lbl = NSTextField(labelWithString: glyph)
        lbl.font = NSFont.systemFont(ofSize: size * 0.5)
        lbl.alignment = .center
        lbl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lbl)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            lbl.centerXAnchor.constraint(equalTo: centerXAnchor),
            lbl.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Filled button with hover / press states

final class FancyButton: NSButton {
    enum Kind { case primary, green, danger, ghost }
    private let kind: Kind
    private var hovering = false

    init(_ title: String, kind: Kind = .primary, target: AnyObject?, action: Selector?) {
        self.kind = kind
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        wantsLayer = true
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        applyTitle()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func applyTitle() {
        let color: NSColor = (kind == .ghost) ? .labelColor : .white
        let p = NSMutableParagraphStyle(); p.alignment = .center
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .paragraphStyle: p,
        ])
    }

    override var intrinsicContentSize: NSSize {
        let w = attributedTitle.size().width
        return NSSize(width: ceil(w) + 40, height: 36)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        guard let l = layer else { return }
        l.cornerRadius = 10
        var fill: NSColor
        switch kind {
        case .primary: fill = Palette.blue
        case .green:   fill = Palette.green
        case .danger:  fill = Palette.red
        case .ghost:   fill = .clear
        }
        if kind == .ghost {
            l.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.0).cgColor
            l.borderWidth = 1
            l.borderColor = (hovering ? Palette.blue : NSColor.separatorColor).cgColor
        } else {
            if isHighlighted { fill = fill.blended(withFraction: 0.18, of: .black) ?? fill }
            else if hovering { fill = fill.blended(withFraction: 0.10, of: .white) ?? fill }
            l.backgroundColor = fill.cgColor
            l.borderWidth = 0
        }
    }
    override func layout() { super.layout(); needsDisplay = true }
    override var title: String { didSet { applyTitle() } }
}

// MARK: - Step indicator

final class StepIndicator: NSView {
    private let stack = UI.hstack([], spacing: 6)
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(labels: [String], active: Int) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, name) in labels.enumerated() {
            if i > 0 {
                let bar = NSView(); bar.translatesAutoresizingMaskIntoConstraints = false
                bar.wantsLayer = true; bar.layer?.backgroundColor = NSColor.separatorColor.cgColor
                bar.layer?.cornerRadius = 1
                bar.widthAnchor.constraint(equalToConstant: 16).isActive = true
                bar.heightAnchor.constraint(equalToConstant: 2).isActive = true
                stack.addArrangedSubview(bar)
            }
            let done = i < active, cur = i == active
            let dot = NSView(); dot.translatesAutoresizingMaskIntoConstraints = false
            dot.wantsLayer = true; dot.layer?.cornerRadius = 10
            dot.widthAnchor.constraint(equalToConstant: 20).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 20).isActive = true
            dot.layer?.backgroundColor = (done ? Palette.green : (cur ? Palette.blue : NSColor.controlBackgroundColor)).cgColor
            dot.layer?.borderWidth = (done || cur) ? 0 : 1.5
            dot.layer?.borderColor = NSColor.separatorColor.cgColor
            let num = NSTextField(labelWithString: done ? "✓" : "\(i+1)")
            num.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            num.textColor = (done || cur) ? .white : .secondaryLabelColor
            num.translatesAutoresizingMaskIntoConstraints = false
            dot.addSubview(num)
            NSLayoutConstraint.activate([num.centerXAnchor.constraint(equalTo: dot.centerXAnchor),
                                         num.centerYAnchor.constraint(equalTo: dot.centerYAnchor)])
            let text = UI.label(name, size: 12, bold: cur, color: cur ? .labelColor : .secondaryLabelColor)
            stack.addArrangedSubview(UI.hstack([dot, text], spacing: 6))
        }
    }
    func clear() { stack.arrangedSubviews.forEach { $0.removeFromSuperview() } }
}

// MARK: - Free-space block map (honest: blocks of free space, not physical sectors)

final class BlockMapView: NSView {
    private var fraction: CGFloat = 0        // 0..1 of writable overwritten
    private var reserveFraction: CGFloat = 0 // 0..1 of total that is reserve
    private var accent: NSColor = Palette.blue
    private let cell: CGFloat = 15
    private let gap: CGFloat = 4

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 120) }

    func configure(accent: NSColor) { self.accent = accent; needsDisplay = true }
    func update(fraction: CGFloat, reserveFraction: CGFloat) {
        self.fraction = max(0, min(1, fraction))
        self.reserveFraction = max(0, min(0.9, reserveFraction))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        guard w > cell else { return }
        let cols = max(1, Int((w + gap) / (cell + gap)))
        // Choose a row count that fills the available height nicely.
        let rows = max(4, Int((bounds.height + gap) / (cell + gap)))
        let total = cols * rows
        if total == 0 { return }

        let reserveCells = Int((CGFloat(total) * reserveFraction).rounded())
        let writable = total - reserveCells
        let doneCells = Int((CGFloat(writable) * fraction).rounded())

        for idx in 0..<total {
            let r = idx / cols, c = idx % cols
            let x = CGFloat(c) * (cell + gap)
            let y = CGFloat(r) * (cell + gap)
            let rect = NSRect(x: x, y: y, width: cell, height: cell)
            let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            let isReserve = idx >= (total - reserveCells)
            if isReserve {
                Palette.amber.withAlphaComponent(0.18).setFill(); path.fill()
                Palette.amber.withAlphaComponent(0.55).setStroke(); path.lineWidth = 1; path.stroke()
            } else if idx < doneCells {
                accent.setFill(); path.fill()
            } else if idx == doneCells {
                accent.withAlphaComponent(0.5).setFill(); path.fill()   // writing frontier
            } else {
                Palette.tileOff.withAlphaComponent(0.5).setFill(); path.fill()
            }
        }
    }
}
