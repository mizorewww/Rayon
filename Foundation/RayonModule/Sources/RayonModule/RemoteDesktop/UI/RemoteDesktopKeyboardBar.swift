//
//  RemoteDesktopKeyboardBar.swift
//  RayonModule
//
//  The bar over the iOS software keyboard on a remote desktop: the keys a
//  touch keyboard lacks. Its look and its sticky modifiers follow
//  libghostty-spm's terminal accessory bar, whose view only a terminal can
//  host.
//

#if canImport(UIKit)
    import UIKit

    @MainActor
    final class RemoteDesktopKeyboardBar: UIView {
        private weak var canvas: RemoteDesktopCanvasView?
        private let barHeight: CGFloat = 52
        private let buttonSize: CGFloat = 36
        private let effectView = UIVisualEffectView()
        private let scrollView = UIScrollView()
        private let stackView = UIStackView()
        private var modifierButtons: [(RemoteDesktopStickyModifiers.Modifier, BarButton)] = []

        /// iOS 26 floats the bar as a glass capsule clear of the keyboard.
        private static var floats: Bool {
            if #available(iOS 26, *) { true } else { false }
        }

        private static var preferredHeight: CGFloat { floats ? 60 : 52 }

        init(canvas: RemoteDesktopCanvasView) {
            self.canvas = canvas
            super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.preferredHeight))
            autoresizingMask = .flexibleWidth
            backgroundColor = .clear
            setUpViews()
            addItems()
            refresh()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { nil }

        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: Self.preferredHeight)
        }

        /// Shows which modifiers are down, and which stay down.
        func refresh() {
            for (modifier, button) in modifierButtons {
                button.show(canvas?.modifierActivation(modifier) ?? .inactive)
            }
        }

        private func setUpViews() {
            effectView.translatesAutoresizingMaskIntoConstraints = false
            effectView.clipsToBounds = true
            effectView.layer.cornerCurve = .continuous
            if #available(iOS 26, *) {
                let glass = UIGlassEffect(style: .regular)
                glass.isInteractive = true
                effectView.effect = glass
                effectView.layer.cornerRadius = barHeight / 2
            } else {
                effectView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            }
            addSubview(effectView)
            let inset: CGFloat = Self.floats ? 8 : 0
            NSLayoutConstraint.activate([
                effectView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
                effectView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
                effectView.topAnchor.constraint(equalTo: topAnchor),
                effectView.heightAnchor.constraint(equalToConstant: barHeight),
            ])

            scrollView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.alwaysBounceHorizontal = true
            effectView.contentView.addSubview(scrollView)
            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),
            ])

            stackView.translatesAutoresizingMaskIntoConstraints = false
            stackView.axis = .horizontal
            stackView.alignment = .center
            stackView.spacing = 8
            scrollView.addSubview(stackView)
            NSLayoutConstraint.activate([
                stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 10),
                stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -10),
                stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            ])
        }

        private func addItems() {
            typealias Keys = RemoteDesktopSpecialKeys
            add(key(Keys.escape, image: "escape", label: String(localized: "Escape", bundle: .module)))
            add(key(Keys.tab, image: "arrow.right.to.line", label: String(localized: "Tab", bundle: .module)))
            add(modifier(.control, image: "control", label: String(localized: "Control", bundle: .module)))
            add(modifier(.option, image: "option", label: String(localized: "Option or Alt", bundle: .module)))
            add(modifier(.command, image: "command", label: String(localized: "Command or Windows", bundle: .module)))
            add(modifier(.shift, image: "shift", label: String(localized: "Shift", bundle: .module)))
            addDivider()
            add(key(Keys.left, image: "arrowtriangle.left.fill", label: String(localized: "Left Arrow", bundle: .module)))
            add(key(Keys.up, image: "arrowtriangle.up.fill", label: String(localized: "Up Arrow", bundle: .module)))
            add(key(Keys.down, image: "arrowtriangle.down.fill", label: String(localized: "Down Arrow", bundle: .module)))
            add(key(Keys.right, image: "arrowtriangle.right.fill", label: String(localized: "Right Arrow", bundle: .module)))
            addDivider()
            add(key(Keys.home, title: String(localized: "Home", bundle: .module)))
            add(key(Keys.end, title: String(localized: "End", bundle: .module)))
            add(key(Keys.pageUp, title: String(localized: "PgUp", bundle: .module), label: String(localized: "Page Up", bundle: .module)))
            add(key(Keys.pageDown, title: String(localized: "PgDn", bundle: .module), label: String(localized: "Page Down", bundle: .module)))
            add(key(Keys.deleteForward, image: "delete.right", label: String(localized: "Forward Delete", bundle: .module)))
            addDivider()
            add(menuButton(
                image: "fn",
                label: String(localized: "Function Keys", bundle: .module),
                actions: (1 ... 12).map { n in
                    UIAction(title: "F\(n)") { [weak self] _ in self?.canvas?.sendKey(Keys.functionKey(n)) }
                }
            ))
            add(menuButton(
                image: "command.square",
                label: String(localized: "Key Combinations", bundle: .module),
                actions: Keys.combinations.map { combination in
                    UIAction(title: combination.title) { [weak self] _ in self?.canvas?.sendKeys(combination.strokes) }
                }
            ))
            addDivider()
            add(button(image: "keyboard.chevron.compact.down", label: String(localized: "Hide Keyboard", bundle: .module)) { [weak self] in
                self?.canvas?.hideKeyboard()
            })
        }

        private func add(_ view: UIView) {
            stackView.addArrangedSubview(view)
        }

        private func addDivider() {
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.backgroundColor = .secondaryLabel.withAlphaComponent(0.28)
            dot.layer.cornerRadius = 3
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 6),
                dot.heightAnchor.constraint(equalToConstant: 6),
            ])
            add(dot)
        }

        private func key(_ stroke: RemoteDesktopKeyStroke, image: String, label: String) -> BarButton {
            button(image: image, label: label) { [weak self] in self?.canvas?.sendKey(stroke) }
        }

        private func key(_ stroke: RemoteDesktopKeyStroke, title: String, label: String? = nil) -> BarButton {
            let button = BarButton(size: buttonSize) { [weak self] in self?.canvas?.sendKey(stroke) }
            var configuration = UIButton.Configuration.plain()
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
            configuration.attributedTitle = AttributedString(title, attributes: AttributeContainer([
                .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
            ]))
            button.configuration = configuration
            button.accessibilityLabel = label ?? title
            return button
        }

        private func modifier(_ modifier: RemoteDesktopStickyModifiers.Modifier, image: String, label: String) -> BarButton {
            let button = button(image: image, label: label) { [weak self] in self?.canvas?.tapModifier(modifier) }
            button.accessibilityHint = String(localized: "Holds for the next key; tap twice to keep it down", bundle: .module)
            modifierButtons.append((modifier, button))
            return button
        }

        private func menuButton(image: String, label: String, actions: [UIAction]) -> BarButton {
            let button = BarButton(size: buttonSize) {}
            button.setImage(UIImage(systemName: image), for: .normal)
            button.accessibilityLabel = label
            button.menu = UIMenu(title: label, children: actions)
            button.showsMenuAsPrimaryAction = true
            return button
        }

        private func button(image: String, label: String, action: @escaping () -> Void) -> BarButton {
            let button = BarButton(size: buttonSize, action: action)
            button.setImage(UIImage(systemName: image), for: .normal)
            button.accessibilityLabel = label
            return button
        }
    }

    /// A round key on the bar; a modifier's shows whether it is down, and a
    /// line under it when it stays down.
    private final class BarButton: UIButton {
        private let lockIndicator = UIView()

        init(size: CGFloat, action: @escaping () -> Void) {
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
            layer.cornerRadius = size / 2
            layer.cornerCurve = .continuous
            clipsToBounds = true
            NSLayoutConstraint.activate([
                widthAnchor.constraint(greaterThanOrEqualToConstant: size),
                heightAnchor.constraint(equalToConstant: size),
            ])

            lockIndicator.translatesAutoresizingMaskIntoConstraints = false
            lockIndicator.layer.cornerRadius = 1.5
            addSubview(lockIndicator)
            NSLayoutConstraint.activate([
                lockIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
                lockIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
                lockIndicator.widthAnchor.constraint(equalToConstant: 14),
                lockIndicator.heightAnchor.constraint(equalToConstant: 3),
            ])

            addAction(UIAction { _ in action() }, for: .touchUpInside)
            show(.inactive)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { nil }

        func show(_ activation: RemoteDesktopStickyModifiers.Activation) {
            let isDown = activation != .inactive
            tintColor = isDown ? .white : .label
            backgroundColor = isDown ? .systemBlue : UIColor.systemGray5.withAlphaComponent(0.92)
            configuration?.baseForegroundColor = tintColor
            lockIndicator.isHidden = activation != .locked
            lockIndicator.backgroundColor = tintColor
            accessibilityTraits = isDown ? [.button, .selected] : .button
        }
    }
#endif
