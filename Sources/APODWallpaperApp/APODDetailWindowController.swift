import AppKit
import APODWallpaperCore

@MainActor
final class APODDetailWindowController: NSWindowController {
    private let apod: APOD
    private let coordinator: WallpaperCoordinator
    private let favoriteButton: NSButton

    init(apod: APOD, imageURL: URL?, coordinator: WallpaperCoordinator) {
        self.apod = apod
        self.coordinator = coordinator
        self.favoriteButton = NSButton(title: "Favorite", target: nil, action: nil)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = apod.title
        window.minSize = NSSize(width: 520, height: 420)
        super.init(window: window)
        buildView(imageURL: imageURL)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleFavorite(_ sender: Any?) {
        coordinator.setFavorite(
            for: apod.date,
            isFavorite: !coordinator.isFavorite(date: apod.date)
        )
        updateFavoriteTitle()
    }

    @objc private func openAPOD(_ sender: Any?) {
        NSWorkspace.shared.open(apod.pageURL)
    }

    private func buildView(imageURL: URL?) {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor)
        ])

        if let imageURL, let image = NSImage(contentsOf: imageURL) {
            let imageView = NSImageView(image: image)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.imageAlignment = .alignCenter
            imageView.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(imageView)
            imageView.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 360).isActive = true
        }

        let title = NSTextField(wrappingLabelWithString: apod.title)
        title.font = .boldSystemFont(ofSize: 22)
        title.maximumNumberOfLines = 0
        stack.addArrangedSubview(title)

        let date = NSTextField(labelWithString: formattedDate(apod.date))
        date.textColor = .secondaryLabelColor
        stack.addArrangedSubview(date)

        if let copyright = apod.copyright, !copyright.isEmpty {
            let credit = NSTextField(wrappingLabelWithString: copyright)
            credit.textColor = .secondaryLabelColor
            credit.maximumNumberOfLines = 0
            stack.addArrangedSubview(credit)
        }

        let explanation = NSTextField(
            wrappingLabelWithString: apod.explanation ?? "NASA did not provide an explanation for this APOD."
        )
        explanation.maximumNumberOfLines = 0
        explanation.font = .systemFont(ofSize: 14)
        stack.addArrangedSubview(explanation)
        explanation.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY
        favoriteButton.target = self
        favoriteButton.action = #selector(toggleFavorite(_:))
        buttons.addArrangedSubview(favoriteButton)

        let openButton = NSButton(title: "View APOD", target: self, action: #selector(openAPOD(_:)))
        buttons.addArrangedSubview(openButton)
        stack.addArrangedSubview(buttons)
        updateFavoriteTitle()
    }

    private func updateFavoriteTitle() {
        favoriteButton.title = coordinator.isFavorite(date: apod.date) ? "Unfavorite" : "Favorite"
    }

    private func formattedDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: "\(value)T00:00:00Z") else {
            return value
        }
        return DateFormatter.localizedString(from: date, dateStyle: .long, timeStyle: .none)
    }
}
