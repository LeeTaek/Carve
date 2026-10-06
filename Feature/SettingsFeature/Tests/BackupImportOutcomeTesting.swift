//
//  BackupImportOutcomeTesting.swift
//  SettingsFeatureTest
//
//  「백업 불러오기」 의 결과와 오류 안내 — 막힘 사유 · 계정 바뀜 · 모든 필사 삭제 · 저장 실패 · 검사 실패(저장소를 바꾸기 전)
//  (설계 docs/backup-import-design.md §4-1 9단계 · §4-2 · §6).
//

@testable import SettingsFeature
import Domain
import Foundation
import Testing

import ComposableArchitecture

/// 이 파일이 막는 것:
/// - 적용이 멈췄는데 다 넣은 것처럼 보이거나, 멈춘 까닭(로그인 · 계정 바뀜 · 모든 필사 삭제)과 넣은 장 수를 숨기는 것
/// - 결과에 미리보기 수를 보이는 것(쓰기 직전에 다시 판정한 실제 수를 보인다)
/// - 이 기기 반영을 iCloud 전송까지 끝난 것처럼 말하는 것
/// - 잘못된 암호 · 손상 · 미지원 형식 · 상한 초과를 저장소를 바꾼 뒤에 알리거나, 고쳐지지 않을 실패에 암호를 다시 받는 것
@Suite("설정 — 필사 백업 · 불러오기 결과와 오류 안내")
@MainActor
struct BackupImportOutcomeTesting {
    private typealias Feature = BackupImportFeature

    /// 적용 결과를 받는 데까지 — 미리보기에서 「불러오기」 를 누르고 결과를 받는다.
    private func apply(reporting report: Result<BackupImportReport, BackupImportError>, expecting result: Feature.ImportResult) async {
        let log = LockIsolated<[ImportEvent]>([])
        let inspection = Feature.Inspection(ImportFixture.inspection())
        let store = makeImportStore(.at(.preview(inspection)), importer: StubBackupImporter(log: log, report: report), log: log)

        await store.send(.view(.applyTapped)) {
            $0.step = .applying(inspection, nil)
        }
        await store.receive(.applyFinished(result)) {
            $0.step = .finished(result)
        }
        await store.finish()
        // 결과를 받으면 검사 결과를 닫는다 — 평문 작업 폴더만 지우고 멈춘 작업 기록은 이어 하기용으로 남는다(불러오기의 몫).
        #expect(log.value == [.applied(jobID: ImportFixture.jobID), .inspectionDiscarded(jobID: ImportFixture.jobID)])
    }

    // MARK: 멈춤

