import AppKit
import ChargeCore

extension SettingsWindowController {
    func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, mono: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = mono ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        return field
    }

    func place(_ view: NSView, in parent: NSView, x: CGFloat = 0, y: CGFloat, width: CGFloat, height: CGFloat = 24) {
        view.frame = NSRect(x: x, y: y, width: width, height: height)
        parent.addSubview(view)
    }

    func caption(_ text: String, in page: NSView, y: CGFloat, warning: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 11)
        field.textColor = warning ? .systemOrange : .secondaryLabelColor
        place(field, in: page, y: y, width: page.bounds.width, height: 34)
        return field
    }

    func separator(in page: NSView, y: CGFloat) {
        let line = NSBox(); line.boxType = .separator
        place(line, in: page, y: y, width: page.bounds.width, height: 1)
    }

    func bind(_ control: NSControl, action: @escaping (SettingsWindowController, NSControl) -> Void) {
        control.target = self; control.action = #selector(controlChanged)
        actions[ObjectIdentifier(control)] = action
    }

    @discardableResult func button(_ title: String, in page: NSView, x: CGFloat = 0, y: CGFloat, width: CGFloat = 135,
                                  action: @escaping (SettingsWindowController, NSControl) -> Void) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        place(button, in: page, x: x, y: y, width: width, height: 28)
        bind(button, action: action)
        return button
    }

    func toggle(_ title: String, _ key: WritableKeyPath<Preferences, Bool>, in page: NSView, y: CGFloat) {
        let toggle = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        place(toggle, in: page, y: y, width: page.bounds.width)
        bind(toggle) { c, sender in c.settings.value[keyPath: key] = (sender as! NSButton).state == .on }
        bindings.append { c in toggle.state = c.settings.value[keyPath: key] ? .on : .off }
    }

    func popup(_ title: String, choices: [(String, String)], key: WritableKeyPath<Preferences, String>,
               in page: NSView, y: CGFloat, width: CGFloat = 235) {
        place(label(title), in: page, y: y + 4, width: 230)
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for (title, value) in choices { popup.addItem(withTitle: title); popup.lastItem?.representedObject = value }
        place(popup, in: page, x: page.bounds.width - width, y: y, width: width, height: 28)
        popup.setAccessibilityLabel(title)
        bind(popup) { c, sender in
            if let value = (sender as! NSPopUpButton).selectedItem?.representedObject as? String { c.settings.value[keyPath: key] = value }
        }
        bindings.append { c in
            if let item = popup.itemArray.first(where: { $0.representedObject as? String == c.settings.value[keyPath: key] }) { popup.select(item) }
        }
    }

    func slider(_ title: String, in page: NSView, y: CGFloat, range: ClosedRange<Double>, step: Double,
                value: @escaping (Preferences) -> Double, set: @escaping (inout Preferences, Double) -> Void,
                format: @escaping (Double) -> String) {
        place(label(title), in: page, y: y + 4, width: 280)
        let slider = NSSlider(value: 0, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        slider.isContinuous = true
        slider.setAccessibilityLabel(title)
        place(slider, in: page, x: 337, y: y + 2, width: 190)
        let readout = label("", size: 12, mono: true)
        readout.alignment = .right
        place(readout, in: page, x: 527, y: y + 4, width: 45)
        bind(slider) { c, sender in
            let snapped = min(range.upperBound, max(range.lowerBound, (sender.doubleValue / step).rounded() * step))
            set(&c.settings.value, snapped)
        }
        bindings.append { c in let v = value(c.settings.value); slider.doubleValue = v; readout.stringValue = format(v) }
    }
}
