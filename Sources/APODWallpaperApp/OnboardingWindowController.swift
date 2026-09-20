import AppKit
import APODWallpaperCore

@MainActor
final class OnboardingWindowController: NSWindowController {
    private var settings: APODSettings
    private var launchAtLogin: Bool
    private let onStart: (APODSettings, Bool) -> Void
    private let sourcePopup = NSPopUpButton()
    private let intervalPopup = NSPopUpButton()
    private let qualityButton = NSButton(checkboxWithTitle: "Use highest-resolution images", target: nil, action: nil)
    private let automaticButton = NSButton(checkboxWithTitle: "Update automatically", target: nil, action: nil)
    private let launchButton = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)

    init(
        settings: APODSettings,
        launchAtLogin: Bool,
        onStart: @escaping (APODSettings, Bool) -> Void
    ) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.onStart = onStart

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "APOD Wallpaper"
        super.init(window: window)
        buildView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func start(_ sender: Any?) {
        guard let source = WallpaperSource.allCases[safe: sourcePopup.indexOfSelectedItem],
              let interval = UpdateInterval.allCases[safe: intervalPopup.indexOfSelectedItem] else {
            return
        }
        settings.wallpaperSource = source
        settings.updateInterval = interval
        settings.preferHighestResolution = qualityButton.state == .on
        settings.automaticUpdates = automaticButton.state == .on
        launchAtLogin = launchButton.state == .on
        onStart(settings, launchAtLogin)
        close()
    }

    private func buildView() {
        guard let contentView = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -26)
        ])

        let title = NSTextField(labelWithString: "A new view of the universe on your desktop.")
        title.font = .boldSystemFont(ofSize: 18)
        stack.addArrangedSubview(title)

        let subtitle = NSTextField(
            wrappingLabelWithString: "APOD Wallpaper discovers NASA imagery for you and quietly changes your desktop over time."
        )
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 0
        stack.addArrangedSubview(subtitle)

        addPopupRow("Wallpaper source", popup: sourcePopup, titles: WallpaperSource.allCases.map(\.title), to: stack)
        addPopupRow("Change wallpaper", popup: intervalPopup, titles: UpdateInterval.allCases.map(\.title), to: stack)

        qualityButton.state = settings.preferHighestResolution ? .on : .off
        stack.addArrangedSubview(qualityButton)
        automaticButton.state = settings.automaticUpdates ? .on : .off
        stack.addArrangedSubview(automaticButton)
        launchButton.state = launchAtLogin ? .on : .off
        stack.addArrangedSubview(launchButton)

        let startButton = NSButton(title: "Start", target: self, action: #selector(start(_:)))
        startButton.keyEquivalent = "\r"
        stack.addArrangedSubview(startButton)

        sourcePopup.selectItem(at: WallpaperSource.allCases.firstIndex(of: settings.wallpaperSource) ?? 0)
        intervalPopup.selectItem(at: UpdateInterval.allCases.firstIndex(of: settings.updateInterval) ?? 0)
    }

    private func addPopupRow(
        _ label: String,
        popup: NSPopUpButton,
        titles: [String],
        to stack: NSStackView
    ) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        let labelField = NSTextField(labelWithString: label)
        labelField.alignment = .right
        labelField.widthAnchor.constraint(equalToConstant: 130).isActive = true
        popup.addItems(withTitles: titles)
        row.addArrangedSubview(labelField)
        row.addArrangedSubview(popup)
        stack.addArrangedSubview(row)
    }
}

