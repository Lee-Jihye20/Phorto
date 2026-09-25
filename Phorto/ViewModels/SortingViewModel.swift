import Foundation
import Photos
import SwiftData

/// A reversible action taken during this session.
///
/// Session-scoped by design: the spec allows undo only within a session, and reversing an
/// album add needs `wasAlreadyInAlbum`, which no persisted row can tell us after the fact.
enum UndoableAction: Equatable {
    case sorted(
        assetID: String,
        direction: Direction,
        albumID: String,
        albumTitle: String,
        wasAlreadyInAlbum: Bool
    )
    case trashed(assetID: String, direction: Direction)
    case skipped(assetID: String)

    var assetID: String {
        switch self {
        case let .sorted(assetID, _, _, _, _): assetID
        case let .trashed(assetID, _): assetID
        case let .skipped(assetID): assetID
        }
    }
}

/// Snapshot of a direction's destination, taken so the view layer never touches
/// SwiftData model objects directly.
struct DirectionDestination: Identifiable, Equatable, Sendable {
    let direction: Direction
    let type: DestinationType
    let albumID: String?
    let title: String

    var id: Direction { direction }
    var isTrash: Bool { type == .trash }
}

@Observable
final class SortingViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case finished
    }

    static let stackDepth = 3
    static let trashTitle = "ゴミ箱"

    private let photoService: PhotoLibraryService
    private let imageProvider: ImageProvider
    private let modelContext: ModelContext

    private(set) var loadState: LoadState = .idle
    private(set) var queue: [String] = []
    private(set) var visibleAssets: [PHAsset] = []
    private(set) var destinations: [Direction: DirectionDestination] = [:]
    private(set) var deleteQueueCount = 0
    private(set) var undoStack: [UndoableAction] = []
    private(set) var sessionTallies: [String: Int] = [:]
    var errorMessage: String?

    private var skipped: Set<String> = []
    private var cardPixelSize: CGSize = CGSize(width: 1_200, height: 1_600)

    init(
        photoService: PhotoLibraryService,
        imageProvider: ImageProvider,
        modelContext: ModelContext
    ) {
        self.photoService = photoService
        self.imageProvider = imageProvider
        self.modelContext = modelContext
    }

    // MARK: - Derived state

    var currentAsset: PHAsset? { visibleAssets.first }
    var remainingCount: Int { queue.count }
    var canUndo: Bool { !undoStack.isEmpty }
    var skippedCount: Int { skipped.count }

    var orderedDestinations: [DirectionDestination] {
        Direction.allCases.compactMap { destinations[$0] }
    }

    /// Per-album counts for the completion screen, trash last.
    var tallySummary: [(title: String, count: Int)] {
        sessionTallies
            .map { (title: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.title == Self.trashTitle { return false }
                if rhs.title == Self.trashTitle { return true }
                return lhs.count > rhs.count
            }
    }

    // MARK: - Loading

    func updateCardSize(_ size: CGSize) {
        let pixelSize = ImageProvider.cardTargetSize(for: size)
        guard pixelSize != cardPixelSize else { return }
        cardPixelSize = pixelSize
        refreshVisibleAssets()
    }

    func loadSession(config: SortSessionConfig) async {
        guard photoService.hasAnyAccess else {
            loadState = .idle
            return
        }
        loadState = .loading
        loadDestinations()
        refreshDeleteQueueCount()

        let processedIdentifiers = fetchProcessedIdentifiers()
        let scope = config.scope
        let start = config.dateRangeStart
        let end = config.dateRangeEnd
        let albumIdentifier = config.scopeAlbumIdentifier
        let order = config.sortOrder

        let identifiers = await Task.detached(priority: .userInitiated) {
            PhotoLibraryService.fetchAssetIdentifiers(
                scope: scope,
                dateRangeStart: start,
                dateRangeEnd: end,
                scopeAlbumIdentifier: albumIdentifier,
                sortOrder: order,
                excluding: processedIdentifiers
            )
        }.value

        let skippedThisSession = skipped
        queue = identifiers.filter { !skippedThisSession.contains($0) }
        refreshVisibleAssets()
        loadState = queue.isEmpty ? .finished : .ready
    }

    /// Re-runs the fetch from scratch, e.g. after settings changed the scope or order.
    func restartSession(config: SortSessionConfig) async {
        skipped = []
        undoStack = []
        sessionTallies = [:]
        await loadSession(config: config)
    }

    /// Brings skipped photos back for another pass, used by the completion screen.
    func reviewSkipped() {
        guard !skipped.isEmpty else { return }
        queue = Array(skipped) + queue
        skipped = []
        refreshVisibleAssets()
        loadState = queue.isEmpty ? .finished : .ready
    }

    func loadDestinations() {
        let assignments = (try? modelContext.fetch(FetchDescriptor<DirectionAssignment>())) ?? []
        var mapped: [Direction: DirectionDestination] = [:]
        for assignment in assignments {
            mapped[assignment.direction] = DirectionDestination(
                direction: assignment.direction,
                type: assignment.destinationType,
                albumID: assignment.albumLocalIdentifier,
                title: assignment.displayTitle
            )
        }
        destinations = mapped
    }

    // MARK: - Sorting actions

    func commit(direction: Direction) {
        guard let assetID = queue.first,
              let destination = destinations[direction]
        else { return }

        queue.removeFirst()

        switch destination.type {
        case .trash:
            modelContext.insert(DeleteQueueItem(assetLocalIdentifier: assetID))
            modelContext.insert(
                ProcessedAsset(
                    assetLocalIdentifier: assetID,
                    direction: direction,
                    destinationAlbumIdentifier: nil,
                    destinationAlbumTitle: nil,
                    wasTrash: true
                )
            )
            undoStack.append(.trashed(assetID: assetID, direction: direction))
            deleteQueueCount += 1
            addTally(Self.trashTitle)
            saveContext()

        case .album:
            guard let albumID = destination.albumID else { return }
            // Checked before the add so undo knows not to strip a pre-existing membership.
            let wasAlreadyInAlbum = photoService.isAsset(assetID, inAlbum: albumID)
            modelContext.insert(
                ProcessedAsset(
                    assetLocalIdentifier: assetID,
                    direction: direction,
                    destinationAlbumIdentifier: albumID,
                    destinationAlbumTitle: destination.title,
                    wasTrash: false
                )
            )
            undoStack.append(
                .sorted(
                    assetID: assetID,
                    direction: direction,
                    albumID: albumID,
                    albumTitle: destination.title,
                    wasAlreadyInAlbum: wasAlreadyInAlbum
                )
            )
            addTally(destination.title)
            saveContext()

            Task {
                do {
                    try await photoService.addAsset(assetID, toAlbum: albumID)
                } catch {
                    rollbackFailedSort(assetID: assetID, title: destination.title, error: error)
                }
            }
        }

        refreshVisibleAssets()
        finishIfEmpty()
    }

    func skip() {
        guard let assetID = queue.first else { return }
        queue.removeFirst()
        skipped.insert(assetID)
        undoStack.append(.skipped(assetID: assetID))
        refreshVisibleAssets()
        finishIfEmpty()
    }

    func undo() {
        guard let action = undoStack.popLast() else { return }

        switch action {
        case let .sorted(assetID, _, albumID, albumTitle, wasAlreadyInAlbum):
            deleteProcessedAsset(assetID)
            queue.insert(assetID, at: 0)
            removeTally(albumTitle)
            if !wasAlreadyInAlbum {
                Task {
                    try? await photoService.removeAsset(assetID, fromAlbum: albumID)
                }
            }

        case let .trashed(assetID, _):
            deleteProcessedAsset(assetID)
            deleteQueueItem(assetID)
            queue.insert(assetID, at: 0)
            deleteQueueCount = max(0, deleteQueueCount - 1)
            removeTally(Self.trashTitle)

        case let .skipped(assetID):
            skipped.remove(assetID)
            queue.insert(assetID, at: 0)
        }

        saveContext()
        refreshVisibleAssets()
        if loadState == .finished { loadState = .ready }
    }

    // MARK: - Delete queue

    func deleteQueueItems() -> [DeleteQueueItem] {
        let descriptor = FetchDescriptor<DeleteQueueItem>(
            sortBy: [SortDescriptor(\.queuedAt, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func deleteQueueAssets() -> [PHAsset] {
        photoService.assets(for: deleteQueueItems().map(\.assetLocalIdentifier))
    }

    /// Deletes everything in the queue with one change request, so iOS asks only once.
    func executeDeleteQueue() async throws {
        let items = deleteQueueItems()
        let identifiers = items.map(\.assetLocalIdentifier)
        guard !identifiers.isEmpty else { return }

        try await photoService.deleteAssets(identifiers)

        for item in items {
            modelContext.delete(item)
        }
        // Past this point the photos are gone from the app's reach — only the system
        // "Recently Deleted" album can bring them back, so drop their undo entries.
        let deletedIdentifiers = Set(identifiers)
        undoStack.removeAll { deletedIdentifiers.contains($0.assetID) }
        deleteQueueCount = 0
        saveContext()
    }

    /// Takes one photo back out of the trash queue and returns it to the sorting queue.
    func restoreFromDeleteQueue(assetID: String) {
        deleteQueueItem(assetID)
        deleteProcessedAsset(assetID)
        undoStack.removeAll { $0.assetID == assetID }
        if !queue.contains(assetID) {
            queue.insert(assetID, at: 0)
        }
        deleteQueueCount = max(0, deleteQueueCount - 1)
        removeTally(Self.trashTitle)
        saveContext()
        refreshVisibleAssets()
        if loadState == .finished { loadState = .ready }
    }

    func refreshDeleteQueueCount() {
        deleteQueueCount = (try? modelContext.fetchCount(FetchDescriptor<DeleteQueueItem>())) ?? 0
    }

    // MARK: - Private helpers

    private func refreshVisibleAssets() {
        let windowSize = max(Self.stackDepth, ImageProvider.lookaheadWindow)
        let windowIdentifiers = Array(queue.prefix(windowSize))
        guard !windowIdentifiers.isEmpty else {
            visibleAssets = []
            imageProvider.updateCache(for: [], targetSize: cardPixelSize)
            return
        }

        let assets = photoService.assets(for: windowIdentifiers)

        // Photos deleted outside the app still sit in the queue; drop them so the card
        // stack never shows a blank slot.
        if assets.count != windowIdentifiers.count {
            let resolved = Set(assets.map(\.localIdentifier))
            let missing = windowIdentifiers.filter { !resolved.contains($0) }
            queue.removeAll { missing.contains($0) }
            refreshVisibleAssets()
            return
        }

        visibleAssets = Array(assets.prefix(Self.stackDepth))
        imageProvider.updateCache(for: assets, targetSize: cardPixelSize)
    }

    private func finishIfEmpty() {
        if queue.isEmpty {
            loadState = .finished
            imageProvider.stopCachingAll()
        }
    }

    private func rollbackFailedSort(assetID: String, title: String, error: Error) {
        deleteProcessedAsset(assetID)
        undoStack.removeAll { $0.assetID == assetID }
        removeTally(title)
        if !queue.contains(assetID) {
            queue.insert(assetID, at: 0)
        }
        saveContext()
        refreshVisibleAssets()
        if loadState == .finished { loadState = .ready }
        errorMessage = "アルバムへの追加に失敗しました: \(error.localizedDescription)"
        HapticsService.failed()
    }

    private func fetchProcessedIdentifiers() -> Set<String> {
        let processed = (try? modelContext.fetch(FetchDescriptor<ProcessedAsset>())) ?? []
        return Set(processed.map(\.assetLocalIdentifier))
    }

    private func deleteProcessedAsset(_ assetID: String) {
        let descriptor = FetchDescriptor<ProcessedAsset>(
            predicate: #Predicate { $0.assetLocalIdentifier == assetID }
        )
        for record in (try? modelContext.fetch(descriptor)) ?? [] {
            modelContext.delete(record)
        }
    }

    private func deleteQueueItem(_ assetID: String) {
        let descriptor = FetchDescriptor<DeleteQueueItem>(
            predicate: #Predicate { $0.assetLocalIdentifier == assetID }
        )
        for item in (try? modelContext.fetch(descriptor)) ?? [] {
            modelContext.delete(item)
        }
    }

    private func addTally(_ title: String) {
        sessionTallies[title, default: 0] += 1
    }

    private func removeTally(_ title: String) {
        guard let current = sessionTallies[title] else { return }
        if current <= 1 {
            sessionTallies.removeValue(forKey: title)
        } else {
            sessionTallies[title] = current - 1
        }
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
    }
}
