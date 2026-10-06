//
//  BackupFeatureTesting.swift
//  SettingsFeatureTest
//
//  설정 → 「필사 백업」 화면 — 두 흐름(백업 만들기 · 불러오기)의 자리, 설정 안의 이동, flush 결과 넘기기
//  (설계 docs/backup-import-design.md §1 · §5-2).
//

@testable import SettingsFeature
import Domain
import Foundation
import Testing

import ComposableArchitecture

/// 이 파일이 막는 것:
/// - 불러오기가 구매에 묶이는 것(정책 §6-4 — 검사 · 미리보기 · 불러오기는 무료)
/// - 사지 않은 사람이 광고 제거 화면으로 가지 못하는 것
/// - 필사 화면의 flush 결과가 기다리는 「백업 만들기」 에 닿지 않거나, 백업 화면이 아닌데 엉뚱한 화면으로 가는 것
@Suite("설정 — 필사 백업 화면")
@MainActor
struct BackupFeatureTesting {
    @Test("불러오기 줄은 구매와 상관없이 불러오기 시트를 연다")
    func importOpensSheetWithoutPurchase() async {
        let defaults = backupDefaults(adFree: false)
        let store = TestStore(initialState: BackupFeature.State()) {
            BackupFeature()
        } withDependencies: {
            $0.defaultAppStorage = defaults
        }

        await store.send(.view(.importTapped)) {
            $0.importer = BackupImportFeature.State()
        }
        await store.send(.importer(.dismiss)) {
            $0.importer = nil
        }
    }

    @Test("백업 만들기 시트가 떠 있으면 불러오기 시트를 겹쳐 열지 않는다")
    func importDoesNotStackOverExportFlow() async {
        var state = BackupFeature.State()
        state.export.step = .password
        let store = TestStore(initialState: state) {
            BackupFeature()
        }

        await store.send(.view(.importTapped))
    }

    @Test("사지 않아 광고 제거를 요청하면 설정이 광고 제거 화면을 연다")
    func removeAdsRequestOpensRemoveAds() async {
        let store = TestStore(initialState: SettingsFeature.State.initialState(path: .backup(.initialState))) {
            SettingsFeature()
        }

        await store.send(.path(.presented(.backup(.export(.view(.removeAdsTapped))))))
        await store.receive(\.path.presented.backup.export.delegate.removeAdsRequested) {
            $0.path = .removeAds(.initialState)
        }
        #expect(store.state.selectedSidebarItem == .removeAds)
    }

    @Test("필사 화면의 flush 결과는 「필사 백업」 의 백업 만들기로 넘긴다")
    func flushResultIsForwardedToExport() async {
        let requestID = UUID(9)
        var backup = BackupFeature.State()
        backup.export = .flushing(requestID)
        let store = TestStore(initialState: SettingsFeature.State.initialState(path: .backup(backup))) {
            SettingsFeature()
        }

        await store.send(.canvasFlushFinished(id: requestID, outcome: .failed(retryCount: 1)))
        var blocked = backup
        blocked.export.step = .flushBlocked(.failed(retryCount: 1))
        await store.receive(\.path.presented.backup.export.canvasFlushFinished) {
            $0.path = .backup(blocked)
        }
    }

    @Test("「필사 백업」 화면이 아니면 flush 결과를 버린다 — 기다리는 백업 만들기가 없다")
    func flushResultIsDroppedElsewhere() async {
        let store = TestStore(initialState: SettingsFeature.State.initialState(path: .iCloud(.initialState))) {
            SettingsFeature()
        }

        // 상태가 바뀌거나 액션을 보내면 TestStore 가 실패한다.
        await store.send(.canvasFlushFinished(id: UUID(9), outcome: .durable))
    }

    @Test("패치노트의 이번 출시는 2.1 — 필사 백업 · 불러오기와 캔버스가 하나가 된 것을 알린다")
    func patchnoteAnnouncesBackup() throws {
        let latest = try #require(PatchnoteFeature.releases.first)
        #expect(latest == PatchnoteFeature.latest)
        #expect(latest.version == "2.1")
        #expect(latest.notes.map(\.title) == ["필사 백업 · 불러오기", "필사 캔버스는 하나로", "본문 표시를 바로잡았어요"])
        #expect(latest.notes[0].body.contains("광고 제거 구매에 포함"))
        #expect(latest.notes[0].body.contains("불러오기는 무료"))
        // 지난 출시의 바뀐 점도 설정의 패치노트에 남는다.
        #expect(PatchnoteFeature.releases.map(\.version) == ["2.1", "2.0"])
    }
}
