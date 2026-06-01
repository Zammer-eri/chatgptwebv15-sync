//
//  ShellLegacyDownloadsManagerView.swift
//  Reynard
//
//  Shell-only copy of the compact downloads UI from 62415178.
//

import MobileCoreServices
import QuickLook
import QuickLookThumbnailing
import UIKit
import UniformTypeIdentifiers

final class ShellLegacyDownloadsManagerView: UIView, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, UIGestureRecognizerDelegate, QLPreviewControllerDataSource, UIDocumentInteractionControllerDelegate {
    private struct Section {
        let title: String
        let items: [DownloadItemSnapshot]
    }

    private struct SectionSignature: Equatable {
        let title: String
        let itemIDs: [UUID]
    }

    private lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = "Search Downloads"
        searchBar.delegate = self
        return searchBar
    }()

    private let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()

    private lazy var tableView: UITableView = {
        let view = UITableView(frame: .zero, style: .plain)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemBackground
        view.dataSource = self
        view.delegate = self
        view.rowHeight = 58
        view.estimatedRowHeight = 58
        view.separatorInset = UIEdgeInsets(top: 0, left: 58, bottom: 0, right: 0)
        if #available(iOS 15.0, *) {
            view.sectionHeaderTopPadding = 0
        }
        view.register(ShellLegacyDownloadItemCell.self, forCellReuseIdentifier: ShellLegacyDownloadItemCell.reuseIdentifier)
        return view
    }()

    private let emptyStateView = ShellLegacyEmptyDownloadsBackgroundView()
    private var sections: [Section] = []
    private var notificationToken: NSObjectProtocol?
    private var isShowingSwipeActions = false
    private var currentSearchTerm = ""
    private var hasStoredDownloads = false
    private var previewFileURL: URL?
    private var documentInteractionController: UIDocumentInteractionController?

    override init(frame: CGRect) {
        super.init(frame: frame)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .secondarySystemBackground
        addSubview(tableView)
        setupHeaderView()

        notificationToken = NotificationCenter.default.addObserver(
            forName: .downloadStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadDownloads()
        }

        reloadDownloads()

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        tableView.addGestureRecognizer(tapGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateHeaderSizeIfNeeded()
        tableView.backgroundView?.frame = tableView.bounds
    }

    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
    }

    private func reloadDownloads() {
        let snapshot = DownloadStore.shared.snapshot()
        hasStoredDownloads = !snapshot.items.isEmpty
        updateSearchBarVisibility()

        let updatedSections = makeSections(from: filteredItems(from: snapshot.items))
        let previousSections = sections
        let shouldReloadTable = sectionSignatures(for: previousSections) != sectionSignatures(for: updatedSections)

        sections = updatedSections
        updateBackgroundView()

        if isShowingSwipeActions {
            if shouldReloadTable {
                isShowingSwipeActions = false
                tableView.setEditing(false, animated: false)
                tableView.reloadData()
            } else {
                refreshVisibleCells(previousSections: previousSections)
            }
            return
        }

        if shouldReloadTable {
            tableView.reloadData()
            return
        }

        refreshVisibleCells(previousSections: previousSections)
    }

    private func setupHeaderView() {
        headerContainerView.layoutMargins = tableView.layoutMargins
        headerContainerView.addSubview(searchBar)
        searchBar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: headerContainerView.layoutMarginsGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: headerContainerView.layoutMarginsGuide.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: headerContainerView.layoutMarginsGuide.trailingAnchor),
            searchBar.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
        ])

        let targetWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        headerContainerView.frame = CGRect(x: 0, y: 0, width: targetWidth, height: 0)
        updateHeaderFittingHeight()
    }

    private func updateSearchBarVisibility() {
        if hasStoredDownloads {
            if tableView.tableHeaderView !== headerContainerView {
                tableView.tableHeaderView = headerContainerView
                updateHeaderSizeIfNeeded()
            }
            return
        }

        if tableView.tableHeaderView != nil {
            tableView.tableHeaderView = nil
        }
    }

    @objc private func handleBackgroundTap() {
        searchBar.resignFirstResponder()
    }

    private func updateHeaderFittingHeight() {
        headerContainerView.setNeedsLayout()
        headerContainerView.layoutIfNeeded()

        let targetSize = CGSize(width: headerContainerView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let height = headerContainerView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        var frame = headerContainerView.frame
        if frame.height != height {
            frame.size.height = height
            headerContainerView.frame = frame
            tableView.tableHeaderView = headerContainerView
        }
    }

    private func updateHeaderSizeIfNeeded() {
        let targetWidth = tableView.bounds.width
        guard targetWidth > 0 else {
            return
        }

        var frame = headerContainerView.frame
        guard frame.width != targetWidth else {
            return
        }

        frame.size.width = targetWidth
        headerContainerView.frame = frame
        updateHeaderFittingHeight()
    }

    private func filteredItems(from items: [DownloadItemSnapshot]) -> [DownloadItemSnapshot] {
        let normalizedTerm = currentSearchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTerm.isEmpty else {
            return items
        }

        return items.filter { $0.fileName.localizedCaseInsensitiveContains(normalizedTerm) }
    }

    private func performSearch(term: String, preserveFocusOnClear: Bool = false) {
        let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedTerm.isEmpty {
            currentSearchTerm = ""
            reloadDownloads()
            if preserveFocusOnClear {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.searchBar.window != nil else {
                        return
                    }

                    self.searchBar.becomeFirstResponder()
                }
            }
            return
        }

        currentSearchTerm = normalizedTerm
        reloadDownloads()
    }

    private func updateBackgroundView() {
        emptyStateView.message = currentSearchTerm.isEmpty ? "Files you download appear here" : "No matching downloads"
        tableView.backgroundView = sections.isEmpty ? emptyStateView : nil
    }

    private func refreshVisibleCells(previousSections: [Section]) {
        let visibleIndexPaths = changedVisibleIndexPaths(previousSections: previousSections)
        guard !visibleIndexPaths.isEmpty else {
            return
        }

        for indexPath in visibleIndexPaths {
            guard let item = item(at: indexPath),
                  let cell = tableView.cellForRow(at: indexPath) as? ShellLegacyDownloadItemCell else {
                continue
            }

            cell.apply(item: item)
        }
    }

    private func changedVisibleIndexPaths(previousSections: [Section]) -> [IndexPath] {
        (tableView.indexPathsForVisibleRows ?? []).filter { indexPath in
            guard let previousItem = item(at: indexPath, in: previousSections),
                  let currentItem = item(at: indexPath, in: sections) else {
                return false
            }

            return !itemsAreDisplayEquivalent(previousItem, currentItem)
        }
    }

    private func makeSections(from items: [DownloadItemSnapshot]) -> [Section] {
        guard !items.isEmpty else {
            return []
        }

        var todayItems: [DownloadItemSnapshot] = []
        var yesterdayItems: [DownloadItemSnapshot] = []
        var previousSevenDayItems: [DownloadItemSnapshot] = []
        var previousThirtyDayItems: [DownloadItemSnapshot] = []
        var monthlyItems: [DateComponents: [DownloadItemSnapshot]] = [:]
        let calendar = Calendar.current
        let now = Date()

        for item in items {
            let startOfItemDay = calendar.startOfDay(for: item.addedAt)
            let startOfToday = calendar.startOfDay(for: now)
            let dayDifference = calendar.dateComponents([.day], from: startOfItemDay, to: startOfToday).day ?? 0

            switch dayDifference {
            case Int.min..<1:
                todayItems.append(item)
            case 1:
                yesterdayItems.append(item)
            case 2...7:
                previousSevenDayItems.append(item)
            case 8...30:
                previousThirtyDayItems.append(item)
            default:
                let components = calendar.dateComponents([.year, .month], from: item.addedAt)
                monthlyItems[components, default: []].append(item)
            }
        }

        var resolvedSections: [Section] = []
        if !todayItems.isEmpty {
            resolvedSections.append(Section(title: "Today", items: todayItems))
        }
        if !yesterdayItems.isEmpty {
            resolvedSections.append(Section(title: "Yesterday", items: yesterdayItems))
        }
        if !previousSevenDayItems.isEmpty {
            resolvedSections.append(Section(title: "Previous 7 Days", items: previousSevenDayItems))
        }
        if !previousThirtyDayItems.isEmpty {
            resolvedSections.append(Section(title: "Previous 30 Days", items: previousThirtyDayItems))
        }

        let currentYear = calendar.component(.year, from: now)
        let sortedMonthComponents = monthlyItems.keys.sorted { lhs, rhs in
            let leftYear = lhs.year ?? 0
            let rightYear = rhs.year ?? 0
            if leftYear != rightYear {
                return leftYear > rightYear
            }

            return (lhs.month ?? 0) > (rhs.month ?? 0)
        }

        for components in sortedMonthComponents {
            guard let year = components.year,
                  let month = components.month,
                  let items = monthlyItems[components],
                  let titleDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
                continue
            }

            let title = year == currentYear ? shellLegacyMonthTitleFormatter.string(from: titleDate) : shellLegacyMonthYearTitleFormatter.string(from: titleDate)
            resolvedSections.append(Section(title: title, items: items))
        }

        return resolvedSections
    }

    private func sectionSignatures(for sections: [Section]) -> [SectionSignature] {
        sections.map { section in
            SectionSignature(title: section.title, itemIDs: section.items.map(\.id))
        }
    }

    private func item(at indexPath: IndexPath, in sections: [Section]? = nil) -> DownloadItemSnapshot? {
        let resolvedSections = sections ?? self.sections
        guard indexPath.section < resolvedSections.count,
              indexPath.row < resolvedSections[indexPath.section].items.count else {
            return nil
        }

        return resolvedSections[indexPath.section].items[indexPath.row]
    }

    private func itemsAreDisplayEquivalent(_ lhs: DownloadItemSnapshot, _ rhs: DownloadItemSnapshot) -> Bool {
        lhs.id == rhs.id &&
        lhs.fileName == rhs.fileName &&
        lhs.fileURL == rhs.fileURL &&
        lhs.state == rhs.state &&
        lhs.totalBytes == rhs.totalBytes &&
        lhs.downloadedBytes == rhs.downloadedBytes &&
        lhs.bytesPerSecond == rhs.bytesPerSecond
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ShellLegacyDownloadItemCell.reuseIdentifier,
            for: indexPath
        ) as? ShellLegacyDownloadItemCell,
              let item = item(at: indexPath) else {
            return UITableViewCell()
        }

        cell.apply(item: item)
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabel
        label.text = sections[section].title

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
        ])

        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        24
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let item = item(at: indexPath) else {
            return nil
        }

        switch item.state {
        case .downloading:
            let cancelAction = UIContextualAction(style: .destructive, title: "Cancel") { [weak self] _, _, completion in
                self?.presentCancellationConfirmation(for: item, completion: completion)
            }
            let configuration = UISwipeActionsConfiguration(actions: [cancelAction])
            configuration.performsFirstActionWithFullSwipe = false
            return configuration

        case .completed:
            let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
                DownloadStore.shared.deleteDownloadedItem(id: item.id)
                completion(true)
            }

            let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
            configuration.performsFirstActionWithFullSwipe = true
            return configuration
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = item(at: indexPath) else {
            return
        }

        tableView.deselectRow(at: indexPath, animated: true)

        guard item.state == .completed else {
            return
        }

        openFile(item, from: indexPath)
    }

    func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {
        isShowingSwipeActions = true
    }

    func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
        isShowingSwipeActions = false
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let preserveFocusOnClear = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && searchBar.isFirstResponder
        performSearch(term: searchText, preserveFocusOnClear: preserveFocusOnClear)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer.view === tableView else {
            return true
        }

        var view = touch.view
        while let currentView = view {
            if currentView === searchBar {
                return false
            }
            view = currentView.superview
        }

        return true
    }

    private func presentCancellationConfirmation(
        for item: DownloadItemSnapshot,
        completion: @escaping (Bool) -> Void
    ) {
        guard let viewController = nearestViewController else {
            DownloadStore.shared.cancelDownload(id: item.id)
            completion(true)
            return
        }

        let alert = UIAlertController(
            title: "Cancel Download?",
            message: "Do you want to stop downloading \(item.fileName)?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Keep Downloading", style: .cancel) { _ in
            completion(false)
        })
        alert.addAction(UIAlertAction(title: "Cancel Download", style: .destructive) { _ in
            DownloadStore.shared.cancelDownload(id: item.id)
            completion(true)
        })
        viewController.present(alert, animated: true)
    }

    private func openFile(_ item: DownloadItemSnapshot, from indexPath: IndexPath) {
        guard let fileURL = item.fileURL,
              let viewController = nearestViewController else {
            return
        }

        guard QLPreviewController.canPreview(fileURL as QLPreviewItem) else {
            presentOpenInMenu(for: fileURL, from: indexPath)
            return
        }

        previewFileURL = fileURL
        let previewController = QLPreviewController()
        previewController.dataSource = self
        viewController.present(previewController, animated: true)
    }

    private func presentOpenInMenu(for fileURL: URL, from indexPath: IndexPath) {
        guard nearestViewController != nil else {
            return
        }

        let controller = UIDocumentInteractionController(url: fileURL)
        controller.delegate = self
        documentInteractionController = controller
        controller.presentOpenInMenu(from: tableView.rectForRow(at: indexPath), in: tableView, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        previewFileURL == nil ? 0 : 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        previewFileURL! as QLPreviewItem
    }

    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        nearestViewController ?? UIViewController()
    }

    private var nearestViewController: UIViewController? {
        sequence(first: next, next: { $0?.next }).first { $0 is UIViewController } as? UIViewController
    }
}

