//
//  BackupExportFeatureTesting.swift
//  SettingsFeatureTest
//
//  설정 → 필사 백업 → 「백업 만들기」 — 구매 확인 · 암호 · 저장 · 취소 · 실패 · 작업 폴더 정리
//  (설계 docs/backup-import-design.md §3-1 · §8-1 「설정 리듀서」).
//

@testable import SettingsFeature
import Domain
import Foundation
import Testing

import ComposableArchitecture

/// 이 파일이 막는 것:
/// - 광고 제거를 사지 않은 사람이 백업을 만드는 것(판정은 Feature 가 한다)
/// - 8자보다 짧거나 두 칸이 다른 암호로 시작하는 것
/// - 저장 · 취소 · 실패를 같은 결과로 보이거나, 어느 쪽이든 앱의 작업 폴더에 평문 · 파일을 남기는 것
/// - 파일을 다 만든 뒤에도 암호를 상태에 들고 있는 것
@Suite("설정 — 필사 백업 · 백업 만들기")
@MainActor
struct BackupExportFeatureTesting {
    private typealias Feature = BackupExportFeature

    // MARK: 구매

    @Test("사지 않았으면 만들기를 열지 않고, 광고 제거 화면을 요청한다")
    func notPurchasedRoutesToRemoveAds() async {
        let exporter = StubBackupExporter()
        let store = makeExportStore(exporter: exporter, adFree: false)

        // 상태가 바뀌면 TestStore 가 실패한다 — 시트가 열리지 않는다.
        await store.send(.view(.createTapped))
        await store.send(.view(.removeAdsTapped))
        await store.receive(.delegate(.removeAdsRequested))
        #expect(exporter.calls.value.isEmpty)
    }

    @Test("암호를 받는 사이 구매가 풀리면 시작하지 않고 흐름을 닫는다")
    func revokedPurchaseClosesFlow() async {
        let exporter = StubBackupExporter()
        let store = makeExportStore(.passwordConfirmed(), exporter: exporter, adFree: false)

        await store.send(.view(.startTapped)) {
            $0.step = .idle
            $0.password = ""
            $0.passwordConfirmation = ""
        }
        #expect(exporter.calls.value.isEmpty)
    }

    // MARK: 암호

    @Test("산 사람은 만들기를 눌러 암호를 받는다 — 8자 이상이고 두 칸이 같아야 시작한다")
    func passwordMustBeLongAndConfirmed() async {
        let store = makeExportStore()

        await store.send(.view(.createTapped)) {
            $0.step = .password
        }
        await store.send(.view(.passwordChanged("1234567"))) {
            $0.password = "1234567"
        }
        await store.send(.view(.passwordConfirmationChanged("1234567"))) {
            $0.passwordConfirmation = "1234567"
        }
        #expect(store.state.passwordIssue == .tooShort)
        // 7자 — 시작하지 않는다.
        await store.send(.view(.startTapped))

        await store.send(.view(.passwordChanged("12345678"))) {
            $0.password = "12345678"
        }
        #expect(store.state.passwordIssue == .mismatch)
        // 두 칸이 다르다 — 시작하지 않는다.
        await store.send(.view(.startTapped))

        await store.send(.view(.passwordConfirmationChanged("12345678"))) {
            $0.passwordConfirmation = "12345678"
        }
        #expect(store.state.passwordIssue == nil)
        await store.send(.view(.startTapped)) {
            $0.step = .flushing(id: UUID(0))
        }
        await store.receive(.delegate(.canvasFlushRequested(id: UUID(0))))

        // 닫으면 기다리던 시한을 거두고 암호를 비운다.
        await store.send(.view(.closeTapped)) {
            $0.step = .idle
            $0.password = ""
            $0.passwordConfirmation = ""
        }
    }

    @Test("암호 길이는 글자 수로 센다 — 한글 8자도 된다")
    func passwordLengthCountsCharacters() {
        var state = Feature.State.passwordConfirmed("가나다라마바사")
        #expect(state.passwordIssue == .tooShort)
        state.password = "가나다라마바사아"
        state.passwordConfirmation = "가나다라마바사아"
        #expect(state.passwordIssue == nil)
    }

    @Test("암호 단계가 아니면 암호 칸 · 시작 사건을 받지 않는다")
    func passwordEventsOutsidePasswordStepAreIgnored() async {
        let exporter = StubBackupExporter()
        let store = makeExportStore(exporter: exporter)

        await store.send(.view(.passwordChanged("abcd1234")))
        await store.send(.view(.passwordConfirmationChanged("abcd1234")))
        await store.send(.view(.startTapped))
        #expect(exporter.calls.value.isEmpty)
    }

