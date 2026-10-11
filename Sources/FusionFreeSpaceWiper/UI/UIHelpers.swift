//
//  UIHelpers.swift
//  Fusion Free Space Wiper 2.0
//
//  Design system (MongoDB tokens) + plain-AppKit components for the redesign.
//  Guardrails (per REDESIGN-SPEC §0): plain AppKit only — NSView/NSBox/NSTextField/
//  NSButton/NSStackView + custom NSView.draw for the block map, disk bar and type
//  bars. No NSVisualEffectView, no animations, no SF Symbols, no emoji. Light only
//  (Aqua forced in AppDelegate). System font is used as the allowed fallback for
//  Plus Jakarta Sans / Source Code Pro (§5 type), at the same sizes/weights.
//

import AppKit

// MARK: - Tokens (§5)

enum Tok {
    static func hex(_ s: String) -> NSColor {
        var h = s; if h.hasPrefix("#") { h.removeFirst() }
        var v: UInt64 = 0; Scanner(string: h).scanHexInt64(&v)
        return NSColor(srgbRed: CGFloat((v>>16)&0xff)/255, green: CGFloat((v>>8)&0xff)/255,
                       blue: CGFloat(v&0xff)/255, alpha: 1)
    }
    // green family
    static let green      = hex("#00ED64")   // primary buttons (ink text), tiles
    static let greenDark  = hex("#00684A")   // links, selected border, done, "No/untouched"
    static let greenSoft  = hex("#C3F0D2")   // passed/ready/recommended badge fill
    static let surfaceFeature = hex("#E3FCEF")   // selected option fill
    // teal / dark
    static let ink        = hex("#001E2B")   // body text; dark cards; readouts
    static let teal       = hex("#003D4F")   // current stage; overwrite segment; type bars
    static let hairlineDark = hex("#1C2D38")
    static let slate      = hex("#3D4F5B")   // secondary body
    static let steel      = hex("#5C6C7A")   // captions/labels/eyebrows
    static let onDarkMuted = hex("#A8B3BC")  // secondary text on dark
    // surfaces / lines
    static let hairline   = hex("#E1E5E8")
    static let hairlineStrong = hex("#C1CCD6")
    static let surface    = hex("#F9FBFA")
    static let surfaceSoft = hex("#F4F7F6")
    static let white      = NSColor.white
    // warning
    static let warningBg  = hex("#FFF8E0")
    static let warningText = hex("#946F3F")
    static let warningBody = hex("#6E522C")
    // orange
    static let orange     = hex("#FA6E39")   // irreversible action (ink text)
    static let orangeDark = hex("#B4441A")   // stop text, files-found count
}

// MARK: - Type helpers

enum Ty {
    static func f(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont { NSFont.systemFont(ofSize: size, weight: weight) }
    static let heading2 = f(32, .medium)     // tool home titles (36 in spec; 32 fits Catalina widths)
    static let heading3 = f(26, .medium)     // flow titles
    static let heading5 = f(18, .semibold)   // card titles
    static let body     = f(15, .regular)
    static let bodySmall = f(13, .regular)
    static let caption  = f(12, .regular)
    static let eyebrow  = f(11, .semibold)
    static let button   = f(14, .semibold)
    static let heroPct  = NSFont.monospacedDigitSystemFont(ofSize: 80, weight: .medium)
    static let heroETA  = NSFont.monospacedSystemFont(ofSize: 50, weight: .medium)
}

enum UI {
    static func text(_ s: String, _ font: NSFont, _ color: NSColor, lines: Int = 0, maxWidth: CGFloat = 0) -> NSTextField {
        let f = NSTextField(labelWithString: s)
        f.font = font; f.textColor = color
        f.lineBreakMode = .byWordWrapping; f.maximumNumberOfLines = lines
        if maxWidth > 0 { f.preferredMaxLayoutWidth = maxWidth }
        return f
    }
    static func eyebrow(_ s: String, color: NSColor = Tok.steel) -> NSTextField {
        let f = text(s.uppercased(), Ty.eyebrow, color)
        return f
    }
    static func heading(_ s: String) -> NSTextField { text(s, Ty.heading3, Tok.ink, lines: 0, maxWidth: 640) }
    static func homeHeading(_ s: String) -> NSTextField { text(s, Ty.heading2, Tok.ink, lines: 0, maxWidth: 640) }
    static func cardTitle(_ s: String, color: NSColor = Tok.ink) -> NSTextField { text(s, Ty.heading5, color) }
    static func body(_ s: String, color: NSColor = Tok.slate, maxWidth: CGFloat = 640) -> NSTextField { text(s, Ty.body, color, maxWidth: maxWidth) }
    static func small(_ s: String, color: NSColor = Tok.steel, maxWidth: CGFloat = 640) -> NSTextField { text(s, Ty.bodySmall, color, maxWidth: maxWidth) }
    static func caption(_ s: String, color: NSColor = Tok.steel) -> NSTextField { text(s, Ty.caption, color) }

