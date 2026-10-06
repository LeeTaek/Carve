//
//  DrawingDatabase.swift
//  Domain
//
//  Created by 이택성 on 5/10/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Foundation
import SwiftData
import ClientInterfaces

import Dependencies

public struct DrawingDatabase: Sendable {
    public typealias Item = BibleDrawing
    @Dependency(\.createSwiftDataActor) public var actor
    @Dependency(\.analyticsClient) private var analyticsClient

    /// 앱은 runtime 마다 만들어 넘긴다 — `liveValue` 는 처음 읽힌 runtime 의 의존성 문맥을 품고 전역에 남는다.
    public init() {}

    // MARK: - verse 단위 BibleDrawing
    
    /// 그날(달력 기준 하루) 고친 필사의 활동 값. 정렬하지 않는다.
    public func fetchDrawings(date: Date) async throws -> [DrawingActivity]? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay)!

        let storedDrawing: [DrawingActivity]? = try await actor.drawingActivities(from: startOfDay, through: endOfDay)
        Log.debug("Drew Log Count:", storedDrawing?.count ?? 0 )
        return storedDrawing
    }

    // MARK: - 값으로 읽기 (모델은 actor 안에 둔다)

    /// 해당 절의 필사 행을 스냅샷으로 모두 가져온다 — 이력 화면용.
    /// - Parameters:
    ///   - chapter: 해당 성경의 이름과 장
    ///   - verse: 절 번호
    /// - Returns: 행마다 하나, `updateDate` 최신순이고, 없으면 `[]`.
    /// - Note: 매핑은 actor 안에서 한다. 부작용 없음.
    public func fetchVerseSnapshots(chapter: BibleChapter, verse: Int) async throws -> [VerseDrawingSnapshot] {
        try await actor.verseDrawingSnapshots(chapter: chapter, verse: verse)
    }

    /// 특정 절에서 어떤 행이 대표(`isPresent`)인지 저장한다.
    /// - Parameters:
    ///   - chapter: 성경의 이름과 장
    ///   - verse: 절 번호
    ///   - presentRowID: `isPresent = true` 로 표시할 행의 키. 그 절의 나머지 행은 `false` 가 된다.
    /// - Note: 실패하면 분석 이벤트와 로그만 남긴다(던지지 않는다).
    public func updatePresentDrawing(
        chapter: BibleChapter,
        verse: Int,
        presentRowID: BibleDrawingRowID
    ) async {
        do {
            try await actor.markPresentDrawing(chapter: chapter, verse: verse, presentRowID: presentRowID)
            Log.debug(" updatePresentDrawing verse:", verse)
        } catch {
            analyticsClient.trackErrorShown(
                .drawingUpdatePresentFailed,
                feature: .domain,
                context: "DrawingDatabase.updatePresentDrawing",
                message: error.localizedDescription
            )
            Log.error("❌ updatePresentDrawing failed:", error)
        }
    }

    // MARK: - Page 단위 BibleDrawing
    
    /// 한 장 전체의 페이지 단위 필사 데이터(BiblePageDrawing)를 불러옴.
    /// - Parameter chapter: 가져올 성경의 이름과 장
    /// - Returns: 해당 장의 페이지 전체 필사 데이터 (없으면 nil)
    /// - Note: 정렬 조건은 없으며, 조건에 매칭되는 첫 번째 레코드만 반환.
    public func fetchPageDrawing(chapter: BibleChapter) async throws -> BiblePageDrawingSnapshot? {
        try await actor.pageDrawingSnapshot(chapter: chapter)
    }
    
    /// 페이지 단위 full PKDrawing 저장/업데이트
    /// - Parameters:
    ///   - title: 저장할 성경의 이름과 장
    ///   - fullLineData: 페이지 전체 기준 PKDrawing.dataRepresentation()
    ///   - drawingVersion: 좌표계/인코딩 버전을 나타내는 버전 값
    ///   - updateDate: 업데이트 일시 (기본값: 현재 시각)
    /// ⛔ **되살리기 전에 CloudKit 스키마부터 보십시오 (2026-09-09).**
    ///
    /// 이 경로는 **호출부가 없습니다.** 유일한 읽기(`fetchPageDrawing`)도 주석 처리된
    /// `CombinedCanvasFeature` 에만 있어 실행되지 않고, D8 실측상 실데이터도 0행이었습니다.
    /// 그래서 단일 Canvas 배포 준비 중 **CloudKit 의 `CD_BiblePageDrawing` 레코드 타입을 지웠습니다** —
    /// 그대로 두면 Production 에 영구히 들어가는데(CloudKit 은 Production 에서 타입을 지울 수 없습니다)
    /// 아무도 쓰지 않는 것이었기 때문입니다.
    ///
    /// ⚠️ **그래서 지금 이 함수를 부르면 Production 에 없는 레코드 타입을 쓰게 됩니다.**
    /// 로컬 저장은 되지만 CloudKit 동기화가 조용히 실패하고, 원인을 여기와 연결짓기 어렵습니다.
    /// 되살리려면 **CloudKit Dashboard 에서 레코드 타입을 다시 만들어 Production 으로 배포한 뒤** 쓰십시오
    /// (절차: 런북 §6-9 D9-CK).
    ///
    /// 모델(`BiblePageDrawing`)은 아직 스키마에 등록돼 있습니다 — 엔티티 제거는 V5 마이그레이션이
    /// 필요해 **Phase 4** 로 미뤄 뒀습니다 (설계 §10-1).
    public func upsertPageDrawing(
        chapter: BibleChapter,
        fullLineData: Data,
        updateDate: Date = .now
    ) async {
        do {
            if let id = try await actor.pageDrawingID(chapter: chapter) {
                // 기존 페이지 Drawing 업데이트
                try await actor.update(id) { (old: BiblePageDrawing) in
                    old.fullLineData = fullLineData
                    old.updateDate = updateDate
                }
                Log.debug("🔄 updated page drawing:", chapter)
            } else {
                // 없으면 새로 생성
                let page = BiblePageDrawing(
                    bibleTitle: chapter,
                    fullLineData: fullLineData,
                    updateDate: updateDate
                )
                try await actor.insert(page)
                Log.debug(" inserted page drawing:", chapter)
            }
        } catch {
            analyticsClient.trackErrorShown(
                .drawingUpsertPageFailed,
                feature: .domain,
                context: "DrawingDatabase.upsertPageDrawing",
                message: error.localizedDescription
            )
            Log.error("❌ upsertPageDrawing failed:", error)
        }
    }

    /// 최근 range 사이에 업데이트 된 drawing의 활동 값을 최신순으로 반환
    public func fetchDrawings(in range: DateInterval) async throws -> [DrawingActivity] {
        try await actor.drawingActivities(in: range)
    }
    
    /// 최근 필사 Verse 리스트용 활동 값 (최신순, 제한)
    public func fetchRecentDrawings(limit: Int) async throws -> [DrawingActivity] {
        guard limit > 0 else { return [] }
        return try await actor.recentDrawingActivities(limit: limit)
    }

    /// 성경 한 권의 장별 필사 기록을 요약한다 — 탐색 장 목록이 필사한 장을 칠하고 기본 장을 고를 때 쓴다.
    /// - Parameter title: 대상 성경.
    /// - Returns: 획이 남은 장과 그중 가장 최근에 필사한 장.
    public func fetchDrawingRecord(title: BibleTitle) async throws -> BibleTitleDrawingRecord {
        try await actor.fetchDrawingRecord(title: title)
    }
}

