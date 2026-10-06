//
//  BackupExportFeature.swift
//  SettingsFeature
//
//  설정 → 필사 백업 → 「백업 만들기」 — 구매 확인 · 암호 · 캔버스 flush 확인 · 파일 만들기 · 저장 위치 고르기 · 작업 폴더 정리
//  (설계 docs/backup-import-design.md §3 · §5-2, 정책 §6-1).
//

import CarveToolkit
import ClientInterfaces
import Domain
import Foundation

import ComposableArchitecture

/// 「백업 만들기」 흐름.
///
/// 1. **권한** — 광고 제거를 산 사람만 만든다(`@SharedReader(.isAdFree)` — 판정은 이 Feature 가 한다). 사지 않았으면 만들기 대신
///    광고 제거 화면으로 보낸다(`Delegate.removeAdsRequested`). 불러오기는 구매와 상관없이 열린다.
/// 2. **암호** — 두 번 입력, 8자 이상, 둘이 같아야 한다. 암호는 저장 · 기록하지 않고, 파일을 다 만들면 상태에서도 지운다.
/// 3. **flush** — 열린 필사 화면의 마지막 편집이 이 기기에 남았는지 코디네이터를 거쳐 묻고(`Delegate.canvasFlushRequested`), 같은 id 의 답
///    (`canvasFlushFinished`)이 `.durable` 일 때만 다음으로 간다. 10초 안에 답이 없으면 `.timedOut` 과 같다. 다른 id 의 늦은 답은 버린다.
/// 4. **파일 만들기** — `backupExporter.export(password:fileName:progress:)`. 장 단위 진행을 보이고, 실패는 사유와 [다시 시도] — 다시 시도는
///    flush 부터 새 id 로 한다(시작 전에 늘 마지막 편집을 확인한다).
/// 5. **저장 위치** — 시스템 저장 창(`fileExporter`)으로 사용자가 고른다. 저장 · 취소 · 실패를 따로 보이고, 어느 쪽이든 앱의 작업 폴더를 지운다
///    (`BackupExporting.discard`). 지우지 못해도 다음 앱 시작의 `BackupWorkDirectory.removeStale()` 이 지운다.
@Reducer
public struct BackupExportFeature: Sendable {
    public init() { }

    /// 암호의 최소 길이(설계 §3-1 3단계).
    public static let minimumPasswordLength = 8
    /// 설정 쪽 flush 시한(설계 §5-2). 캔버스 쪽 시한(5초)보다 길어 캔버스가 먼저 `.timedOut` 으로 답한다.
    public static let canvasFlushTimeout: Duration = .seconds(10)

    @ObservableState
    public struct State: Hashable, Sendable {
        /// 흐름의 단계. `.idle` 이면 시트가 닫혀 있다.
        public var step: Step = .idle
        /// 새 암호 — 시트의 첫 칸. 파일을 다 만들거나 흐름을 닫으면 비운다.
        public var password = ""
        /// 새 암호 확인 — 시트의 둘째 칸.
        public var passwordConfirmation = ""
        /// 시스템 저장 창이 떠 있는가. 파일을 다 만들면 띄우고, 저장 · 취소 · 실패가 오면 내린다.
        public var isLocationPickerPresented = false

        public init() { }

        /// 「백업 만들기」 시트가 떠 있는가.
        public var isFlowPresented: Bool { step != .idle }

        /// 지금 암호로 만들기를 시작할 수 없는 까닭. nil 이면 시작할 수 있다.
        public var passwordIssue: PasswordIssue? {
            if password.count < BackupExportFeature.minimumPasswordLength { return .tooShort }
            if password != passwordConfirmation { return .mismatch }
            return nil
        }

        /// 기다리는 일(flush · 파일 만들기 · 저장 위치 고르기)이 있는가 — 시트를 쓸어서 닫지 못하게 한다.
        public var isBusy: Bool {
            switch step {
            case .flushing, .exporting, .saving: true
            case .idle, .password, .flushBlocked, .exportFailed, .finished: false
            }
        }

        /// 다 만들어 저장 위치를 기다리는 파일.
        public var exportedFile: ExportedFile? {
            guard case .saving(let file) = step else { return nil }
            return file
        }
    }

