//
//  BackupImportFeatureTesting.swift
//  SettingsFeatureTest
//
//  설정 → 필사 백업 → 「백업 불러오기」 — 파일 고르기 · 암호 · 검사 · 미리보기 · 쓰기 게이트 · 적용 · 닫기와 정리
//  (설계 docs/backup-import-design.md §4-1 · §8-1 「설정 리듀서」).
//

@testable import SettingsFeature
import Domain
import Foundation
import Testing

import ComposableArchitecture

/// 이 파일이 막는 것:
/// - 고른 파일의 보안 범위 접근을 검사 밖에서 열어 두거나 닫지 않는 것
/// - 암호를 검사에 넘긴 뒤에도 상태에 들고 있는 것
/// - 대상 계정이 없는 검사 결과(미로그인 · 연결 보류 등)를 적용하는 것
/// - 닫거나 적용을 마친 뒤 평문 작업 폴더(검사 결과)를 남기는 것
@Suite("설정 — 필사 백업 · 백업 불러오기")
@MainActor
struct BackupImportFeatureTesting {
    /// 문구를 꺼내는 언어 — 시험 언어(스킴 ko-KR)와 같은 한국어라 기대 문구는 한국어 원문 그대로다.
    private static let koreanLocale = Locale(identifier: "ko_KR")
    private typealias Feature = BackupImportFeature

    // MARK: 파일 → 암호 → 검사 → 미리보기