private final class ShellLegacyDownloadItemCell: UITableViewCell {
    static let reuseIdentifier = "ShellLegacyDownloadItemCell"

    private static let sizeNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private let iconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = .label
        view.layer.cornerRadius = 6
        view.clipsToBounds = true
        return view
    }()

    private let fileNameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .label
        label.numberOfLines = 1
        return label
    }()

    private let detailsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        return label
    }()

    private let progressView: UIProgressView = {
        let view = UIProgressView(progressViewStyle: .default)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.trackTintColor = .tertiarySystemFill
        view.progressTintColor = .label
        view.isHidden = true
        return view
    }()

    private var representedFileURL: URL?
    private var representedItemID: UUID?
    private var lastDetailsLabelUpdateTime: TimeInterval = 0

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        backgroundColor = .secondarySystemBackground
        contentView.backgroundColor = .secondarySystemBackground
        layoutMargins = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)

        let labelsStack = UIStackView(arrangedSubviews: [fileNameLabel, detailsLabel, progressView])
        labelsStack.translatesAutoresizingMaskIntoConstraints = false
        labelsStack.axis = .vertical
        labelsStack.alignment = .fill
        labelsStack.spacing = 2

        contentView.addSubview(iconView)
        contentView.addSubview(labelsStack)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 6),
            iconView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -6),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            labelsStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            labelsStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            labelsStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labelsStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 8),
            labelsStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),
        ])

        separatorInset.left = 58
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.layoutIfNeeded()
        let guideFrameInContent = contentView.layoutMarginsGuide.layoutFrame
        let guideFrameInCell = convert(guideFrameInContent, from: contentView)
        let rightInset = bounds.width - guideFrameInCell.maxX
        separatorInset = UIEdgeInsets(
            top: separatorInset.top,
            left: separatorInset.left,
            bottom: separatorInset.bottom,
            right: rightInset
        )
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedFileURL = nil
        representedItemID = nil
        lastDetailsLabelUpdateTime = 0
        iconView.image = nil
        iconView.transform = .identity
        iconView.tintColor = .label
    }

    func apply(item: DownloadItemSnapshot) {
        fileNameLabel.text = item.fileName

        switch item.state {
        case .downloading:
            representedFileURL = nil
            let previousItemID = representedItemID
            representedItemID = item.id
            let downloadedText = Self.formattedByteCount(item.downloadedBytes)
            let sizeText = item.totalBytes.map { Self.formattedByteCount($0) }
            let speedText: String?
            if item.bytesPerSecond > 0 {
                speedText = "\(Self.formattedByteCount(item.bytesPerSecond))/sec"
            } else {
                speedText = nil
            }

            var detailsText = downloadedText
            if let sizeText {
                detailsText += " of \(sizeText)"
            }
            if let speedText {
                detailsText += " (\(speedText))"
            }

            let now = ProcessInfo.processInfo.systemUptime
            if previousItemID != item.id || now - lastDetailsLabelUpdateTime >= 0.5 || detailsLabel.text == nil {
                detailsLabel.text = detailsText
                lastDetailsLabelUpdateTime = now
            }
            progressView.isHidden = false
            if let totalBytes = item.totalBytes, totalBytes > 0 {
                progressView.progress = min(max(Float(item.downloadedBytes) / Float(totalBytes), 0), 1)
            } else {
                progressView.progress = 0
            }
            let placeholderIcon = ShellLegacyDownloadFileIconProvider.shared.genericPlaceholderIcon()
            iconView.image = placeholderIcon
            iconView.transform = .identity
            iconView.tintColor = placeholderIcon == nil ? .label : nil

        case .completed:
            representedItemID = item.id
            lastDetailsLabelUpdateTime = 0
            detailsLabel.text = item.totalBytes.map { Self.formattedByteCount($0) } ?? "Unknown size"
            progressView.isHidden = true
            progressView.progress = 0
            iconView.transform = .identity
            iconView.tintColor = nil
            representedFileURL = item.fileURL
            iconView.image = item.fileURL.flatMap { ShellLegacyDownloadFileIconProvider.shared.cachedIcon(for: $0) } ?? ShellLegacyDownloadFileIconProvider.shared.genericPlaceholderIcon()

            guard let fileURL = item.fileURL else {
                return
            }

            let expectedItemID = item.id
            ShellLegacyDownloadFileIconProvider.shared.icon(for: fileURL, size: CGSize(width: 40, height: 40)) { [weak self] image in
                guard let self,
                      self.representedFileURL == fileURL,
                      self.representedItemID == expectedItemID else {
                    return
                }

                if let image {
                    self.iconView.image = image
                } else {
                    self.iconView.image = ShellLegacyDownloadFileIconProvider.shared.placeholderIcon(for: fileURL) ?? ShellLegacyDownloadFileIconProvider.shared.genericPlaceholderIcon()
                }
            }
        }
    }

    private static func formattedByteCount(_ byteCount: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        var value = Double(abs(byteCount))
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            let bytesText = Int64(value)
            return "\(byteCount < 0 ? -bytesText : bytesText) \(units[unitIndex])"
        }

        let formattedValue = sizeNumberFormatter.string(from: NSNumber(value: byteCount < 0 ? -value : value)) ?? String(format: "%.1f", byteCount < 0 ? -value : value)
        return "\(formattedValue) \(units[unitIndex])"
    }
}

