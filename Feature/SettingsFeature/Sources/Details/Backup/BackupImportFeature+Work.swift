//
//  BackupImportFeature+Work.swift
//  SettingsFeature
//
//  「백업 불러오기」 의 effect — 멈춘 작업 읽기 · 버리기 · 검사 · 적용 · 닫기와 검사 결과 정리(설계 docs/backup-import-design.md §4-1 · §6-3).
//

import CarveToolkit
import Domain
import Foundation

import ComposableArchitecture

// MARK: - 멈춘 작업

extension BackupImportFeature {
    /// 끝나지 않은 불러오기를 읽는다 — 시트를 열 때 · 돌아갈 때.
    /// - 출력: `pendingJobLoaded`(없거나 이 실행에 불러오기가 없으면 nil).
    /// - 부작용: 작업 기록과 지금 환경을 읽는다(이어 할 수 있는지는 불러오기가 정한다). 닫으면 취소.
    func loadPendingJob() -> Effect<Action> {
        .run { send in
            let job = await importer?.pendingJob()
            await send(.pendingJobLoaded(job.map(PendingJob.init)))
        }
        .cancellable(id: CancelID.work, cancelInFlight: true)
    }

    /// 멈춘 작업을 버리고(작업 기록 · 암호화 사본 — 넣은 필사는 그대로) 끝나지 않은 불러오기를 다시 읽는다.
    /// - 출력: `pendingJobLoaded`. 부작용: 작업 기록 삭제.
    func discardJob(_ job: PendingJob) -> Effect<Action> {
        .run { send in
            await importer?.discard(job.value)
            let next = await importer?.pendingJob()
            await send(.pendingJobLoaded(next.map(PendingJob.init)))
        }
        .cancellable(id: CancelID.work, cancelInFlight: true)
    }
}

// MARK: - 검사

extension BackupImportFeature {
    /// 검사한다 — 암호는 effect 에만 넘기고 상태에서 곧바로 지운다.
    /// - 입력: 암호를 넣은 상태. 출력: `.inspecting(source)` 와 `inspectFinished` 를 보내는 effect.
    /// - 부작용: 파일 복사 · 평문 작업 폴더 쓰기(저장소는 바꾸지 않는다). 닫으면 취소 — 그새 끝난 검사 결과는 effect 가 닫는다.
    func startInspection(_ state: inout State, source: Source) -> Effect<Action> {
        let password = state.password
        state.password = ""
        state.step = .inspecting(source)
        return .run { send in
            guard let importer else {
                Log.error("필사 불러오기 — 이 실행에 불러오기가 주입되지 않았다")
                await send(.inspectFinished(.failure(.unavailable)))
                return
            }
            do {
                let inspection = try await inspect(source, password: password, importer: importer)
                guard !Task.isCancelled else {
                    // 닫는 사이 끝났다 — 내놓을 곳이 없으니 곧바로 닫는다.
                    await importer.discard(inspection)
                    return
                }
                await send(.inspectFinished(.success(Inspection(inspection))))
            } catch is CancellationError {
                // 닫아서 멈췄다 — 불러오기가 평문 작업 폴더와 새 작업 기록을 지웠다.
            } catch let error as BackupImportError {
                await send(.inspectFinished(.failure(ImportFailure(error))))
            } catch {
                Log.error("필사 불러오기 — 알 수 없는 오류로 검사하지 못했다", "\(error)")
                await send(.inspectFinished(.failure(.ioFailed)))
            }
        }
        .cancellable(id: CancelID.work, cancelInFlight: true)
    }

    /// 출처에 맞는 검사를 부른다 — 고른 파일은 보안 범위 접근을 연 동안만 넘기고(검사가 앱 작업 영역으로 먼저 복사한다) 끝나면 닫는다.
    /// 멈춘 작업은 기기 안 암호화 사본을 쓰므로 접근을 열지 않는다.
    /// - Returns: 검사 결과. - Throws: `BackupImportError` · `CancellationError`. 암호는 넘기기만 하고 남기지 않는다.
    private func inspect(_ source: Source, password: String, importer: any BackupImporting) async throws -> BackupInspection {
        switch source {
        case .file(let url):
            let isAccessing = fileAccess.open(url)
            defer {
                if isAccessing { fileAccess.close(url) }
            }
            return try await importer.inspect(fileURL: url, password: password)
        case .resume(let job):
            return try await importer.resume(job.value, password: password)
        case .restart(let job):
            return try await importer.restart(job.value, password: password)
        }
    }