    static func vstack(_ v: [NSView], spacing: CGFloat = 16, alignment: NSLayoutConstraint.Attribute = .leading) -> NSStackView {
        let s = NSStackView(views: v); s.orientation = .vertical; s.alignment = alignment; s.spacing = spacing
        s.translatesAutoresizingMaskIntoConstraints = false; return s
    }
    static func hstack(_ v: [NSView], spacing: CGFloat = 12, alignment: NSLayoutConstraint.Attribute = .centerY) -> NSStackView {
        let s = NSStackView(views: v); s.orientation = .horizontal; s.alignment = alignment; s.spacing = spacing
        s.translatesAutoresizingMaskIntoConstraints = false; return s
    }
    static func spacer() -> NSView { let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false; return v }

    static func logView() -> (scroll: NSScrollView, text: NSTextView) {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .noBorder; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let tv = NSTextView(); tv.isEditable = false; tv.isRichText = false; tv.drawsBackground = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular); tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.autoresizingMask = [.width]; scroll.documentView = tv
        return (scroll, tv)
    }

    // Decimal GB formatting (§6.1 — matches Finder).
    static let fileFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter(); f.countStyle = .file; f.allowedUnits = [.useGB, .useMB, .useKB]
        return f
    }()
    static func gb(_ bytes: Int64) -> String { fileFormatter.string(fromByteCount: max(0, bytes)) }
    static func mono(_ s: String, _ size: CGFloat = 13, color: NSColor = Tok.ink) -> NSTextField {
        let f = NSTextField(labelWithString: s); f.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        f.textColor = color; f.lineBreakMode = .byCharWrapping; f.maximumNumberOfLines = 0; return f
    }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }
extension NSControl.StateValue { var isOn: Bool { self == .on } }

// MARK: - Card (§7)

final class Card: NSView {
    init(dark: Bool = false, padding: CGFloat = 20, feature: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        if dark { layer?.backgroundColor = Tok.ink.cgColor; layer?.borderWidth = 0 }
        else { layer?.backgroundColor = Tok.white.cgColor; layer?.borderWidth = 1; layer?.borderColor = Tok.hairline.cgColor }
    }
    required init?(coder: NSCoder) { fatalError() }
}

func makeCard(_ content: NSView, dark: Bool = false, padding: CGFloat = 20, feature: Bool = false) -> Card {
    let c = Card(dark: dark, padding: padding, feature: feature)
    content.translatesAutoresizingMaskIntoConstraints = false
    c.addSubview(content)
    NSLayoutConstraint.activate([
        content.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: padding),
        content.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -padding),
        content.topAnchor.constraint(equalTo: c.topAnchor, constant: padding),
        content.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -padding),
    ])
    return c
}

// MARK: - Pill button (§7)

final class PillButton: NSButton {
    enum Style { case primary, secondary, orange, link, darkPrimary }
    private let st: Style
    private var hovering = false
    var compact = false

    init(_ title: String, style: Style = .primary, target: AnyObject?, action: Selector?) {
        self.st = style
        super.init(frame: .zero)
        self.title = title; self.target = target; self.action = action
        isBordered = false; bezelStyle = .regularSquare; focusRingType = .none; wantsLayer = true
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        applyTitle()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func applyTitle() {
        let color: NSColor
        switch st {
        case .primary:     color = Tok.ink           // ink text on green
        case .orange:      color = Tok.ink           // ink text on orange
        case .darkPrimary: color = Tok.white
        case .secondary:   color = Tok.ink
        case .link:        color = Tok.greenDark
        }
        let p = NSMutableParagraphStyle(); p.alignment = .center
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: isEnabled ? color : Tok.steel, .font: Ty.button, .paragraphStyle: p])
    }
    override var isEnabled: Bool { didSet { applyTitle(); needsDisplay = true } }
    override var title: String { didSet { applyTitle() } }

    override var intrinsicContentSize: NSSize {
        let w = attributedTitle.size().width
        let h: CGFloat = compact ? 40 : 44
        return NSSize(width: ceil(w) + (st == .link ? 6 : 40), height: st == .link ? 22 : h)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil))
    }
    override func mouseEntered(with e: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with e: NSEvent) { hovering = false; needsDisplay = true }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        guard let l = layer else { return }
        let h = (st == .link) ? 0 : (compact ? 40 : 44)
        l.cornerRadius = CGFloat(h) / 2
        func dim(_ c: NSColor) -> NSColor {
            if !isEnabled { return c.blended(withFraction: 0.5, of: Tok.white) ?? c }
            if isHighlighted { return c.blended(withFraction: 0.12, of: .black) ?? c }
            if hovering { return c.blended(withFraction: 0.06, of: .black) ?? c }
            return c
        }
        switch st {
        case .primary:     l.backgroundColor = dim(Tok.green).cgColor; l.borderWidth = 0
        case .orange:      l.backgroundColor = dim(Tok.orange).cgColor; l.borderWidth = 0
        case .darkPrimary: l.backgroundColor = dim(Tok.ink).cgColor; l.borderWidth = 0
        case .secondary:
            l.backgroundColor = (hovering ? Tok.surfaceSoft : Tok.white).cgColor
            l.borderWidth = 1; l.borderColor = Tok.hairlineStrong.cgColor
        case .link:
            l.backgroundColor = NSColor.clear.cgColor; l.borderWidth = 0
        }
    }
    override func layout() { super.layout(); needsDisplay = true }
}

