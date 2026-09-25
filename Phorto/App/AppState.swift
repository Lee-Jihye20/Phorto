import Foundation
import Photos
import SwiftData

/// Owns the objects that outlive any single screen and decides which top-level
/// destination `RootView` shows.
@Observable
final class AppState {
    let photoService: PhotoLibraryService
    let imageProvider: ImageProvider

    private(set) var sortingViewModel: SortingViewModel?
    private var modelContext: ModelContext?

    /// Set at launch when a previous run left photos waiting to be deleted.
    var showsPendingDeleteQueue = false
    var showsSettings = false
    var showsDeleteConfirmation = false

    init(
        photoService: PhotoLibraryService = PhotoLibraryService(),
        imageProvider: ImageProvider = ImageProvider()
    ) {
        self.photoService = photoService
        self.imageProvider = imageProvider
    }

    func bootstrap(modelContext: ModelContext) {
        guard self.modelContext == nil else { return }
        self.modelContext = modelContext
        sortingViewModel = SortingViewModel(
            photoService: photoService,
            imageProvider: imageProvider,
            modelContext: modelContext
        )
    }

    /// The single config row, created on first launch.
    func configuration(in context: ModelContext) -> SortSessionConfig {
        if let existing = try? context.fetch(FetchDescriptor<SortSessionConfig>()).first {
            return existing
        }
        let config = SortSessionConfig()
        context.insert(config)
        try? context.save()
        return config
    }

    func startSession(config: SortSessionConfig) async {
        guard let viewModel = sortingViewModel else { return }
        await viewModel.loadSession(config: config)
        // A queue left over from a previous run is offered before sorting resumes.
        if viewModel.deleteQueueCount > 0 {
            showsPendingDeleteQueue = true
        }
    }
}
