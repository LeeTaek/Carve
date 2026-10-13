//
//  BackupExportFlushTesting.swift
//  SettingsFeatureTest
//
//  「백업 만들기」 의 캔버스 flush 계약과 파일 만들기 — flush 결과별 진행 · 설정 쪽 10초 시한 · 다시 시도 · 진행 표시 · 실패 사유
//  (설계 docs/backup-import-design.md §3-1 4 ~ 6단계 · §5-2).
//

@testable import SettingsFeature
import ClientInterfaces
import Domain
import Foundation
import Testing

import ComposableArchitecture

/// 이 파일이 막는 것:
/// - 필사 화면의 마지막 편집이 이 기기에 남았는지 확인하기 전에(또는 확인하지 못했는데) 백업을 시작하는 것
/// - 다른 요청 · 지난 요청의 늦은 답으로 백업을 시작하는 것
/// - 답이 오지 않는데 기다리기만 하는 것(설정 쪽 10초 시한)
/// - 파일 만들기 실패를 성공처럼 보이거나, 다시 시도가 마지막 편집 확인을 건너뛰는 것
@Suite("설정 — 필사 백업 · flush 와 파일 만들기")
@MainActor
struct BackupExportFlushTesting {
    /// 문구를 꺼내는 언어 — 시험 언어(스킴 ko-KR)와 같은 한국어라 기대 문구는 한국어 원문 그대로다.
    private static let koreanLocale = Locale(identifier: "ko_KR")
    private typealias Feature = BackupExportFeature

    // MARK: flush 결과

    @Test("flush 가 durable 이면 파일을 만들고 진행을 보인다 — 기본 이름은 만든 날짜, 다 만들면 암호를 비우고 저장 창을 띄운다")
    func durableFlushStartsExport() async {
        let exporter = StubBackupExporter(steps: [
            BackupProgress(done: 0, total: 2), BackupProgress(done: 1, total: 2), BackupProgress(done: 2, total: 2)
        ])
        let requestID = UUID(5)
        let store = makeExportStore(.flushing(requestID), exporter: exporter)

        await store.send(.canvasFlushFinished(id: requestID, outcome: .durable)) {
            $0.step = .exporting(nil)
        }
        await store.receive(.exportProgressed(Feature.ExportProgress(done: 0, total: 2))) {
            $0.step = .exporting(Feature.ExportProgress(done: 0, total: 2))
        }
        await store.receive(.exportProgressed(Feature.ExportProgress(done: 1, total: 2))) {
            $0.step = .exporting(Feature.ExportProgress(done: 1, total: 2))
        }
        await store.receive(.exportProgressed(Feature.ExportProgress(done: 2, total: 2))) {
            $0.step = .exporting(Feature.ExportProgress(done: 2, total: 2))
        }
        await store.receive(.exportFinished(.success(Feature.ExportedFile(.fixture)))) {
            $0.step = .saving(Feature.ExportedFile(.fixture))
            $0.isLocationPickerPresented = true
            // 암호는 파일을 만드는 데까지만 쓴다.
            $0.password = ""
            $0.passwordConfirmation = ""
        }
        #expect(exporter.calls.value == [StubBackupExporter.Call(password: "abcd1234", fileName: BackupTestTime.fileName)])
        #expect(exporter.discarded.value.isEmpty)
        #expect(store.state.exportedFile?.suggestedName == "새기다 필사 백업 2026-10-06")
    }

    @Test("기본 이름의 앞부분은 만드는 순간의 화면 언어다 — 앱 안에서 영어를 고르면 「Carve Backup 날짜」 로 만든다(즉시 전환 단계 3)")
    func defaultNameFollowsInAppLanguage() async {
        // Given: 설정 › 화면 › 언어에서 영어를 고른 저장소
        let storage = InMemoryStorage()
        withDependencies {
            $0.defaultInMemoryStorage = storage
        } operation: {
            @Shared(.appLanguageOverride) var languageOverride: AppLanguage?
            $languageOverride.withLock { $0 = .english }
        }
        let exporter = StubBackupExporter()
        let requestID = UUID(5)
        let store = makeExportStore(.flushing(requestID), exporter: exporter)
        store.dependencies.defaultInMemoryStorage = storage
        store.exhaustivity = .off

        // When: 마지막 필기가 남아 파일을 만든다
        await store.send(.canvasFlushFinished(id: requestID, outcome: .durable))
        await store.receive(\.exportFinished)

        // Then: 저장되는 파일 이름은 그 순간의 화면 언어(영어)로 지었다 — 날짜 부분은 언어와 무관하다
        #expect(exporter.calls.value == [StubBackupExporter.Call(password: "abcd1234", fileName: "Carve Backup 2026-10-06.carvebackup")])
    }