private final class ShellLegacyDownloadFileIconProvider {
    static let shared = ShellLegacyDownloadFileIconProvider()

    private let generator = QLThumbnailGenerator.shared
    private let cache = NSCache<NSURL, UIImage>()
    private let genericCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default

    func placeholderIcon(for fileURL: URL) -> UIImage? {
        placeholderIcon(fileName: fileURL.lastPathComponent, mimeType: nil)
    }

    func placeholderIcon(fileName: String, mimeType: String?) -> UIImage? {
        let cacheKey = placeholderCacheKey(fileName: fileName, mimeType: mimeType)
        if let cachedImage = genericCache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let placeholderURL = placeholderURL(fileName: fileName, mimeType: mimeType),
              let image = documentInteractionIcon(for: placeholderURL) else {
            return nil
        }

        genericCache.setObject(image, forKey: cacheKey)
        return image
    }

    func genericPlaceholderIcon() -> UIImage? {
        let cacheKey: NSString = "generic"
        if let cachedImage = genericCache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let placeholderURL = placeholderURL(fileName: "generic-file", mimeType: nil),
              let image = documentInteractionIcon(
                for: placeholderURL,
                uti: kUTTypeData as String,
                name: "Downloading"
              ) else {
            return nil
        }

        genericCache.setObject(image, forKey: cacheKey)
        return image
    }