    /// 흐름의 단계.
    public enum Step: Hashable, Sendable {
        /// 시트가 닫혀 있다.
        case idle
        /// 암호를 두 번 받는다.
        case password
        /// 마지막 필기를 저장하는 중 — 그 id 의 flush 답을 기다린다.
        case flushing(id: UUID)
        /// flush 가 `.durable` 이 아니었다 — 백업을 시작하지 않았다. 다시 시도는 새 id 로 묻는다.
        case flushBlocked(CanvasFlushOutcome)
        /// 파일을 만드는 중. 진행은 첫 알림 전까지 nil 이다.
        case exporting(ExportProgress?)
        /// 파일을 만들지 못했다.
        case exportFailed(ExportFailure)
        /// 다 만든 파일의 저장 위치를 고르는 중.
        case saving(ExportedFile)
        /// 저장 위치 고르기가 끝났다 — 저장 · 취소 · 실패.
        case finished(SaveOutcome)
    }

    /// 암호로 시작할 수 없는 까닭.
    public enum PasswordIssue: Hashable, Sendable {
        /// 8자보다 짧다.
        case tooShort
        /// 두 칸이 같지 않다.
        case mismatch
    }

    /// 파일 만들기 진행 — 장 단위(`BackupProgress` 를 화면 상태로 옮긴 값).
    public struct ExportProgress: Hashable, Sendable {
        /// 마친 장 수.
        public var done: Int
        /// 읽을 장 수.
        public var total: Int

        public init(done: Int, total: Int) {
            self.done = done
            self.total = total
        }

        init(_ progress: BackupProgress) {
            self.init(done: progress.done, total: progress.total)
        }
    }

    /// 파일 만들기 실패 — `BackupExportError` 와, 이 실행에 내보내기가 없는 경우.
    public enum ExportFailure: Error, Hashable, Sendable {
        /// 만드는 사이 「모든 필사 삭제」 가 있었다.
        case generationChanged
        /// 만드는 사이 계정 상태 · 저장소 소유 · 여는 초안 묶음이 바뀌었다.
        case accountChanged
        /// 저장된 필사를 읽지 못했다.
        case storeUnreadable
        /// 남겨 둔 필기(초안)를 읽지 못한 장이 있다.
        case draftsUnreadable
        /// 공간이 모자란다.
        case insufficientSpace
        /// 파일을 쓰지 못했다.
        case writeFailed
        /// 다시 열어 대조한 결과가 맞지 않는다.
        case verificationFailed
        /// 이 실행에 내보내기가 주입되지 않았다.
        case unavailable

        init(_ error: BackupExportError) {
            switch error {
            case .generationChanged: self = .generationChanged
            case .accountChanged: self = .accountChanged
            case .storeUnreadable: self = .storeUnreadable
            case .draftsUnreadable: self = .draftsUnreadable
            case .insufficientSpace: self = .insufficientSpace
            case .writeFailed: self = .writeFailed
            case .verificationFailed: self = .verificationFailed
            }
        }
    }

    /// 다 만든 파일 — 저장 위치를 고를 때까지 앱의 작업 폴더(`BackupWork/<UUID>/`)에 있다.
    public struct ExportedFile: Hashable, Sendable {
        /// 작업 폴더 안의 암호화한 파일.
        public let fileURL: URL
        /// 담은 행 수.
        public let rows: Int
        /// 담은 초안(남겨 둔 필기) 수.
        public let drafts: Int
        /// 담은 blob 수.
        public let blobs: Int
        /// manifest 의 `backupID`.
        public let backupID: String

        public init(_ result: BackupExportResult) {
            fileURL = result.fileURL
            rows = result.counts.rows
            drafts = result.counts.drafts
            blobs = result.counts.blobs
            backupID = result.backupID
        }

        /// 파일 이름 — 「새기다 필사 백업 YYYY-MM-DD.carvebackup」.
        public var fileName: String { fileURL.lastPathComponent }

        /// 시스템 저장 창에 넣을 기본 이름 — 확장자는 형식(`.carveBackup`)이 붙인다.
        public var suggestedName: String { fileURL.deletingPathExtension().lastPathComponent }

        /// 내보내기에 돌려줄 결과 — 작업 폴더를 지울 때 쓴다.
        var result: BackupExportResult {
            BackupExportResult(fileURL: fileURL, counts: BackupCounts(rows: rows, drafts: drafts, blobs: blobs), backupID: backupID)
        }
    }

    /// 시스템 저장 창이 알린 결과 — 뷰가 넘긴다.
    public enum SaveResult: Equatable, Sendable {
        /// 사용자가 고른 곳에 저장했다 — 저장된 파일 이름.
        case saved(fileName: String)
        /// 사용자가 저장 위치 고르기를 취소했다.
        case cancelled
        /// 저장하지 못했다.
        case failed
    }