extension SwiftDatabaseActor {
    /// 성경 한 권의 행을 훑어 획이 있는 장과 가장 최근에 필사한 장을 구한다.
    ///
    /// SwiftData 모델은 actor 밖으로 내보내지 않고 요약 값만 돌려준다. 획 판정은 `DrawingContentRule` 을 따른다 —
    /// 지우기로 비운 행과 지우개로 전부 지운 행은 기록이 아니고, 보관 행(`isPresent == false`)은 원래 필사 시각을 지닌 기록이다.
    /// 판정마다 `PKDrawing` 을 디코딩하므로 `updateDate` 최신순으로 훑으며 이미 기록을 확인한 장의 행은 건너뛴다.
    /// - Parameter title: 대상 성경.
    /// - Returns: 필사 기록 요약.
    public func fetchDrawingRecord(title: BibleTitle) throws -> BibleTitleDrawingRecord {
        let titleName = title.rawValue
        let predicate = #Predicate<BibleDrawing> { $0.titleName == titleName }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updateDate, order: .reverse)]
        )
        var record = BibleTitleDrawingRecord()
        for row in try modelContext.fetch(descriptor) {
            guard let chapter = row.titleChapter,
                  !record.drawnChapters.contains(chapter),
                  DrawingContentRule.hasStrokes(row.lineData) else { continue }
            record.drawnChapters.insert(chapter)
            // 최신순으로 훑으므로 처음 확인한 장이 가장 최근에 필사한 장이다.
            if record.latestChapter == nil {
                record.latestChapter = chapter
            }
        }
        return record
    }
}

extension DrawingDatabase: DependencyKey {
    public static let liveValue: DrawingDatabase = Self()
    public static let testValue: DrawingDatabase = {
        let database = withDependencies {
            $0.createSwiftDataActor = .testValue
        } operation: {
            DrawingDatabase()
        }
        return database
    }()
    public static let previewValue: DrawingDatabase = {
        let database = withDependencies {
            $0.createSwiftDataActor = .previewValue
        } operation: {
            DrawingDatabase()
        }
        return database
    }()
}

extension DependencyValues {
    public var drawingData: DrawingDatabase {
        get { self[DrawingDatabase.self] }
        set { self[DrawingDatabase.self] = newValue }
    }
}
