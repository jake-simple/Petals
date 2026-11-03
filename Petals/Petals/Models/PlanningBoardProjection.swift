import Foundation

/// A read-only projection for independently created CloudKit rows. Original rows
/// and their content remain intact; no automatic deletion or reparenting occurs.
enum PlanningBoardProjection {
    static func visibleBoards(_ records: [PlanningBoard]) -> [PlanningBoard] {
        Dictionary(grouping: records, by: \.id).values.compactMap { copies in
            guard !copies.contains(where: { $0.deletedAt != nil }) else { return nil }
            return copies.sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.recordID < $1.recordID
            }.first
        }.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
    }

    static func canvasItems(in documents: [YearDocument], zoom: Int? = nil, page: Int = 0) -> [CanvasItem] {
        documents.flatMap { document in
            zoom.map { document.canvasItems(for: $0, pageIndex: page) } ?? document.canvasItems ?? []
        }.sorted { $0.zIndex < $1.zIndex }
    }
}
