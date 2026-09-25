import Foundation
import SwiftData

@Observable
final class OnboardingViewModel {
    enum Step: Int, CaseIterable {
        case directions
        case scope
        case order

        var title: String {
            switch self {
            case .directions: "方向の割り当て"
            case .scope: "仕分けの対象"
            case .order: "表示順"
            }
        }
    }

    var step: Step = .directions
    var draft: [Direction: DirectionDestination] = [:]
    var scope: ScopeType = .all
    var sortOrder: PhotoSortOrder = .newest
    var dateRangeStart: Date = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
    var dateRangeEnd: Date = .now
    var scopeAlbum: AlbumInfo?
    var errorMessage: String?

    // MARK: - Validation

    /// Album IDs already spoken for, so the picker can grey them out.
    func takenAlbumIDs(excluding direction: Direction) -> Set<String> {
        Set(
            draft
                .filter { $0.key != direction }
                .compactMap { $0.value.albumID }
        )
    }

    func isTrashTaken(excluding direction: Direction) -> Bool {
        draft.contains { $0.key != direction && $0.value.isTrash }
    }

    var isDirectionStepValid: Bool {
        Direction.allCases.allSatisfy { draft[$0] != nil }
    }

    var isScopeStepValid: Bool {
        switch scope {
        case .all, .excludeScreenshots:
            return true
        case .dateRange:
            return dateRangeStart <= dateRangeEnd
        case .specificAlbum:
            return scopeAlbum != nil
        }
    }

    var canAdvance: Bool {
        switch step {
        case .directions: isDirectionStepValid
        case .scope: isScopeStepValid
        case .order: true
        }
    }

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    // MARK: - Persisting

    func persist(config: SortSessionConfig, context: ModelContext) {
        // Replace any previous assignments rather than merging, so a re-run of onboarding
        // (or a settings change) cannot leave a stale direction behind.
        let existing = (try? context.fetch(FetchDescriptor<DirectionAssignment>())) ?? []
        for assignment in existing {
            context.delete(assignment)
        }

        for direction in Direction.allCases {
            guard let destination = draft[direction] else { continue }
            context.insert(
                DirectionAssignment(
                    direction: direction,
                    destinationType: destination.type,
                    albumLocalIdentifier: destination.albumID,
                    albumTitle: destination.title
                )
            )
        }

        config.scope = scope
        config.sortOrder = sortOrder
        config.dateRangeStart = scope == .dateRange ? dateRangeStart : nil
        config.dateRangeEnd = scope == .dateRange ? dateRangeEnd : nil
        config.scopeAlbumIdentifier = scope == .specificAlbum ? scopeAlbum?.id : nil
        config.scopeAlbumTitle = scope == .specificAlbum ? scopeAlbum?.title : nil
        config.hasCompletedOnboarding = true

        do {
            try context.save()
        } catch {
            errorMessage = "設定の保存に失敗しました: \(error.localizedDescription)"
        }
    }

    /// Seeds the editor from what is already stored, for the settings screen.
    func loadExisting(config: SortSessionConfig, context: ModelContext) {
        let assignments = (try? context.fetch(FetchDescriptor<DirectionAssignment>())) ?? []
        var mapped: [Direction: DirectionDestination] = [:]
        for assignment in assignments {
            mapped[assignment.direction] = DirectionDestination(
                direction: assignment.direction,
                type: assignment.destinationType,
                albumID: assignment.albumLocalIdentifier,
                title: assignment.displayTitle
            )
        }
        draft = mapped
        scope = config.scope
        sortOrder = config.sortOrder
        if let start = config.dateRangeStart { dateRangeStart = start }
        if let end = config.dateRangeEnd { dateRangeEnd = end }
        if let albumID = config.scopeAlbumIdentifier {
            scopeAlbum = AlbumInfo(
                id: albumID,
                title: config.scopeAlbumTitle ?? "アルバム",
                count: 0
            )
        }
    }
}
