import AppKit
import APODWallpaperCore

@MainActor
final class RecentWindowController: NSWindowController {
    private let coordinator: WallpaperCoordinator
    private let showDetails: (APODRecord) -> Void
    private let stackView = NSStackView()

    init(
        coordinator: WallpaperCoordinator,
        showDetails: @escaping (APODRecord) -> Void
    ) {
        self.coordinator = coordinator
        self.showDetails = showDetails

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Recent"
        window.minSize = NSSize(width: 560, height: 400)
        super.init(window: window)
        buildView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        reload()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildView() {
        guard let contentView = window?.contentView else { return }
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 12
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stackView
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor)
        ])
    }

    private func reload() {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let records = coordinator.recentRecords()
        if records.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: "No APODs have been shown yet.")
            empty.textColor = .secondaryLabelColor
            stackView.addArrangedSubview(empty)
            return
        }

        for record in records {
            stackView.addArrangedSubview(makeRow(record))
        }
    }

    private func makeRow(_ record: APODRecord) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40).isActive = true

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.image = record.cachedImagePath.flatMap(NSImage.init(contentsOf:))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 140),
            imageView.heightAnchor.constraint(equalToConstant: 90)
        ])

        let info = NSStackView()
        info.orientation = .vertical
        info.alignment = .leading
        info.spacing = 4
        info.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(info)
        info.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let title = NSTextField(wrappingLabelWithString: record.apod.title)
        title.font = .boldSystemFont(ofSize: 14)
        title.maximumNumberOfLines = 2
        info.addArrangedSubview(title)

        let date = NSTextField(labelWithString: formattedDate(record.apod.date))
        date.textColor = .secondaryLabelColor
        info.addArrangedSubview(date)

        if let lastShownAt = record.lastShownAt {
            let shown = NSTextField(labelWithString: "Last shown \(relativeDate(lastShownAt))")
            shown.textColor = .secondaryLabelColor
            info.addArrangedSubview(shown)
        }

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 6
        let setButton = actionButton(
            title: "Set Wallpaper",
            action: #selector(setWallpaper(_:)),
            date: record.apod.date
        )
        let favoriteButton = actionButton(
            title: record.isFavorite ? "Unfavorite" : "Favorite",
            action: #selector(toggleFavorite(_:)),
            date: record.apod.date
        )
        let detailsButton = actionButton(
            title: "Details",
            action: #selector(openDetails(_:)),
            date: record.apod.date
        )
        actions.addArrangedSubview(setButton)
        actions.addArrangedSubview(favoriteButton)
        actions.addArrangedSubview(detailsButton)
        info.addArrangedSubview(actions)

        let openButton = actionButton(
            title: "Open APOD",
            action: #selector(openAPOD(_:)),
            date: record.apod.date
        )
        row.addArrangedSubview(openButton)
        return container
    }

    @objc private func setWallpaper(_ sender: NSButton) {
        guard let date = sender.identifier?.rawValue else { return }
        Task { @MainActor [weak self] in
            await self?.coordinator.showAgain(date: date)
            self?.reload()
        }
    }

    @objc private func toggleFavorite(_ sender: NSButton) {
        guard let date = sender.identifier?.rawValue,
              let record = coordinator.recentRecords().first(where: { $0.apod.date == date }) else {
            return
        }
        coordinator.setFavorite(for: date, isFavorite: !record.isFavorite)
        reload()
    }

    @objc private func openDetails(_ sender: NSButton) {
        guard let date = sender.identifier?.rawValue,
              let record = coordinator.recentRecords().first(where: { $0.apod.date == date }) else {
            return
        }
        showDetails(record)
    }

    @objc private func openAPOD(_ sender: NSButton) {
        guard let date = sender.identifier?.rawValue,
              let record = coordinator.recentRecords().first(where: { $0.apod.date == date }) else {
            return
        }
        NSWorkspace.shared.open(record.apod.pageURL)
    }

    private func actionButton(title: String, action: Selector, date: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.identifier = NSUserInterfaceItemIdentifier(date)
        return button
    }

    private func formattedDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: "\(value)T00:00:00Z") else {
            return value
        }
        return DateFormatter.localizedString(from: date, dateStyle: .long, timeStyle: .none)
    }

    private func relativeDate(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