    @Test("쓰기 게이트가 막혀 멈추면 그 사유와 넣은 장 수를 보인다 — 미로그인 · 보류는 로그인 뒤 다시 열기",
          arguments: [SyncedWriteBlock.signedOut, .connectionHeld])
    func blockedReportShowsRelaunchGuidance(block: SyncedWriteBlock) async {
        let tally = BackupImportTally(new: 2, same: 1)
        let report = BackupImportReport.blocked(block, doneChapters: [ImportFixture.genesis1, ImportFixture.genesis2], tally: tally)
        let result = Feature.ImportResult.blocked(block, doneChapters: 2, tally: Feature.Tally(new: 2, same: 1))

        await apply(reporting: .success(report), expecting: result)
        #expect(BackupCopy.resultTitle(result)
            == "불러오기를 멈췄어요. iCloud 에 로그인한 뒤 앱을 다시 열면 불러올 수 있어요. 넣은 장 2개는 그대로 있어요.")
        #expect(!result.isCompleted)
    }

    @Test("그 밖의 막힘 사유도 「확인이 필요한 필기」 와 같은 사유로 말한다")
    func blockedReportUsesWriteBlockReason() async {
        let report = BackupImportReport.blocked(.accountUnconfirmed, doneChapters: [], tally: BackupImportTally())
        let result = Feature.ImportResult.blocked(.accountUnconfirmed, doneChapters: 0, tally: Feature.Tally())

        await apply(reporting: .success(report), expecting: result)
        #expect(BackupCopy.resultTitle(result).contains(BackupCopy.importBlocked(.accountUnconfirmed)))
        #expect(BackupCopy.resultTitle(result).hasSuffix("넣은 장 0개는 그대로 있어요."))
    }

    @Test("iCloud 계정이 바뀌어 멈추면 「iCloud 계정이 바뀌어 불러오기를 멈췄어요. 넣은 장 N개는 그대로 있어요.」 와 그때까지의 실제 수")
    func accountChangedReport() async {
        let tally = BackupImportTally(new: 1, archived: 2)
        let report = BackupImportReport.accountChanged(
            doneChapters: [ImportFixture.genesis1, ImportFixture.genesis2, ImportFixture.exodus3],
            tally: tally
        )
        let result = Feature.ImportResult.accountChanged(doneChapters: 3, tally: Feature.Tally(new: 1, archived: 2))

        await apply(reporting: .success(report), expecting: result)
        #expect(BackupCopy.resultTitle(result) == "iCloud 계정이 바뀌어 불러오기를 멈췄어요. 넣은 장 3개는 그대로 있어요.")
        #expect(result.tally?.inserted == 3)
    }

    @Test("넣는 사이 모든 필사가 지워지면 그렇게 말하고 멈춘다")
    func generationChangedReport() async {
        let report = BackupImportReport.generationChanged(doneChapters: [], tally: BackupImportTally())
        let result = Feature.ImportResult.generationChanged(tally: Feature.Tally())

        await apply(reporting: .success(report), expecting: result)
        #expect(BackupCopy.resultTitle(result).hasPrefix("적용 중에 모든 필사가 지워져 멈췄어요."))
    }

    @Test("저장에 실패하면 넣은 장은 그대로라고 알리고, 다시 열면 이어서 불러올 수 있다고 말한다")
    func storeWriteFailure() async {
        let result = Feature.ImportResult.failed(.storeWriteFailed)

        await apply(reporting: .failure(.storeWriteFailed), expecting: result)
        #expect(result.tally == nil)
        #expect(BackupCopy.resultTitle(result).contains("넣은 장은 그대로 있어요."))
        #expect(BackupCopy.resultTitle(result).contains("이어서 불러올 수 있어요."))
    }

    // MARK: 다 넣음 — 실제 수

    @Test("다 넣으면 실제로 넣은 수 · 건너뛴 수 · 넣지 못한 수를 따로 보인다 — 이 기기 저장과 iCloud 전송은 다르다고 말한다")
    func completedReportShowsActualCounts() async {
        let tally = Feature.Tally(ImportFixture.tally)
        let result = Feature.ImportResult.completed(tally)

        await apply(reporting: .success(.completed(ImportFixture.tally)), expecting: result)
        #expect(result.isCompleted)
        #expect(BackupCopy.resultTitle(result) == "불러오기를 마쳤어요.")
        #expect(BackupCopy.insertedLine(tally) == "넣은 필사 7개 — 새 필사 2 · 이전 필사 기록 4 · 지운 절이라 기록에만 1")
        #expect(BackupCopy.skippedLine(tally) == "건너뛴 것 4개 — 같은 필사 3 · 비운 기록 1")
        #expect(BackupCopy.notInsertedLine(tally.unsupported) == "넣지 못한 것 2개 — 이 앱이 읽을 수 없는 내용이에요")
        #expect(BackupCopy.savedLocally == "이 기기에 저장됐어요. iCloud 전송은 따로 진행돼요.")
    }

    @Test("새로 넣은 것이 없으면 마쳤다고만 말한다")
    func completedWithoutInsertions() {
        let result = Feature.ImportResult.completed(Feature.Tally(same: 5))

        #expect(BackupCopy.resultTitle(result) == "불러오기를 마쳤어요. 새로 넣은 필사는 없어요.")
        #expect(result.tally?.inserted == 0)
    }

    // MARK: 검사 실패 — 저장소를 바꾸기 전

    @Test("잘못된 암호 · 손상 · 미지원 형식 · 상한 초과는 적용 전에 안내한다 — 고쳐질 수 있는 실패만 암호를 다시 받는다",
          arguments: [
            (BackupImportError.wrongPasswordOrDamaged, true),
            (.unsupportedFormat(formatVersion: 2), false),
            (.tooLarge, false),
            (.fileUnreadable, true),
            (.insufficientSpace, true)
          ])
    func inspectionErrorsAreExplainedBeforeAnyWrite(error: BackupImportError, allowsRetry: Bool) async {
        let log = LockIsolated<[ImportEvent]>([])
        let url = ImportFixture.fileURL
        let failure = Feature.ImportFailure(error)
        let store = makeImportStore(
            .at(.password(.file(url)), password: ImportFixture.password),
            importer: StubBackupImporter(log: log, inspection: .failure(error)),
            log: log
        )

        await store.send(.view(.inspectTapped)) {
            $0.password = ""
            $0.step = .inspecting(.file(url))
        }
        await store.receive(.inspectFinished(.failure(failure))) {
            $0.step = .inspectFailed(failure, .file(url))
        }
        // 적용하지 않았다 — 검사만 했고 접근은 닫았다.
        #expect(log.value == [.accessOpened(url), .inspected(url, password: ImportFixture.password), .accessClosed(url)])
        #expect(failure.allowsRetry == allowsRetry)
        #expect(!BackupCopy.inspectFailed(failure).isEmpty)
        #expect(BackupCopy.inspectFailedNote == "확인하는 단계에서 멈춰서 필사는 바뀌지 않았어요.")

        if allowsRetry {
            await store.send(.view(.retryTapped)) {
                $0.step = .password(.file(url))
            }
        } else {
            // 같은 파일로는 결과가 같다 — 암호를 다시 받지 않고 다른 파일만 고른다.
            await store.send(.view(.retryTapped))
            await store.send(.view(.chooseFileTapped)) {
                $0.isFileImporterPresented = true
            }
        }
    }

    @Test("잘못된 암호면 같은 파일로 다시 검사한다 — 다시 검사할 때도 보안 범위 접근은 그 동안만 연다")
    func wrongPasswordRetriesSameFile() async {
        let log = LockIsolated<[ImportEvent]>([])
        let url = ImportFixture.fileURL
        let store = makeImportStore(
            .at(.inspectFailed(.wrongPasswordOrDamaged, .file(url))),
            importer: StubBackupImporter(log: log),
            log: log
        )

        #expect(BackupCopy.retryTitle(.wrongPasswordOrDamaged) == "암호 다시 입력")
        #expect(BackupCopy.retryTitle(.insufficientSpace) == BackupCopy.retryAction)
        await store.send(.view(.retryTapped)) {
            $0.step = .password(.file(url))
        }
        await store.send(.view(.passwordChanged("right-password"))) {
            $0.password = "right-password"
        }
        await store.send(.view(.inspectTapped)) {
            $0.password = ""
            $0.step = .inspecting(.file(url))
        }
        let inspection = Feature.Inspection(ImportFixture.inspection())
        await store.receive(.inspectFinished(.success(inspection))) {
            $0.step = .preview(inspection)
        }
        #expect(log.value == [.accessOpened(url), .inspected(url, password: "right-password"), .accessClosed(url)])
    }

    @Test("파일 고르기 창이 파일을 내주지 못하면 안내하고 다시 고르게 한다")
    func fileChoiceFailureOffersAnotherFile() async {
        let log = LockIsolated<[ImportEvent]>([])
        var state = Feature.State.at(.chooseFile)
        state.isFileImporterPresented = true
        let store = makeImportStore(state, importer: StubBackupImporter(log: log), log: log)

        await store.send(.view(.fileChoiceFailed)) {
            $0.isFileImporterPresented = false
            $0.step = .inspectFailed(.fileUnreadable, nil)
        }
        // 다시 해 볼 출처가 없다 — 암호를 받지 않고 파일을 다시 고른다.
        await store.send(.view(.retryTapped))
        await store.send(.view(.chooseFileTapped)) {
            $0.isFileImporterPresented = true
        }
        await store.send(.view(.fileChosen(ImportFixture.fileURL))) {
            $0.isFileImporterPresented = false
            $0.step = .password(.file(ImportFixture.fileURL))
        }
        #expect(log.value.isEmpty)
    }
}