    @Test("멈춘 불러오기가 없으면 파일 고르기부터 — 고른 파일은 보안 범위 접근을 연 동안만 검사에 넘기고, 암호는 넘기는 즉시 지운다")
    func fileFlowInspectsWithinSecurityScope() async {
        let log = LockIsolated<[ImportEvent]>([])
        let inspection = Feature.Inspection(ImportFixture.inspection())
        let store = makeImportStore(importer: StubBackupImporter(log: log), log: log)
        let url = ImportFixture.fileURL

        await store.send(.view(.onAppear))
        await store.receive(.pendingJobLoaded(nil)) {
            $0.step = .chooseFile
        }
        await store.send(.view(.chooseFileTapped)) {
            $0.isFileImporterPresented = true
        }
        await store.send(.view(.fileChosen(url))) {
            $0.isFileImporterPresented = false
            $0.step = .password(.file(url))
        }
        await store.send(.view(.passwordChanged(ImportFixture.password))) {
            $0.password = ImportFixture.password
        }
        await store.send(.view(.inspectTapped)) {
            $0.password = ""
            $0.step = .inspecting(.file(url))
        }
        await store.receive(.inspectFinished(.success(inspection))) {
            $0.step = .preview(inspection)
        }
        #expect(log.value == [
            .pendingJobRead,
            .accessOpened(url),
            .inspected(url, password: ImportFixture.password),
            .accessClosed(url)
        ])
        #expect(!store.state.isBusy)
        // 검사 결과를 들고 있는 동안은 쓸어서 닫지 않는다 — 닫기 버튼이 정리한다.
        #expect(store.state.blocksInteractiveDismiss)
    }

    @Test("보안 범위가 아닌 URL 이면 열리지 않은 접근을 닫지 않는다")
    func unscopedFileIsNotClosed() async {
        let log = LockIsolated<[ImportEvent]>([])
        let url = ImportFixture.fileURL
        let store = makeImportStore(
            .at(.password(.file(url)), password: ImportFixture.password),
            importer: StubBackupImporter(log: log),
            log: log,
            grantsAccess: false
        )

        await store.send(.view(.inspectTapped)) {
            $0.password = ""
            $0.step = .inspecting(.file(url))
        }
        let inspection = Feature.Inspection(ImportFixture.inspection())
        await store.receive(.inspectFinished(.success(inspection))) {
            $0.step = .preview(inspection)
        }
        #expect(log.value == [.accessOpened(url), .inspected(url, password: ImportFixture.password)])
    }

    @Test("암호가 비어 있으면 검사하지 않는다")
    func emptyPasswordDoesNotInspect() async {
        let log = LockIsolated<[ImportEvent]>([])
        let store = makeImportStore(.at(.password(.file(ImportFixture.fileURL))), importer: StubBackupImporter(log: log), log: log)

        // 상태가 바뀌거나 effect 가 돌면 TestStore 가 실패한다.
        await store.send(.view(.inspectTapped))
        #expect(log.value.isEmpty)
    }

    @Test("시트가 다시 나타나도 멈춘 불러오기를 다시 읽지 않는다 — 처음 한 번만")
    func onAppearLoadsOnlyOnce() async {
        let log = LockIsolated<[ImportEvent]>([])
        let store = makeImportStore(.at(.chooseFile), importer: StubBackupImporter(log: log), log: log)

        await store.send(.view(.onAppear))
        #expect(log.value.isEmpty)
    }

    @Test("이 실행에 불러오기가 없으면 검사에서 안내한다 — 파일 접근도 열지 않는다")
    func missingImporterExplains() async {
        let log = LockIsolated<[ImportEvent]>([])
        let url = ImportFixture.fileURL
        let store = makeImportStore(importer: nil, log: log)

        await store.send(.view(.onAppear))
        await store.receive(.pendingJobLoaded(nil)) {
            $0.step = .chooseFile
        }
        await store.send(.view(.fileChosen(url))) {
            $0.step = .password(.file(url))
        }
        await store.send(.view(.passwordChanged(ImportFixture.password))) {
            $0.password = ImportFixture.password
        }
        await store.send(.view(.inspectTapped)) {
            $0.password = ""
            $0.step = .inspecting(.file(url))
        }
        await store.receive(.inspectFinished(.failure(.unavailable))) {
            $0.step = .inspectFailed(.unavailable, .file(url))
        }
        #expect(log.value.isEmpty)
        #expect(!Feature.ImportFailure.unavailable.allowsRetry)
    }

    // MARK: 미리보기 · 쓰기 게이트

    @Test("대상 계정이 없는 검사 결과는 미리보기까지다 — 「불러오기」 를 받지 않고 그 사유를 보인다",
          arguments: [SyncedWriteBlock.signedOut, .connectionHeld, .accountUnconfirmed, .ownershipUnverified, .knowledgeUnreadable])
    func previewWithoutTargetScopeDoesNotApply(block: SyncedWriteBlock) async {
        let log = LockIsolated<[ImportEvent]>([])
        let inspection = ImportFixture.inspection(targetScope: nil, writeBlock: block)
        let store = makeImportStore(.at(.preview(Feature.Inspection(inspection))), importer: StubBackupImporter(log: log), log: log)

        #expect(!inspection.canApply)
        await store.send(.view(.applyTapped))
        #expect(log.value.isEmpty)
        #expect(BackupCopy.previewOnly(block, locale: Self.koreanLocale) == "지금은 미리보기만 할 수 있어요. " + BackupCopy.importBlocked(block, locale: Self.koreanLocale))
    }

    @Test("로그인하지 않았거나 연결이 보류된 실행은 「로그인한 뒤 앱을 다시 열면」 으로 안내한다 — 나머지 사유는 따로 말한다")
    func signedOutAndHeldShareRelaunchGuidance() {
        let relaunch = "iCloud 에 로그인한 뒤 앱을 다시 열면 불러올 수 있어요."
        #expect(BackupCopy.importBlocked(.signedOut, locale: Self.koreanLocale) == relaunch)
        #expect(BackupCopy.importBlocked(.connectionHeld, locale: Self.koreanLocale) == relaunch)
        let others: [SyncedWriteBlock] = [.accountUnconfirmed, .ownershipUnverified, .knowledgeUnreadable, .verseFromOtherSession]
        #expect(Set(others.map { BackupCopy.importBlocked($0, locale: Self.koreanLocale) }).count == others.count)
        #expect(!others.map { BackupCopy.importBlocked($0, locale: Self.koreanLocale) }.contains(relaunch))
        // 사유 없이 대상 계정이 없는 검사 결과(대역)도 빈 안내로 두지 않는다.
        #expect(!BackupCopy.importBlocked(nil, locale: Self.koreanLocale).isEmpty)
    }

    @Test("미리보기의 넣을 수 없는 것은 사유별로 판정 순서대로 보인다")
    func unsupportedDetailFollowsReasonOrder() {
        let detail = BackupCopy.unsupportedDetail(ImportFixture.preview.unsupported, locale: Self.koreanLocale)
        #expect(detail == "모르는 성경 권 1 · 읽지 못하는 위치 정보 2")
        #expect(BackupCopy.unsupportedDetail([:], locale: Self.koreanLocale).isEmpty)
        #expect(BackupCopy.resumedChapters(2, locale: Self.koreanLocale) == "앞서 넣은 2장은 건너뛰고 남은 장부터 넣어요.")
    }

    // MARK: 적용 · 결과

    @Test("「불러오기」 는 장 단위 진행을 보이고 실제 수로 끝난다 — 결과를 받으면 검사 결과를 닫는다")
    func applyShowsProgressAndActualTally() async {
        let log = LockIsolated<[ImportEvent]>([])
        let importer = StubBackupImporter(
            log: log,
            applySteps: [BackupProgress(done: 0, total: 3), BackupProgress(done: 1, total: 3), BackupProgress(done: 3, total: 3)]
        )
        let inspection = Feature.Inspection(ImportFixture.inspection())
        let store = makeImportStore(.at(.preview(inspection)), importer: importer, log: log)

        await store.send(.view(.applyTapped)) {
            $0.step = .applying(inspection, nil)
        }
        #expect(store.state.isBusy)
        await store.receive(.applyProgressed(Feature.ApplyProgress(done: 0, total: 3))) {
            $0.step = .applying(inspection, Feature.ApplyProgress(done: 0, total: 3))
        }
        await store.receive(.applyProgressed(Feature.ApplyProgress(done: 1, total: 3))) {
            $0.step = .applying(inspection, Feature.ApplyProgress(done: 1, total: 3))
        }
        await store.receive(.applyProgressed(Feature.ApplyProgress(done: 3, total: 3))) {
            $0.step = .applying(inspection, Feature.ApplyProgress(done: 3, total: 3))
        }
        // 결과는 미리보기 수가 아니라 쓰기 직전에 다시 판정한 실제 수다.
        let tally = Feature.Tally(new: 2, same: 3, archived: 4, protectedCleared: 1, skippedEmpty: 1, unsupported: 2)
        await store.receive(.applyFinished(.completed(tally))) {
            $0.step = .finished(.completed(tally))
        }
        await store.finish()
        #expect(log.value == [.applied(jobID: ImportFixture.jobID), .inspectionDiscarded(jobID: ImportFixture.jobID)])
        #expect(!store.state.blocksInteractiveDismiss)
    }

    // MARK: 닫기 · 정리

    @Test("미리보기에서 닫으면 검사 결과를 닫고(평문 작업 폴더 정리) 시트를 내린다")
    func closingPreviewDiscardsInspection() async {
        let log = LockIsolated<[ImportEvent]>([])
        let dismissals = LockIsolated(0)
        let inspection = Feature.Inspection(ImportFixture.inspection())
        let store = makeImportStore(.at(.preview(inspection)), importer: StubBackupImporter(log: log), log: log, dismissals: dismissals)

        await store.send(.view(.closeTapped))
        await store.finish()
        #expect(log.value == [.inspectionDiscarded(jobID: ImportFixture.jobID)])
        #expect(dismissals.value == 1)
    }

    @Test("검사 중에 닫으면 검사를 멈추고 보안 범위 접근도 닫은 뒤 시트를 내린다")
    func closingWhileInspectingCancels() async {
        let log = LockIsolated<[ImportEvent]>([])
        let dismissals = LockIsolated(0)
        let url = ImportFixture.fileURL
        let store = makeImportStore(
            .at(.password(.file(url)), password: ImportFixture.password),
            importer: StubBackupImporter(log: log, suspendsInspection: true),
            log: log,
            dismissals: dismissals
        )

        await store.send(.view(.inspectTapped)) {
            $0.password = ""
            $0.step = .inspecting(.file(url))
        }
        #expect(store.state.isBusy)
        await waitUntil { log.value.contains(.inspected(url, password: ImportFixture.password)) }
        await store.send(.view(.closeTapped))
        await store.finish()
        // 검사가 멈추면 불러오기가 스스로 작업 폴더를 지운다 — 내놓은 검사 결과가 없어 닫을 것도 없다.
        #expect(log.value == [.accessOpened(url), .inspected(url, password: ImportFixture.password), .accessClosed(url)])
        #expect(dismissals.value == 1)
    }

    @Test("적용 중에 닫으면 적용을 멈추고(쓴 장 · 작업 기록은 그대로) 검사 결과를 닫는다 — 한 번만")
    func closingWhileApplyingCancelsAndDiscards() async {
        let log = LockIsolated<[ImportEvent]>([])
        let dismissals = LockIsolated(0)
        let inspection = Feature.Inspection(ImportFixture.inspection())
        let store = makeImportStore(
            .at(.preview(inspection)),
            importer: StubBackupImporter(log: log, suspendsApply: true),
            log: log,
            dismissals: dismissals
        )

        await store.send(.view(.applyTapped)) {
            $0.step = .applying(inspection, nil)
        }
        await waitUntil { log.value.contains(.applied(jobID: ImportFixture.jobID)) }
        await store.send(.view(.closeTapped))
        await store.finish()
        #expect(log.value == [.applied(jobID: ImportFixture.jobID), .inspectionDiscarded(jobID: ImportFixture.jobID)])
        #expect(dismissals.value == 1)
    }

    @Test("검사를 기다리지 않을 때 늦게 온 검사 결과는 내놓지 않고 닫는다")
    func lateInspectionIsDiscarded() async {
        let log = LockIsolated<[ImportEvent]>([])
        let store = makeImportStore(.at(.chooseFile), importer: StubBackupImporter(log: log), log: log)

        await store.send(.inspectFinished(.success(Feature.Inspection(ImportFixture.inspection()))))
        await store.finish()
        #expect(log.value == [.inspectionDiscarded(jobID: ImportFixture.jobID)])
    }

    @Test("닫으면 입력하던 암호와 파일 고르기 창을 거둔다")
    func closingClearsPasswordAndPicker() async {
        let log = LockIsolated<[ImportEvent]>([])
        let dismissals = LockIsolated(0)
        var state = Feature.State.at(.password(.file(ImportFixture.fileURL)), password: "abcd")
        state.isFileImporterPresented = true
        let store = makeImportStore(state, importer: StubBackupImporter(log: log), log: log, dismissals: dismissals)

        await store.send(.view(.closeTapped)) {
            $0.password = ""
            $0.isFileImporterPresented = false
        }
        await store.finish()
        #expect(log.value.isEmpty)
        #expect(dismissals.value == 1)
    }
}
