//
//  DrawingDataEraser.swift
//  Domain
//
//  설정의 「모든 필사 데이터 삭제」 실행 (로드맵 SAVE-2).
//

import CarveToolkit
import Foundation

import Dependencies

/// 모든 필사 데이터를 지운 결과. **어디까지 지워졌는지**가 뒤처리를 가른다.
public enum DrawingEraseOutcome: Equatable, Sendable {
    /// 전부 지웠다.
    case completed
    /// 필사 행은 지웠지만 뒤따른 삭제(구 구조 행 · 즐겨찾기 · 보존 영역)가 실패했다.
    ///
    /// 필사 행이 사라졌으므로 **열린 장은 옛 잉크와 미저장분을 버려야 한다.** 그러지 않으면 다음 저장이
    /// 방금 지운 필사를 새 행으로 되살린다 (`ChapterCanvasDataClear`).
    case partiallyFailed
    /// 필사 행 삭제가 실패했다. **아무것도 지워지지 않았다고 보고 미저장분을 지킨다** — 저장소 세대도 올리지 않는다.
    ///
    /// 가정이다. 배치 삭제가 실패할 때 일부만 지워질 수 있는지를 SwiftData 가 밝히지 않아 코드로 증명하지 못한다.
    /// 반대로 가정해 미저장분을 버리면 아무것도 지워지지 않았을 때 사용자가 쓴 필사를 잃는다. 일부가 지워졌더라도
    /// 사용자는 실패 안내의 「다시 시도」 로 마저 지운다.
    case failed

    /// 필사 행이 지워졌는가 — 열린 장이 옛 잉크를 버려야 하는가.
    public var drawingsCleared: Bool { self != .failed }
}

/// 모든 필사 데이터를 지운다. 화면이 SwiftData 를 직접 알지 않게 하고, 실패를 주입해 시험할 수 있게 하는 경계다.
///
/// - Important: 삭제는 **멱등**이어야 한다. 부분 실패 뒤 「다시 시도」 는 이미 지운 것을 다시 지우는 것으로 이어간다.
public protocol DrawingDataEraser: Sendable {
    func eraseAll() async -> DrawingEraseOutcome
}

/// 앱이 실제로 쓰는 구현.
///
/// 필사 행을 **가장 먼저** 지운다 — 무엇이 지워졌는지를 필사 행 하나로 판정할 수 있게 하기 위함이다.
/// 각 삭제는 따로 반영되며 서로 원자적이지 않다(SwiftData 배치 삭제).
///
/// 필사 행 삭제는 저장소 세대도 함께 올린다 (`eraseAllDrawingRows`). 삭제 전에 요청된 저장이 뒤늦게 실행돼도
/// 행을 되살리지 못하게 하기 위함이다 (`DrawingStoreGeneration`).
///
/// 마지막으로 이 기기의 **보존 영역**(원시 사본 · 복구 사본 · 격리본 · 초안)을 지운다. 사용자가 이 기기에서 전체 삭제를 요청했으므로
/// 숨은 사본을 남기지 않는다(§12-6 C11 단계 ④). 2.0.0 이 보존 영역을 지우는 경로는 이것뿐이다. 초안 · 격리 쓰기와 **같은 직렬화 경계**
/// (`LocalPreservationWriter`)를 거친다 — 로컬 삭제 세대를 먼저 올리므로, 삭제 뒤에 도착한 늦은 쓰기는 거절된다.
public struct SwiftDataDrawingDataEraser: DrawingDataEraser {
    private let actor: SwiftDatabaseActor?
    private let localPreservation: @Sendable () -> LocalPreservationWriter?

    /// - Parameters:
    ///   - actor: 사용할 actor. 생략하면 삭제할 때의 의존성 actor — 저장소(`SwiftDataDrawingRepository`)와 같은 actor 여야 세대가 맞는다.
    ///   - localPreservation: 함께 지울 보존 영역의 직렬화 경계. 삭제할 때 정한다. 생략하면 지우지 않는다.
    public init(actor: SwiftDatabaseActor? = nil, localPreservation: @escaping @Sendable () -> LocalPreservationWriter? = { nil }) {
        self.actor = actor
        self.localPreservation = localPreservation
    }

    public func eraseAll() async -> DrawingEraseOutcome {
        @Dependency(\.createSwiftDataActor) var injected
        let database = actor ?? injected
        do {
            try await database.eraseAllDrawingRows()
        } catch {
            Log.error("전체 삭제 — 필사 행을 지우지 못했다. 미저장분을 지키려고 세대를 올리지 않는다", "\(error)")
            return .failed
        }
        do {
            try await database.deleteAll(BiblePageDrawing.self)
            try await database.deleteAll(FavoriteVerse.self)
        } catch {
            Log.error("전체 삭제 — 필사 행은 지웠지만 구 구조 행 · 즐겨찾기를 지우지 못했다", "\(error)")
            return .partiallyFailed
        }
        do {
            try await localPreservation()?.eraseAllLocal()
            return .completed
        } catch {
            Log.error("전체 삭제 — 필사 행은 지웠지만 보존 영역을 지우지 못했다", "\(error)")
            return .partiallyFailed
        }
    }

    /// 앱이 쓰는 직렬화 경계. 앱이 주입한 것을 삭제할 때 읽는다.
    static func liveWriter() -> LocalPreservationWriter? {
        @Dependency(\.localPreservationWriter) var writer
        return writer
    }
}

private enum DrawingDataEraserKey: DependencyKey {
    static let liveValue: any DrawingDataEraser = SwiftDataDrawingDataEraser(localPreservation: { SwiftDataDrawingDataEraser.liveWriter() })
    static let testValue: any DrawingDataEraser = SwiftDataDrawingDataEraser()
}

public extension DependencyValues {
    /// 모든 필사 데이터 삭제.
    var drawingDataEraser: any DrawingDataEraser {
        get { self[DrawingDataEraserKey.self] }
        set { self[DrawingDataEraserKey.self] = newValue }
    }
}