    /// 흐름의 끝 — 저장 · 취소 · 실패를 따로 보인다(설계 §3-1 8단계).
    public enum SaveOutcome: Hashable, Sendable {
        /// 고른 곳에 저장했다 — 저장된 파일 이름과 담은 수.
        case saved(fileName: String, rows: Int, drafts: Int)
        /// 저장 위치 고르기를 취소했다 — 만든 파일은 지웠다.
        case cancelled
        /// 저장하지 못했다 — 만든 파일은 지웠다.
        case failed
    }

    public enum Action: Equatable, ViewAction {
        /// 부모(코디네이터 · 설정)가 처리하는 사건.
        case delegate(Delegate)
        /// 코디네이터가 돌려준 캔버스 flush 결과 — 설정(`SettingsFeature.canvasFlushFinished`)이 넘긴다. 기다리는 id 가 아니면 버린다.
        case canvasFlushFinished(id: UUID, outcome: CanvasFlushOutcome)
        /// 설정 쪽 flush 시한(10초)이 지났다 — 그 id 를 아직 기다리면 `.timedOut` 과 같다.
        case canvasFlushTimedOut(id: UUID)
        /// 파일 만들기가 장 하나를 마쳤다(시작할 때 0 으로 한 번).
        case exportProgressed(ExportProgress)
        /// 파일 만들기가 끝났다 — 다시 열어 대조까지 마친 파일 또는 실패 사유.
        case exportFinished(Result<ExportedFile, ExportFailure>)
        case view(View)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            /// 백업 전에 열린 필사 화면의 마지막 편집이 이 기기에 남았는지 확인해 달라 — 코디네이터가 캔버스로 중계하고 같은 id 로 답한다(설계 §5-2).
            case canvasFlushRequested(id: UUID)
            /// 광고 제거 화면을 열어 달라 — 사지 않아 백업을 만들 수 없다.
            case removeAdsRequested
        }

        @CasePathable
        public enum View: Equatable, Sendable {
            /// 「백업 만들기」 줄의 만들기 — 산 사람이면 암호 시트를 연다.
            case createTapped
            /// 사지 않은 사람의 「광고 제거 보기」.
            case removeAdsTapped
            /// 암호 칸을 고쳤다.
            case passwordChanged(String)
            /// 암호 확인 칸을 고쳤다.
            case passwordConfirmationChanged(String)
            /// 암호를 확인하고 시작한다 — 먼저 마지막 필기를 저장했는지 묻는다.
            case startTapped
            /// flush 가 막혔거나 파일을 만들지 못한 뒤의 [다시 시도] — flush 부터 새 id 로 한다.
            case retryTapped
            /// 저장 창이 닫혀 있을 때 다시 띄운다.
            case chooseLocationTapped
            /// 시스템 저장 창이 뜨거나 닫혔다. 결과는 `saveFinished` 로 따로 온다.
            case locationPickerPresentationChanged(Bool)
            /// 시스템 저장 창이 끝났다 — 저장 · 취소 · 실패.
            case saveFinished(SaveResult)
            /// 취소 · 실패 뒤의 [다시 만들기] — 암호부터 다시 받는다.
            case remakeTapped
            /// 시트를 쓸어서 닫았다.
            case flowPresentationChanged(Bool)
            /// 시트의 닫기 · 취소 — 기다리던 일을 멈추고 만든 파일이 있으면 지운다.
            case closeTapped
        }
    }

    /// effect 취소 id.
    enum CancelID: Hashable {
        /// 설정 쪽 flush 시한.
        case flushTimeout
        /// 파일 만들기.
        case export
    }

    @Dependency(\.backupExporter) var exporter
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date) var date
    @Dependency(\.timeZone) var timeZone
    @Dependency(\.uuid) var uuid

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(let viewAction):
                return reduceView(&state, viewAction)
            case .canvasFlushFinished(let id, let outcome):
                return canvasFlushFinished(&state, id: id, outcome: outcome)
            case .canvasFlushTimedOut(let id):
                return canvasFlushFinished(&state, id: id, outcome: .timedOut)
            case .exportProgressed(let progress):
                guard case .exporting = state.step else { return .none }
                state.step = .exporting(progress)
                return .none
            case .exportFinished(let result):
                return exportFinished(&state, result)
            case .delegate:
                return .none
            }
        }
    }
}

// MARK: - 화면 사건