    func icon(for fileURL: URL, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        if let cachedImage = cache.object(forKey: fileURL as NSURL) {
            completion(cachedImage)
            return
        }

        generateIcon(for: fileURL, size: size, contentTypeIdentifier: nil) { [weak self] image in
            if let image {
                self?.cache.setObject(image, forKey: fileURL as NSURL)
                completion(image)
                return
            }

            self?.genericIcon(for: fileURL, size: size, completion: completion)
        }
    }

    func cachedIcon(for fileURL: URL) -> UIImage? {
        cache.object(forKey: fileURL as NSURL)
    }

    private func generateIcon(
        for fileURL: URL,
        size: CGSize,
        contentTypeIdentifier: String?,
        representationTypes: QLThumbnailGenerator.Request.RepresentationTypes = .all,
        completion: @escaping (UIImage?) -> Void
    ) {
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: size,
            scale: UIScreen.main.scale,
            representationTypes: representationTypes
        )
        request.iconMode = true
        if #available(iOS 14.0, *),
           let contentTypeIdentifier,
           let contentType = UTType(contentTypeIdentifier) {
            request.contentType = contentType
        }

        generator.generateBestRepresentation(for: request) { thumbnail, _ in
            DispatchQueue.main.async {
                completion(thumbnail?.uiImage)
            }
        }
    }

    private func genericIcon(for fileURL: URL, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        let fileName = fileURL.lastPathComponent
        let cacheKey = placeholderCacheKey(fileName: fileName, mimeType: nil)
        if let cachedImage = genericCache.object(forKey: cacheKey) {
            completion(cachedImage)
            return
        }

        guard let placeholderURL = placeholderURL(fileName: fileName, mimeType: nil) else {
            completion(nil)
            return
        }

        generateIcon(
            for: placeholderURL,
            size: size,
            contentTypeIdentifier: resolvedContentTypeIdentifier(fileName: fileName, mimeType: nil),
            representationTypes: .icon
        ) { [weak self] image in
            let resolvedImage = image ?? self?.documentInteractionIcon(for: placeholderURL)
            if let resolvedImage {
                self?.genericCache.setObject(resolvedImage, forKey: cacheKey)
            }
            completion(resolvedImage)
        }
    }

    private func placeholderURL(fileName: String, mimeType: String?) -> URL? {
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let placeholderDirectory = cachesDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("IconPlaceholders", isDirectory: true)

        do {
            try fileManager.createDirectory(at: placeholderDirectory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let contentTypeIdentifier = resolvedContentTypeIdentifier(fileName: fileName, mimeType: mimeType)
        let existingExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let preferredExtension = existingExtension.isEmpty
        ? (preferredFilenameExtension(from: contentTypeIdentifier) ?? "")
        : existingExtension
        let placeholderName = preferredExtension.isEmpty ? "generic-file" : "generic-file.\(preferredExtension)"
        let placeholderURL = placeholderDirectory.appendingPathComponent(placeholderName)

        if !fileManager.fileExists(atPath: placeholderURL.path) {
            fileManager.createFile(atPath: placeholderURL.path, contents: Data())
        }

        return placeholderURL
    }

    private func placeholderCacheKey(fileName: String, mimeType: String?) -> NSString {
        let pathExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        if !pathExtension.isEmpty {
            return pathExtension as NSString
        }
        if let mimeType, !mimeType.isEmpty {
            return mimeType.lowercased() as NSString
        }
        return "generic"
    }

    private func resolvedContentTypeIdentifier(fileName: String, mimeType: String?) -> String? {
        if let mimeType {
            if let uti = UTTypeCreatePreferredIdentifierForTag(
                kUTTagClassMIMEType,
                mimeType as CFString,
                nil
            )?.takeRetainedValue() {
                return uti as String
            }
        }

        let pathExtension = URL(fileURLWithPath: fileName).pathExtension
        guard !pathExtension.isEmpty else {
            return nil
        }

        return UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassFilenameExtension,
            pathExtension as CFString,
            nil
        )?.takeRetainedValue() as String?
    }

    private func preferredFilenameExtension(from contentTypeIdentifier: String?) -> String? {
        guard let contentTypeIdentifier else {
            return nil
        }
        return UTTypeCopyPreferredTagWithClass(
            contentTypeIdentifier as CFString,
            kUTTagClassFilenameExtension
        )?.takeRetainedValue() as String?
    }

    private func documentInteractionIcon(for fileURL: URL, uti: String? = nil, name: String? = nil) -> UIImage? {
        let controller = UIDocumentInteractionController(url: fileURL)
        controller.uti = uti
        controller.name = name

        return preferredDocumentInteractionIcon(from: controller.icons)
    }

    private func preferredDocumentInteractionIcon(from icons: [UIImage]) -> UIImage? {
        icons.last
    }
}

private let shellLegacyMonthTitleFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("MMMM")
    return formatter
}()

private let shellLegacyMonthYearTitleFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
    return formatter
}()

private final class ShellLegacyEmptyDownloadsBackgroundView: UIView {
    private let label: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "Files you download appear here"
        return label
    }()

    var message: String? {
        get {
            label.text
        }
        set {
            label.text = newValue
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(label)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let maxWidth = max(bounds.width - 48, 0)
        let fittingSize = CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
        let labelSize = label.sizeThatFits(fittingSize)
        label.frame = CGRect(
            x: (bounds.width - min(labelSize.width, maxWidth)) / 2,
            y: (bounds.height - labelSize.height) / 2,
            width: min(labelSize.width, maxWidth),
            height: labelSize.height
        ).integral
    }
}