// MARK: - Badge (§7)

func badge(_ s: String, fill: NSColor, textColor: NSColor) -> NSView {
    let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false; v.wantsLayer = true
    v.layer?.backgroundColor = fill.cgColor; v.layer?.cornerRadius = 9
    let l = UI.text(s, Ty.f(11, .semibold), textColor)
    l.translatesAutoresizingMaskIntoConstraints = false
    v.addSubview(l)
    NSLayoutConstraint.activate([
        l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 9),
        l.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -9),
        l.topAnchor.constraint(equalTo: v.topAnchor, constant: 3),
        l.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -3),
    ])
    return v
}
func badgeRecommended(_ s: String = "Recommended") -> NSView { badge(s, fill: Tok.greenSoft, textColor: Tok.greenDark) }
func badgeNeutral(_ s: String) -> NSView { badge(s, fill: Tok.surface, textColor: Tok.steel) }
func badgeWarning(_ s: String) -> NSView { badge(s, fill: Tok.warningBg, textColor: Tok.warningText) }

// MARK: - Panels (§7, §4) — no left accent bar

func limitsPanel(title: String, body: String) -> NSView {
    let t = UI.text(title, Ty.f(13, .semibold), Tok.slate)
    let b = UI.text(body, Ty.caption, Tok.steel, maxWidth: 560)
    let v = UI.vstack([t, b], spacing: 6)
    let c = makeCard(v, padding: 14)
    c.layer?.backgroundColor = Tok.surface.cgColor
    return c
}
func warningPanel(title: String, body: String) -> NSView {
    let t = UI.text(title, Ty.f(13, .semibold), Tok.warningText)
    let b = UI.text(body, Ty.caption, Tok.warningBody, maxWidth: 560)
    let v = UI.vstack([t, b], spacing: 6)
    let c = makeCard(v, padding: 14)
    c.layer?.backgroundColor = Tok.warningBg.cgColor
    c.layer?.borderColor = Tok.warningText.withAlphaComponent(0.25).cgColor
    return c
}

// MARK: - Block map (recoloured: green done, dark todo, hatched reserve)

final class BlockMapView: NSView {
    private var fraction: CGFloat = 0
    private var reserveFraction: CGFloat = 0
    private let cell: CGFloat = 14, gap: CGFloat = 4
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 108) }
    func update(fraction: CGFloat, reserveFraction: CGFloat) {
        self.fraction = max(0, min(1, fraction)); self.reserveFraction = max(0, min(0.9, reserveFraction)); needsDisplay = true
    }
    override func draw(_ r: NSRect) {
        let w = bounds.width; guard w > cell else { return }
        let cols = max(1, Int((w + gap)/(cell+gap)))
        let rows = max(4, Int((bounds.height + gap)/(cell+gap)))
        let total = cols*rows; if total == 0 { return }
        let rsv = Int((CGFloat(total)*reserveFraction).rounded())
        let writable = total - rsv
        let done = Int((CGFloat(writable)*fraction).rounded())
        for i in 0..<total {
            let c = i % cols, rr = i / cols
            let rect = NSRect(x: CGFloat(c)*(cell+gap), y: CGFloat(rr)*(cell+gap), width: cell, height: cell)
            let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            if i >= total - rsv { // reserve hatch
                Tok.onDarkMuted.withAlphaComponent(0.18).setFill(); path.fill()
                drawHatch(in: rect, color: Tok.onDarkMuted.withAlphaComponent(0.5))
            } else if i < done { Tok.green.setFill(); path.fill() }
            else { Tok.hairlineDark.setFill(); path.fill() }  // dark = still to do
        }
    }
    private func drawHatch(in rect: NSRect, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        color.setStroke(); let p = NSBezierPath(); p.lineWidth = 1
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: NSPoint(x: x, y: rect.minY)); p.line(to: NSPoint(x: x + rect.height, y: rect.maxY)); x += 4
        }
        p.stroke(); NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: - Disk bar (files | overwrite | reserve) (§4.5)