    /// 검사의 끝 — 검사 결과면 미리보기, 실패면 사유(저장소를 바꾸기 전의 안내)를 보인다.
    /// - 부작용: 검사를 기다리지 않을 때 늦게 온 검사 결과는 곧바로 닫는다.
    func inspectFinished(_ state: inout State, _ result: Result<Inspection, ImportFailure>) -> Effect<Action> {
        guard case .inspecting(let source) = state.step else {
            if case .success(let inspection) = result { return discard(inspection) }
            return .none
        }
        switch result {
        case .success(let inspection):
            state.step = .preview(inspection)
        case .failure(let failure):
            Log.error("필사 불러오기 — 검사하지 못했다(저장소는 그대로)", "\(failure)")
            state.step = .inspectFailed(failure, source)
        }
        return .none
    }
}

// MARK: - 적용

extension BackupImportFeature {
    /// 미리보기를 적용한다 — 장 단위 진행을 보이고 실제 결과를 받는다.
    /// - 입력: 대상 계정이 있는 검사 결과. 출력: `.applying(_, nil)` 과 `applyProgressed` · `applyFinished` 를 보내는 effect.
    /// - 부작용: `backupImporter.apply` — 장마다 한 트랜잭션씩 저장소에 쓴다. 닫으면 취소(쓴 장은 그대로, 작업 기록은 이어 하기용으로 남는다)하고
    ///   effect 가 검사 결과를 닫는다.
    func startApply(_ state: inout State, _ inspection: Inspection) -> Effect<Action> {
        state.step = .applying(inspection, nil)
        return .run { send in
            guard let importer else {
                Log.error("필사 불러오기 — 이 실행에 불러오기가 주입되지 않았다")
                await send(.applyFinished(.failed(.unavailable)))
                return
            }
            do {
                let report = try await importer.apply(inspection.value) { progress in
                    await send(.applyProgressed(ApplyProgress(progress)))
                }
                guard !Task.isCancelled else {
                    await importer.discard(inspection.value)
                    return
                }
                await send(.applyFinished(ImportResult(report)))
            } catch is CancellationError {
                // 닫아서 멈췄다 — 쓴 장은 그대로이고 작업 기록은 이어 하기용으로 남는다. 검사 결과(평문 작업 폴더)를 닫는다.
                await importer.discard(inspection.value)
            } catch let error as BackupImportError {
                await send(.applyFinished(.failed(ImportFailure(error))))
            } catch {
                Log.error("필사 불러오기 — 알 수 없는 오류로 적용을 멈췄다", "\(error)")
                await send(.applyFinished(.failed(.storeWriteFailed)))
            }
        }
        .cancellable(id: CancelID.work, cancelInFlight: true)
    }

    /// 적용의 끝 — 결과를 보이고 검사 결과를 닫는다(평문 작업 폴더만 지우고, 멈춘 작업 기록은 이어 하기용으로 남는다).
    /// - 부작용: `discard(inspection)`. 적용을 기다리지 않으면(닫는 중) 버린다 — 그 effect 가 스스로 정리한다.
    func applyFinished(_ state: inout State, _ result: ImportResult) -> Effect<Action> {
        guard case .applying(let inspection, _) = state.step else { return .none }
        switch result {
        case .completed(let tally):
            Log.info("필사 불러오기 — 모든 장을 넣었다", "넣음=\(tally.inserted)", "건너뜀=\(tally.skipped)", "넣지 못함=\(tally.unsupported)")
        case .blocked, .accountChanged, .generationChanged, .failed:
            Log.error("필사 불러오기 — 적용이 멈췄다(넣은 장은 그대로)", "\(result)")
        }
        state.step = .finished(result)
        return discard(inspection)
    }
}

// MARK: - 닫기 · 정리

extension BackupImportFeature {
    /// 시트를 닫는다 — 기다리던 일을 멈추고, 미리보기의 검사 결과를 닫고, 암호를 비운 뒤 내린다.
    /// 검사 · 적용 중이면 그 effect 가 취소되며 스스로 정리한다(같은 검사 결과를 여기서 함께 닫지 않는다).
    /// - 부작용: effect 취소 · `discard(inspection)` · `dismiss()`.
    func close(_ state: inout State) -> Effect<Action> {
        let held = state.heldInspection
        state.password = ""
        state.isFileImporterPresented = false
        return .merge(
            .cancel(id: CancelID.work),
            .run { _ in
                if let held {
                    await importer?.discard(held.value)
                }
                await dismiss()
            }
        )
    }

    /// 검사 결과를 닫는다(`BackupImporting.discard`) — 평문 작업 폴더를 지우고, 적용을 시작하지 않은 작업이면 그 기록 · 사본도 지운다.
    /// 부작용: 파일 삭제. 지우지 못해도 다음 앱 시작의 `BackupWorkDirectory.removeStale()` 이 지운다.
    func discard(_ inspection: Inspection) -> Effect<Action> {
        .run { _ in
            await importer?.discard(inspection.value)
        }
    }
}
