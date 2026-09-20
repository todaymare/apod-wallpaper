import AppKit
import APODWallpaperCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private var settings: APODSettings
    private var launchAtLogin: Bool
    private let onSettingsChanged: (APODSettings) -> Void
    private let onLaunchAtLoginChanged: (Bool) -> Void
    private let onClearCache: () -> Void
    private let sourcePopup = NSPopUpButton()
    private let intervalPopup = NSPopUpButton()
    private let nonImagePopup = NSPopUpButton()
    private let presentationPopup = NSPopUpButton()
    private let qualityButton = NSButton(checkboxWithTitle: "Prefer highest-resolution images", target: nil, action: nil)
    private let automaticButton = NSButton(checkboxWithTitle: "Update automatically", target: nil, action: nil)
    private let launchButton = NSButton(checkboxWithTitle: "Launch APOD Wallpaper at Login", target: nil, action: nil)
    private let cacheLabel = NSTextField(labelWithString: "")

    init(
        settings: APODSettings,
        launchAtLogin: Bool,
        cacheSizeBytes: Int64,
        onSettingsChanged: @escaping (APODSettings) -> Void,
        onLaunchAtLoginChanged: @escaping (Bool) -> Void,
        onClearCache: @escaping () -> Void
    ) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.onSettingsChanged = onSettingsChanged
        self.onLaunchAtLoginChanged = onLaunchAtLoginChanged

        self.onClearCache = onClearCache
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "APOD Wallpaper Settings"
        super.init(window: window)
        buildView(cacheSizeBytes: cacheSizeBytes)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func sourceChanged(_ sender: Any?) {
        guard let source = WallpaperSource.allCases[safe: sourcePopup.indexOfSelectedItem] else { return }
        settings.wallpaperSource = source
        emitSettings()
    }

    @objc private func intervalChanged(_ sender: Any?) {
        guard let interval = UpdateInterval.allCases[safe: intervalPopup.indexOfSelectedItem] else { return }
        settings.updateInterval = interval
        emitSettings()
    }

    @objc private func nonImageChanged(_ sender: Any?) {
        guard let behavior = NonImageBehavior.allCases[safe: nonImagePopup.indexOfSelectedItem] else { return }
        settings.nonImageBehavior = behavior
        emitSettings()
    }

    @objc private func presentationChanged(_ sender: Any?) {
        guard let presentation = WallpaperPresentation.allCases[safe: presentationPopup.indexOfSelectedItem] else { return }
        settings.wallpaperPresentation = presentation
        emitSettings()
    }

    @objc private func qualityChanged(_ sender: NSButton) {
        settings.preferHighestResolution = sender.state == .on
        emitSettings()
    }
    @objc private func automaticChanged(_ sender: NSButton) {
        settings.automaticUpdates = sender.state == .on
        emitSettings()
    }

    @objc private func launchChanged(_ sender: NSButton) {
        launchAtLogin = sender.state == .on
        onLaunchAtLoginChanged(launchAtLogin)
    }

    @objc private func clearCache(_ sender: Any?) {
        onClearCache()
        cacheLabel.stringValue = "Downloaded image cache cleared"
    }

    private func buildView(cacheSizeBytes: Int64) {
        guard let contentView = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24)
        ])

        stack.addArrangedSubview(sectionLabel("Wallpaper"))
        addPopupRow(
            "Source",
            popup: sourcePopup,
            titles: WallpaperSource.allCases.map(\.title),
            action: #selector(sourceChanged(_:)),
            to: stack
        )
        addPopupRow(
            "Update interval",
            popup: intervalPopup,
            titles: UpdateInterval.allCases.map(\.title),
            action: #selector(intervalChanged(_:)),
            to: stack
        )
        addPopupRow(
            "Presentation",
            popup: presentationPopup,
            titles: WallpaperPresentation.allCases.map(\.title),
            action: #selector(presentationChanged(_:)),
            to: stack
        )

        stack.addArrangedSubview(sectionLabel("APOD"))
        addPopupRow(
            "Non-image behavior",
            popup: nonImagePopup,
            titles: NonImageBehavior.allCases.map(\.title),
            action: #selector(nonImageChanged(_:)),
            to: stack
        )
        qualityButton.target = self
        qualityButton.action = #selector(qualityChanged(_:))
        qualityButton.state = settings.preferHighestResolution ? .on : .off
        stack.addArrangedSubview(qualityButton)

        stack.addArrangedSubview(sectionLabel("Application"))
        automaticButton.target = self
        automaticButton.action = #selector(automaticChanged(_:))
        automaticButton.state = settings.automaticUpdates ? .on : .off
        stack.addArrangedSubview(automaticButton)
        launchButton.target = self
        launchButton.action = #selector(launchChanged(_:))
        launchButton.state = launchAtLogin ? .on : .off
        stack.addArrangedSubview(launchButton)

        stack.addArrangedSubview(sectionLabel("Storage"))
        cacheLabel.stringValue = "Downloaded image cache: \(formattedBytes(cacheSizeBytes))"
        cacheLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(cacheLabel)
        let clearButton = NSButton(
            title: "Clear Downloaded Image Cache",
            target: self,
            action: #selector(clearCache(_:))
        )
        stack.addArrangedSubview(clearButton)

        sourcePopup.selectItem(withTitle: settings.wallpaperSource.title)
        intervalPopup.selectItem(at: UpdateInterval.allCases.firstIndex(of: settings.updateInterval) ?? 0)
        nonImagePopup.selectItem(at: NonImageBehavior.allCases.firstIndex(of: settings.nonImageBehavior) ?? 0)
        presentationPopup.selectItem(withTitle: settings.wallpaperPresentation.title)
    }

    private func addPopupRow(
        _ label: String,
        popup: NSPopUpButton,
        titles: [String],
        action: Selector,
        to stack: NSStackView
    ) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        let labelField = NSTextField(labelWithString: label)
        labelField.alignment = .right
        labelField.widthAnchor.constraint(equalToConstant: 140).isActive = true
        popup.addItems(withTitles: titles)
        popup.target = self
        popup.action = action
        row.addArrangedSubview(labelField)
        row.addArrangedSubview(popup)
        stack.addArrangedSubview(row)
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func emitSettings() {
        onSettingsChanged(settings)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