final class DiskBarView: NSView {
    private var files: CGFloat = 0.4, overwrite: CGFloat = 0.5, reserve: CGFloat = 0.1
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 26) }
    func set(filesFrac: CGFloat, overwriteFrac: CGFloat, reserveFrac: CGFloat) {
        let sum = max(0.0001, filesFrac + overwriteFrac + reserveFrac)
        files = filesFrac/sum; overwrite = overwriteFrac/sum; reserve = reserveFrac/sum; needsDisplay = true
    }
    override func draw(_ r: NSRect) {
        let w = bounds.width, h = bounds.height
        let radius: CGFloat = h/2
        let outer = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius); outer.addClip()
        var x: CGFloat = 0
        func seg(_ frac: CGFloat, _ color: NSColor, hatch: Bool = false) {
            let sw = w*frac; let rect = NSRect(x: x, y: 0, width: sw, height: h)
            color.setFill(); NSBezierPath(rect: rect).fill()
            if hatch { Tok.steel.withAlphaComponent(0.5).setStroke(); let p = NSBezierPath(); p.lineWidth = 1
                var hx = rect.minX - h; while hx < rect.maxX { p.move(to: NSPoint(x: hx, y: 0)); p.line(to: NSPoint(x: hx+h, y: h)); hx += 5 }; p.stroke() }
            x += sw
        }
        seg(files, Tok.hairlineStrong)
        seg(overwrite, Tok.teal)
        seg(reserve, Tok.surfaceSoft, hatch: true)
    }
}

// MARK: - File-type bars (§4.8)

final class TypeBarsView: NSView {
    struct Row { let label: String; let count: Int }
    private var rows: [Row] = []
    override var isFlipped: Bool { true }
    func set(_ rows: [Row]) { self.rows = rows; invalidateIntrinsicContentSize(); needsDisplay = true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: CGFloat(max(1, rows.count)) * 28) }
    override func draw(_ r: NSRect) {
        guard let maxCount = rows.map({ $0.count }).max(), maxCount > 0 else { return }
        let labelW: CGFloat = 90, countW: CGFloat = 44
        let barMaxW = max(40, bounds.width - labelW - countW - 16)
        let rowH: CGFloat = 28
        let attrs: [NSAttributedString.Key: Any] = [.font: Ty.bodySmall, .foregroundColor: Tok.slate]
        let cattrs: [NSAttributedString.Key: Any] = [.font: Ty.f(13, .semibold), .foregroundColor: Tok.ink]
        for (i, row) in rows.enumerated() {
            let y = CGFloat(i)*rowH + 4
            (row.label as NSString).draw(at: NSPoint(x: 0, y: y+2), withAttributes: attrs)
            let bw = barMaxW * CGFloat(row.count)/CGFloat(maxCount)
            let rect = NSRect(x: labelW, y: y, width: max(3, bw), height: 16)
            Tok.teal.setFill(); NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            ("\(row.count)" as NSString).draw(at: NSPoint(x: labelW + bw + 8, y: y+2), withAttributes: cattrs)
        }
    }
}

// MARK: - Stage row (§4.3 / §6.3)

final class StageRowView: NSView {
    private let stages = ["Preflight", "Overwriting", "Flush", "Verify", "Clean up"]
    private var current = 0
    private let stack = UI.hstack([], spacing: 8)
    init() { super.init(frame: .zero); translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)])
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }
    func setCurrent(_ idx: Int) { current = idx; rebuild() }
    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, name) in stages.enumerated() {
            let done = i < current, cur = i == current
            let pill = NSView(); pill.translatesAutoresizingMaskIntoConstraints = false; pill.wantsLayer = true
            pill.layer?.cornerRadius = 11
            let label = UI.text((done ? "\(name) · done" : name), Ty.f(11, .semibold), cur ? Tok.green : (done ? Tok.green : Tok.onDarkMuted))
            label.translatesAutoresizingMaskIntoConstraints = false
            pill.addSubview(label)
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -10),
                label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 4), label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -4),
                pill.heightAnchor.constraint(equalToConstant: 22)])
            if cur { pill.layer?.backgroundColor = Tok.teal.cgColor; pill.layer?.borderWidth = 1; pill.layer?.borderColor = Tok.green.cgColor }
            else if done { pill.layer?.backgroundColor = NSColor.clear.cgColor }
            else { pill.layer?.backgroundColor = NSColor.clear.cgColor; pill.layer?.borderWidth = 1; pill.layer?.borderColor = Tok.hairlineDark.cgColor }
            stack.addArrangedSubview(pill)
        }
    }
}