    @Test("flush 가 durable 이 아니면 파일을 만들지 않고 안내한다 — 다시 시도는 새 id 로 묻고, 앞 id 의 늦은 답은 버린다",
          arguments: [CanvasFlushOutcome.failed(retryCount: 2), .timedOut])
    func nonDurableFlushBlocksExport(outcome: CanvasFlushOutcome) async {
        let exporter = StubBackupExporter()
        let store = makeExportStore(.passwordConfirmed(), exporter: exporter)

        await store.send(.view(.startTapped)) {
            $0.step = .flushing(id: UUID(0))
        }
        await store.receive(.delegate(.canvasFlushRequested(id: UUID(0))))
        await store.send(.canvasFlushFinished(id: UUID(0), outcome: outcome)) {
            $0.step = .flushBlocked(outcome)
        }
        #expect(exporter.calls.value.isEmpty)

        await store.send(.view(.retryTapped)) {
            $0.step = .flushing(id: UUID(1))
        }
        await store.receive(.delegate(.canvasFlushRequested(id: UUID(1))))
        // 앞 요청의 늦은 답 — 지금 기다리는 요청이 아니다.
        await store.send(.canvasFlushFinished(id: UUID(0), outcome: .durable))
        #expect(exporter.calls.value.isEmpty)

        await store.send(.view(.closeTapped)) {
            $0.step = .idle
            $0.password = ""
            $0.passwordConfirmation = ""
        }
    }

    @Test("설정 쪽 시한 10초 안에 답이 없으면 시간 초과로 막고, 그 뒤 늦게 온 답은 버린다")
    func settingsSideTimeout() async {
        let clock = TestClock<Duration>()
        let exporter = StubBackupExporter()
        let store = makeExportStore(.passwordConfirmed(), exporter: exporter, clock: clock)

        await store.send(.view(.startTapped)) {
            $0.step = .flushing(id: UUID(0))
        }
        await store.receive(.delegate(.canvasFlushRequested(id: UUID(0))))

        // 시한 직전까지는 기다린다.
        await clock.advance(by: Feature.canvasFlushTimeout - .milliseconds(1))
        #expect(store.state.step == .flushing(id: UUID(0)))

        await clock.advance(by: .milliseconds(1))
        await store.receive(.canvasFlushTimedOut(id: UUID(0))) {
            $0.step = .flushBlocked(.timedOut)
        }
        await store.send(.canvasFlushFinished(id: UUID(0), outcome: .durable))
        #expect(exporter.calls.value.isEmpty)
    }

    @Test("답을 받으면 설정 쪽 시한을 거둔다 — 10초가 지나도 시간 초과가 오지 않는다")
    func answerCancelsTimeout() async {
        let clock = TestClock<Duration>()
        let store = makeExportStore(.passwordConfirmed(), clock: clock)

        await store.send(.view(.startTapped)) {
            $0.step = .flushing(id: UUID(0))
        }
        await store.receive(.delegate(.canvasFlushRequested(id: UUID(0))))
        await store.send(.canvasFlushFinished(id: UUID(0), outcome: .failed(retryCount: 1))) {
            $0.step = .flushBlocked(.failed(retryCount: 1))
        }
        // 시한 effect 가 남아 있으면 여기서 `canvasFlushTimedOut` 을 받아 TestStore 가 실패한다.
        await clock.advance(by: Feature.canvasFlushTimeout)
    }

    // MARK: 파일 만들기 실패

    @Test("파일을 만들지 못하면 사유를 보이고, 다시 시도는 flush 부터 새 id 로 한다",
          arguments: [BackupExportError.generationChanged, .accountChanged, .insufficientSpace, .verificationFailed])
    func exportFailureShowsReasonAndRetriesFromFlush(error: BackupExportError) async {
        let exporter = StubBackupExporter(outcome: .failure(error))
        let requestID = UUID(5)
        let store = makeExportStore(.flushing(requestID), exporter: exporter)

        await store.send(.canvasFlushFinished(id: requestID, outcome: .durable)) {
            $0.step = .exporting(nil)
        }
        await store.receive(.exportFinished(.failure(Feature.ExportFailure(error)))) {
            $0.step = .exportFailed(Feature.ExportFailure(error))
        }
        // 다시 시도에 쓰므로 암호는 그대로다.
        #expect(store.state.password == "abcd1234")

        await store.send(.view(.retryTapped)) {
            $0.step = .flushing(id: UUID(0))
        }
        await store.receive(.delegate(.canvasFlushRequested(id: UUID(0))))
        await store.send(.view(.closeTapped)) {
            $0.step = .idle
            $0.password = ""
            $0.passwordConfirmation = ""
        }
        #expect(exporter.discarded.value.isEmpty)
    }

    @Test("이 실행에 내보내기가 없으면 만들 수 없다고 보인다")
    func missingExporterFails() async {
        let requestID = UUID(5)
        let store = makeExportStore(.flushing(requestID), exporter: nil)

        await store.send(.canvasFlushFinished(id: requestID, outcome: .durable)) {
            $0.step = .exporting(nil)
        }
        await store.receive(.exportFinished(.failure(.unavailable))) {
            $0.step = .exportFailed(.unavailable)
        }
    }

    @Test("진행 문구 — 장을 모으는 동안은 장 수를, 다 모은 뒤에는 암호를 걸어 쓰고 확인한다고 말한다")
    func progressCopy() {
        #expect(BackupCopy.exporting(nil, locale: Self.koreanLocale) == "백업 파일을 만드는 중이에요")
        #expect(BackupCopy.exporting(Feature.ExportProgress(done: 3, total: 10), locale: Self.koreanLocale) == "필사를 모으는 중이에요 · 3/10장")
        #expect(BackupCopy.exporting(Feature.ExportProgress(done: 10, total: 10), locale: Self.koreanLocale) == "암호를 걸어 파일을 쓰고, 다시 열어 확인하는 중이에요")
    }
}
