//
//  Components2.swift
//  Fusion Free Space Wiper 2.0
//
//  Sidebar nav row + flow-step header + radio card + disk status card.
//

import AppKit

// MARK: - Sidebar nav row (§7)

final class SidebarRow: NSControl {
    private let number: Int
    private let titleText: String
    private let subtitleText: String
    private var selected = false
    private let numView = NSView()
    private let numLabel = NSTextField(labelWithString: "")
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")

    init(number: Int, title t: String, subtitle s: String, target: AnyObject?, action: Selector?) {
        self.number = number; self.titleText = t; self.subtitleText = s
        super.init(frame: .zero)
        self.target = target; self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true; layer?.cornerRadius = 10
        build()
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked)))
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func clicked() { if isEnabled { sendAction(action, to: target) } }

    private func build() {
        numView.translatesAutoresizingMaskIntoConstraints = false; numView.wantsLayer = true
        numView.layer?.cornerRadius = 13
        numLabel.stringValue = "\(number)"; numLabel.font = Ty.f(12, .bold); numLabel.alignment = .center
        numLabel.translatesAutoresizingMaskIntoConstraints = false
        numView.addSubview(numLabel)
        title.font = Ty.f(14, .semibold); title.stringValue = titleText
        subtitle.font = Ty.caption; subtitle.stringValue = subtitleText; subtitle.textColor = Tok.steel
        let textCol = UI.vstack([title, subtitle], spacing: 1)
        let row = UI.hstack([numView, textCol], spacing: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            numView.widthAnchor.constraint(equalToConstant: 26), numView.heightAnchor.constraint(equalToConstant: 26),
            numLabel.centerXAnchor.constraint(equalTo: numView.centerXAnchor), numLabel.centerYAnchor.constraint(equalTo: numView.centerYAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 9), row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
        ])
        refresh()
    }
    func setSelected(_ s: Bool) { selected = s; refresh() }
    override var isEnabled: Bool { didSet { refresh() } }
    private func refresh() {
        if selected { layer?.backgroundColor = Tok.white.cgColor; layer?.borderWidth = 1; layer?.borderColor = Tok.hairline.cgColor }
        else { layer?.backgroundColor = NSColor.clear.cgColor; layer?.borderWidth = 0 }
        let active = isEnabled
        numView.layer?.backgroundColor = (active ? (selected ? Tok.green : Tok.surfaceSoft) : Tok.surfaceSoft).cgColor
        numLabel.textColor = active ? (selected ? Tok.ink : Tok.slate) : Tok.steel
        title.textColor = active ? Tok.ink : Tok.steel
        subtitle.stringValue = active ? subtitleText : "Available after the wipe"
        subtitle.textColor = Tok.steel
    }
}

// MARK: - Flow step header (§3) — Back + step indicator, inside the content

func flowHeader(back: (title: String, target: AnyObject, action: Selector)?, steps: [String], active: Int) -> NSView {
    var left: [NSView] = []
    if let b = back { left.append(PillButton("← " + b.title, style: .link, target: b.target, action: b.action)) }
    let stepStack = UI.hstack([], spacing: 8)
    for (i, name) in steps.enumerated() {
        if i > 0 {
            let sep = NSView(); sep.translatesAutoresizingMaskIntoConstraints = false; sep.wantsLayer = true
            sep.layer?.backgroundColor = Tok.hairlineStrong.cgColor; sep.layer?.cornerRadius = 1
            sep.widthAnchor.constraint(equalToConstant: 22).isActive = true; sep.heightAnchor.constraint(equalToConstant: 2).isActive = true
            stepStack.addArrangedSubview(sep)
        }
        let done = i < active, cur = i == active
        let dot = NSView(); dot.translatesAutoresizingMaskIntoConstraints = false; dot.wantsLayer = true; dot.layer?.cornerRadius = 11
        dot.widthAnchor.constraint(equalToConstant: 22).isActive = true; dot.heightAnchor.constraint(equalToConstant: 22).isActive = true
        dot.layer?.backgroundColor = (done ? Tok.greenDark : (cur ? Tok.green : Tok.white)).cgColor
        dot.layer?.borderWidth = (done || cur) ? 0 : 1.5; dot.layer?.borderColor = Tok.hairlineStrong.cgColor
        let num = NSTextField(labelWithString: done ? "✓" : "\(i+1)"); num.font = Ty.f(11, .bold)
        num.textColor = (done ? Tok.white : (cur ? Tok.ink : Tok.steel)); num.translatesAutoresizingMaskIntoConstraints = false
        dot.addSubview(num)
        NSLayoutConstraint.activate([num.centerXAnchor.constraint(equalTo: dot.centerXAnchor), num.centerYAnchor.constraint(equalTo: dot.centerYAnchor)])
        let lab = UI.text(name, Ty.f(12, cur ? .semibold : .regular), cur ? Tok.ink : Tok.steel)
        stepStack.addArrangedSubview(UI.hstack([dot, lab], spacing: 6))
    }
    let row = UI.hstack(left + [stepStack, UI.spacer()], spacing: 16)
    return row
}

// MARK: - Radio card (§7)

final class RadioCard: NSControl {
    private let radio = NSView()
    private var selected = false
    let value: Int
    init(value: Int, title: String, desc: String, badgeView: NSView? = nil, target: AnyObject?, action: Selector?) {
        self.value = value
        super.init(frame: .zero)
        self.target = target; self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true; layer?.cornerRadius = 10
        radio.translatesAutoresizingMaskIntoConstraints = false; radio.wantsLayer = true; radio.layer?.cornerRadius = 9
        let t = UI.text(title, Ty.f(14, .semibold), Tok.ink)
        var titleRow: [NSView] = [t]; if let b = badgeView { titleRow.append(b) }
        let d = UI.text(desc, Ty.caption, Tok.steel, maxWidth: 520)
        let col = UI.vstack([UI.hstack(titleRow, spacing: 8), d], spacing: 3)
        let row = UI.hstack([radio, col], spacing: 10, alignment: .top)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            radio.widthAnchor.constraint(equalToConstant: 18), radio.heightAnchor.constraint(equalToConstant: 18),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 13), row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),
        ])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked)))
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func clicked() { sendAction(action, to: target) }
    func setSelected(_ s: Bool) { selected = s; refresh() }
    private func refresh() {
        if selected {
            layer?.backgroundColor = Tok.surfaceFeature.cgColor; layer?.borderWidth = 2; layer?.borderColor = Tok.greenDark.cgColor
            radio.layer?.backgroundColor = Tok.white.cgColor; radio.layer?.borderWidth = 5; radio.layer?.borderColor = Tok.greenDark.cgColor
        } else {
            layer?.backgroundColor = Tok.white.cgColor; layer?.borderWidth = 1; layer?.borderColor = Tok.hairlineStrong.cgColor
            radio.layer?.backgroundColor = Tok.white.cgColor; radio.layer?.borderWidth = 2; radio.layer?.borderColor = Tok.hairlineStrong.cgColor
        }
    }
}
