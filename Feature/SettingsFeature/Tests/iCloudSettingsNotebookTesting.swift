//
//  iCloudSettingsNotebookTesting.swift
//  SettingsFeatureTest
//
//  설정 → iCloud → 「모든 필사 데이터 삭제」 와 필사책(2.2 회차별 필사책) — 지운 뒤 지금 필사책이 기본 필사책이고, 확인 문구가 필사책도 지워진다고 말한다.
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import SettingsFeature

// MARK: - 대역

/// 정해 둔 결과를 돌려주는 전체 삭제.
private struct OutcomeEraser: DrawingDataEraser {
    let outcome: DrawingEraseOutcome

    func eraseAll() async -> DrawingEraseOutcome { outcome }
}

/// 아무것도 하지 않는 위젯 — 비우기도 늘 된다.
private struct QuietWidgetClient: WidgetVerseClient {
    func selection() async -> [FavoriteVerseKey] { [] }
    func select(_ favorites: [FavoriteVerseSnapshot]) async throws {}
    func add(_ favorite: FavoriteVerseSnapshot) async throws {}
    func remove(_ key: FavoriteVerseKey) async throws {}
    func clear() async throws {}
}

/// 이 파일이 막는 것:
/// - 모든 필사책을 지운 뒤에도 지금 필사책 키가 지운 필사책을 가리켜, 다음 필기가 정보 없는 필사책(「이름 없는 필사책」)의 행으로 써지는 것
/// - 지워졌는지 모르는 실패에서 지금 필사책을 바꾸는 것
/// - 확인 문구가 필사책 · 필사책 이름도 함께 지워진다는 것을 말하지 않는 것
@Suite("설정 — 전체 삭제와 필사책")
@MainActor
struct CloudSettingsNotebookTesting {
    /// 문구를 꺼내는 언어 — 시험 언어(스킴 ko-KR)와 같은 한국어라 기대 문구는 한국어 원문 그대로다.
    private static let koreanLocale = Locale(identifier: "ko_KR")
    private static let englishLocale = Locale(identifier: "en")
    /// 지금 펴 둔 필사책 — 기본이 아니다.
    private static let secondNotebook = NotebookID.make(uuid: UUID(uuidString: "0F3A1C2D-0000-4000-8000-000000000002")!)

    /// 이 시험만의 UserDefaults 에 지금 필사책(두 번째)을 두고 전체 삭제를 끝까지 돌린다.
    /// - Returns: 끝난 뒤의 지금 필사책 키 값과, 결과 대화상자.
    private func eraseAll(_ outcome: DrawingEraseOutcome) async throws -> (current: String?, popup: PopupFeature.State?) {
        let suite = "CloudSettingsNotebookTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Self.secondNotebook.rawValue, forKey: "currentNotebookID")
        let store = TestStore(initialState: .initialState) {
            CloudSettingsFeature()
        } withDependencies: {
            $0.defaultAppStorage = defaults
            $0.drawingDataEraser = OutcomeEraser(outcome: outcome)
            $0.widgetVerseClient = QuietWidgetClient()
        }
        // 지금 필사책은 상태 밖(기기의 UserDefaults)이다 — 상태는 기존 전체 삭제 시험이 본다.
        store.exhaustivity = .off

        await store.send(.removeAlliCloudData)
        await store.receive(\.presentPopover)
        await store.finish()
        return (defaults.string(forKey: "currentNotebookID"), store.state.path?.popup)
    }

    @Test("필사 행을 지웠으면(다 지움 · 뒤따른 삭제 일부 실패) 지금 필사책을 기본 필사책으로 돌린다 — 지운 필사책을 가리키지 않는다",
          arguments: [DrawingEraseOutcome.completed, .partiallyFailed])
    func eraseResetsCurrentNotebook(outcome: DrawingEraseOutcome) async throws {
        let result = try await eraseAll(outcome)

        #expect(result.current == NotebookID.default.rawValue)
        // 결과 대화상자는 지금과 같다 — 다 지웠으면 완료, 일부 실패면 다시 시도.
        let expectedAction: PopupFeature.ConfirmAction = outcome == .completed ? .dismiss : .deleteAllData
        #expect(result.popup?.confirmAction == expectedAction)
    }

    @Test("필사 행을 지우지 못했으면 지금 필사책을 그대로 둔다 — 지워졌는지 모르는 채 바꾸지 않는다")
    func failedEraseKeepsCurrentNotebook() async throws {
        let result = try await eraseAll(.failed)

        #expect(result.current == Self.secondNotebook.rawValue)
        #expect(result.popup?.confirmAction == .deleteAllData)
    }

    @Test("삭제 확인 문구는 필사책도 모두 지워지고 「첫 번째 필사」 만 남는다고 말한다 — 영어도")
    func confirmBodyMentionsNotebooks() {
        for remaining in [nil, 0, 3] as [Int?] {
            let korean = CloudSettingsFeature.eraseConfirmBody(remainingDrafts: remaining, locale: Self.koreanLocale)
            #expect(korean.contains("필사책도 모두 지워지고 「첫 번째 필사」만 남아요."))
            // 필기 · 이전 필사 기록 다음 줄이다 — 지워지는 것을 큰 것부터 말한다.
            #expect(korean.components(separatedBy: "\n").dropFirst().first == "필사책도 모두 지워지고 「첫 번째 필사」만 남아요.")
        }
        let english = CloudSettingsFeature.eraseConfirmBody(remainingDrafts: nil, locale: Self.englishLocale)
        #expect(english.contains("All notebooks will be deleted too, leaving only “First Notebook.”"))
    }
}