extension BackupExportFeature {
    /// 화면 사건을 단계에 맞게 처리한다 — 지금 단계에 맞지 않는 사건(늦게 온 탭)은 버린다.
    /// - Returns: flush 요청 · 파일 만들기 · 정리 effect. 부작용은 effect 로만 낸다.
    private func reduceView(_ state: inout State, _ action: Action.View) -> Effect<Action> {
        switch action {
        case .createTapped:
            // 판정은 지금 공유 값으로 한다 — 줄의 모양(뷰)과 같은 값이지만, 구매가 바뀐 직후의 탭도 막는다.
            guard state.step == .idle, isAdFree else { return .none }
            clearPassword(&state)
            state.step = .password
            return .none
        case .removeAdsTapped:
            return .send(.delegate(.removeAdsRequested))
        case .passwordChanged(let value):
            guard state.step == .password else { return .none }
            state.password = value
            return .none
        case .passwordConfirmationChanged(let value):
            guard state.step == .password else { return .none }
            state.passwordConfirmation = value
            return .none
        case .startTapped:
            guard state.step == .password, state.passwordIssue == nil else { return .none }
            return requestCanvasFlush(&state)
        case .retryTapped:
            switch state.step {
            case .flushBlocked, .exportFailed: return requestCanvasFlush(&state)
            default: return .none
            }
        case .chooseLocationTapped:
            guard case .saving = state.step else { return .none }
            state.isLocationPickerPresented = true
            return .none
        case .locationPickerPresentationChanged(let isPresented):
            state.isLocationPickerPresented = state.exportedFile != nil && isPresented
            return .none
        case .saveFinished(let result):
            return saveFinished(&state, result)
        case .remakeTapped:
            guard case .finished(let outcome) = state.step, outcome == .cancelled || outcome == .failed else { return .none }
            clearPassword(&state)
            state.step = .password
            return .none
        case .flowPresentationChanged(let isPresented):
            guard !isPresented else { return .none }
            return closeFlow(&state)
        case .closeTapped:
            return closeFlow(&state)
        }
    }

    /// 광고 제거를 샀는가 — 구매 클라이언트가 쓰는 공유 값(`@SharedReader(.isAdFree)`)을 지금 읽는다.
    /// 상태에 두지 않는 까닭은 `SettingsFeature.Path` 가 `Hashable` 상태를 요구하고 `SharedReader` 는 `Hashable` 이 아니어서다(`RemoveAdsFeature` 와 같다).
    private var isAdFree: Bool {
        SharedReader<Bool>(.isAdFree).wrappedValue
    }

    /// 암호 두 칸을 비운다. 부작용 없음.
    private func clearPassword(_ state: inout State) {
        state.password = ""
        state.passwordConfirmation = ""
    }
}

// MARK: - flush → 파일 만들기

extension BackupExportFeature {
    /// 열린 필사 화면의 마지막 편집이 이 기기에 남았는지 묻는다(설계 §5-2 ①) — 새 id 로 요청하고 10초 시한을 잰다.
    /// - 입력: 암호를 확인한 상태. 출력: `.flushing(id)` 와 요청 · 시한 effect.
    /// - 부작용: 그새 구매가 풀렸으면 시작하지 않고 흐름을 닫는다.
    private func requestCanvasFlush(_ state: inout State) -> Effect<Action> {
        guard isAdFree else { return closeFlow(&state) }
        let id = uuid()
        state.step = .flushing(id: id)
        return .merge(
            .send(.delegate(.canvasFlushRequested(id: id))),
            .run { send in
                try await clock.sleep(for: Self.canvasFlushTimeout)
                await send(.canvasFlushTimedOut(id: id))
            }
            .cancellable(id: CancelID.flushTimeout, cancelInFlight: true)
        )
    }

    /// flush 의 답(또는 설정 쪽 시한) — 기다리는 id 일 때만 받는다. `.durable` 이면 파일을 만들고, 아니면 시작하지 않고 안내한다.
    /// - 출력: 시한 취소와, `.durable` 이면 파일 만들기 effect.
    private func canvasFlushFinished(_ state: inout State, id: UUID, outcome: CanvasFlushOutcome) -> Effect<Action> {
        // 다른 id · 이미 지난 요청의 늦은 답은 버린다 — 다시 시도는 새 id 로 묻는다.
        guard state.step == .flushing(id: id) else { return .none }
        let stopTimeout = Effect<Action>.cancel(id: CancelID.flushTimeout)
        guard outcome == .durable else {
            Log.info("필사 백업 — 마지막 필기가 이 기기에 남았는지 확인하지 못해 백업을 시작하지 않는다", "\(outcome)")
            state.step = .flushBlocked(outcome)
            return stopTimeout
        }
        return .merge(stopTimeout, startExport(&state))
    }