    // MARK: 저장 · 취소 · 실패

    @Test("저장 · 취소 · 실패를 따로 보이고, 어느 쪽이든 만든 파일과 작업 폴더를 지운다")
    func saveOutcomesAreDistinctAndCleanUp() async {
        let file = Feature.ExportedFile(.fixture)
        let cases: [(Feature.SaveResult, Feature.SaveOutcome)] = [
            (.saved(fileName: "내 필사 백업.carvebackup"), .saved(fileName: "내 필사 백업.carvebackup", rows: 12, drafts: 3)),
            (.cancelled, .cancelled),
            (.failed, .failed)
        ]
        for (result, outcome) in cases {
            let exporter = StubBackupExporter()
            var state = Feature.State()
            state.step = .saving(file)
            state.isLocationPickerPresented = true
            let store = makeExportStore(state, exporter: exporter)

            await store.send(.view(.saveFinished(result))) {
                $0.step = .finished(outcome)
                $0.isLocationPickerPresented = false
            }
            await store.finish()
            #expect(exporter.discarded.value == [.fixture], "\(result)")
        }
    }

    @Test("취소 · 실패 뒤 다시 만들기는 암호부터 다시 받는다 — 저장한 뒤에는 받지 않는다")
    func remakeStartsFromPassword() async {
        for outcome in [Feature.SaveOutcome.cancelled, .failed] {
            var state = Feature.State()
            state.step = .finished(outcome)
            let store = makeExportStore(state)
            await store.send(.view(.remakeTapped)) {
                $0.step = .password
            }
        }

        var saved = Feature.State()
        saved.step = .finished(.saved(fileName: BackupTestTime.fileName, rows: 1, drafts: 0))
        let store = makeExportStore(saved)
        await store.send(.view(.remakeTapped))
    }

    @Test("저장 창이 결과 없이 닫혀도 파일은 남아 다시 띄울 수 있다")
    func locationPickerCanBeReopened() async {
        var state = Feature.State()
        state.step = .saving(Feature.ExportedFile(.fixture))
        state.isLocationPickerPresented = true
        let store = makeExportStore(state)

        await store.send(.view(.locationPickerPresentationChanged(false))) {
            $0.isLocationPickerPresented = false
        }
        await store.send(.view(.chooseLocationTapped)) {
            $0.isLocationPickerPresented = true
        }
    }

    // MARK: 닫기 · 정리

    @Test("저장할 곳을 고르기 전에 닫으면 만든 파일을 지운다")
    func closingWhileSavingDiscardsFile() async {
        let exporter = StubBackupExporter()
        var state = Feature.State()
        state.step = .saving(Feature.ExportedFile(.fixture))
        state.isLocationPickerPresented = true
        let store = makeExportStore(state, exporter: exporter)

        await store.send(.view(.flowPresentationChanged(false))) {
            $0.step = .idle
            $0.isLocationPickerPresented = false
        }
        await store.finish()
        #expect(exporter.discarded.value == [.fixture])
    }

    @Test("만드는 중에 닫으면 파일 만들기를 멈추고 암호를 비운다 — 늦은 결과를 받지 않는다")
    func closingWhileExportingCancelsExport() async {
        let exporter = StubBackupExporter(suspends: true)
        let requestID = UUID(7)
        let store = makeExportStore(.flushing(requestID), exporter: exporter)

        await store.send(.canvasFlushFinished(id: requestID, outcome: .durable)) {
            $0.step = .exporting(nil)
        }
        await store.send(.view(.closeTapped)) {
            $0.step = .idle
            $0.password = ""
            $0.passwordConfirmation = ""
        }
        // 멈춘 만들기는 내보내기가 스스로 정리한다 — 내놓을 파일이 없어 지울 것도 없다.
        await store.finish()
        #expect(exporter.discarded.value.isEmpty)
    }

    @Test("흐름을 닫은 뒤 늦게 끝난 파일은 내놓지 않고 지운다")
    func lateExportResultIsDiscarded() async {
        let exporter = StubBackupExporter()
        let store = makeExportStore(exporter: exporter)

        await store.send(.exportFinished(.success(Feature.ExportedFile(.fixture))))
        await store.finish()
        #expect(exporter.discarded.value == [.fixture])
    }
}