    /// 파일을 만든다 — 기본 이름은 오늘 날짜(`@Dependency(\.date)` · `\.timeZone`)다.
    /// - 출력: `.exporting(nil)` 과, 진행 · 결과를 보내는 effect(흐름을 닫으면 취소 — 내보내기가 작업 폴더를 지운다).
    /// - 부작용: `backupExporter.export` — 앱 작업 폴더에 파일을 쓴다. 암호는 넘기기만 하고 기록하지 않는다.
    private func startExport(_ state: inout State) -> Effect<Action> {
        state.step = .exporting(nil)
        let password = state.password
        let fileName = BackupExportFileName.defaultName(for: date.now, timeZone: timeZone)
        return .run { send in
            guard let exporter else {
                Log.error("필사 백업 — 이 실행에 내보내기가 주입되지 않았다")
                await send(.exportFinished(.failure(.unavailable)))
                return
            }
            do {
                let result = try await exporter.export(password: password, fileName: fileName) { progress in
                    await send(.exportProgressed(ExportProgress(progress)))
                }
                guard !Task.isCancelled else {
                    // 흐름을 닫는 사이 끝났다 — 내놓을 곳이 없으니 곧바로 지운다.
                    await exporter.discard(result)
                    return
                }
                await send(.exportFinished(.success(ExportedFile(result))))
            } catch is CancellationError {
                // 흐름을 닫아 멈췄다 — 내보내기가 작업 폴더를 지웠다.
            } catch let error as BackupExportError {
                await send(.exportFinished(.failure(ExportFailure(error))))
            } catch {
                Log.error("필사 백업 — 알 수 없는 오류로 파일을 만들지 못했다", "\(error)")
                await send(.exportFinished(.failure(.writeFailed)))
            }
        }
        .cancellable(id: CancelID.export, cancelInFlight: true)
    }

    /// 파일 만들기의 끝 — 다 만들었으면 암호를 비우고 저장 창을 띄운다. 실패면 사유를 보인다.
    /// - 부작용: 흐름을 닫은 뒤 늦게 온 파일은 지운다.
    private func exportFinished(_ state: inout State, _ result: Result<ExportedFile, ExportFailure>) -> Effect<Action> {
        guard case .exporting = state.step else {
            if case .success(let file) = result { return discard(file) }
            return .none
        }
        switch result {
        case .success(let file):
            // 암호는 파일을 만드는 데까지만 쓴다.
            clearPassword(&state)
            state.step = .saving(file)
            state.isLocationPickerPresented = true
        case .failure(let failure):
            Log.error("필사 백업 — 파일을 만들지 못했다", "\(failure)")
            state.step = .exportFailed(failure)
        }
        return .none
    }
}

// MARK: - 저장 위치 · 정리

extension BackupExportFeature {
    /// 시스템 저장 창의 결과를 따로 보이고(저장 · 취소 · 실패), 어느 쪽이든 앱의 작업 폴더를 지운다(설계 §3-1 8 · 9단계).
    private func saveFinished(_ state: inout State, _ result: SaveResult) -> Effect<Action> {
        guard case .saving(let file) = state.step else { return .none }
        state.isLocationPickerPresented = false
        switch result {
        case .saved(let fileName):
            state.step = .finished(.saved(fileName: fileName, rows: file.rows, drafts: file.drafts))
        case .cancelled:
            state.step = .finished(.cancelled)
        case .failed:
            Log.error("필사 백업 — 고른 곳에 저장하지 못했다")
            state.step = .finished(.failed)
        }
        return discard(file)
    }

    /// 시트를 닫는다 — 기다리던 flush 시한 · 파일 만들기를 멈추고, 저장 위치를 기다리던 파일은 지우고, 암호를 비운다.
    private func closeFlow(_ state: inout State) -> Effect<Action> {
        let leftover = state.exportedFile
        state.step = .idle
        state.isLocationPickerPresented = false
        clearPassword(&state)
        var effects: [Effect<Action>] = [.cancel(id: CancelID.flushTimeout), .cancel(id: CancelID.export)]
        if let leftover { effects.append(discard(leftover)) }
        return .merge(effects)
    }

    /// 만든 파일과 그 작업 폴더를 지운다(`BackupExporting.discard`). 부작용: 파일 삭제 — 실패해도 다음 앱 시작이 지운다.
    private func discard(_ file: ExportedFile) -> Effect<Action> {
        .run { _ in
            await exporter?.discard(file.result)
        }
    }
}
