//
//  BackupImportFeature.swift
//  SettingsFeature
//
//  설정 → 필사 백업 → 「백업 불러오기」 시트 — 멈춘 작업 · 파일 고르기 · 암호 · 검사 · 미리보기 · 쓰기 게이트 · 적용 · 결과 · 정리
//  (설계 docs/backup-import-design.md §4 · §6). 흐름의 effect 는 BackupImportFeature+Work.swift.
//

import CarveToolkit
import Domain
import Foundation

import ComposableArchitecture

/// 「백업 불러오기」 흐름 (설계 §4-1 · §6-3).
///
/// 1. **멈춘 작업** — 시트를 열면 끝나지 않은 불러오기(`backupImporter.pendingJob()`)부터 본다. 지금 계정이 그 작업의 대상 계정이면
///    「이어서 불러오기」(암호를 다시 받는다) · 「버리기」, 다른 계정에서 시작한 작업이면 「버리기」 · 「이 계정으로 처음부터」 만 —
///    A 계정에서 일부 넣은 작업을 B 계정 저장소에 잇지 않는다.
/// 2. **파일 · 암호** — 시스템 파일 고르기(`.carveBackup`)로 고르고 암호를 한 번 받는다. 암호는 검사에 넘기는 즉시 상태에서 지운다.
/// 3. **검사** — 고른 파일의 보안 범위 접근을 열고 `inspect(fileURL:password:)` 에 넘긴 뒤 닫는다(검사가 앱 작업 영역으로 먼저 복사한다).
///    잘못된 암호 · 손상 · 미지원 형식 · 상한 초과는 저장소를 바꾸기 전에 안내한다.
/// 4. **미리보기 · 쓰기 게이트** — 결정별 수와 불러오기 안내(원문). 검사 결과에 대상 계정(`targetScope`)이 없으면 「불러오기」 대신 사유를 보인다.
/// 5. **적용 · 결과** — 장 단위 진행 뒤 실제로 넣은 수 · 건너뛴 수 · 멈춘 사유. 결과를 받으면 검사 결과를 닫는다(`discard` — 평문 작업
///    폴더만 지우고, 멈춘 작업 기록은 이어 하기용으로 남는다).
///
/// - 검사 · 미리보기 · 불러오기는 구매 여부를 묻지 않는다(정책 §6-4).
/// - 시트는 `BackupFeature` 의 `@Presents` 다. 닫기는 이 Feature 안에서 `@Dependency(\.dismiss)` 로 한다 — 닫을 것(검사 결과)을 정리한 뒤 내린다.
@Reducer
public struct BackupImportFeature: Sendable {
    public init() { }

    @ObservableState
    public struct State: Hashable, Sendable {
        /// 흐름의 단계. 시트를 열면 멈춘 작업부터 본다.
        public var step: Step = .loading
        /// 암호 칸. 검사(이어 하기 · 처음부터 포함)에 넘기는 즉시, 그리고 시트를 닫을 때 비운다 — 암호는 저장 · 기록하지 않는다.
        public var password = ""
        /// 시스템 파일 고르기 창이 떠 있는가.
        public var isFileImporterPresented = false

        public init() { }

        /// 기다리는 일(검사 · 적용)이 있는가 — 닫기 버튼이 「취소」 가 된다.
        public var isBusy: Bool {
            switch step {
            case .inspecting, .applying: true
            case .loading, .pendingJob, .chooseFile, .password, .inspectFailed, .preview, .finished: false
            }
        }

        /// 쓸어서 닫지 못하게 하는가 — 기다리는 일이 있거나 닫을 때 정리할 검사 결과가 있으면 닫기 버튼으로만 닫는다.
        public var blocksInteractiveDismiss: Bool { isBusy || heldInspection != nil }

        /// 상태가 들고 있는 검사 결과 — 미리보기 단계에서만. 검사 · 적용 중에는 그 effect 가 들고 있다가 스스로 닫는다.
        var heldInspection: Inspection? {
            guard case .preview(let inspection) = step else { return nil }
            return inspection
        }

        /// 지금 파일을 (다시) 고를 수 있는가 — 파일 고르기 · 고른 파일의 암호 · 파일 검사 실패 단계.
        var allowsChoosingFile: Bool {
            switch step {
            case .chooseFile, .password(.file), .inspectFailed(_, .some(.file)), .inspectFailed(_, .none): true
            default: false
            }
        }
    }

    /// 흐름의 단계.
    public enum Step: Hashable, Sendable {
        /// 끝나지 않은 불러오기가 있는지 보는 중 — 시트를 열 때 · 작업을 버린 뒤.
        case loading
        /// 끝나지 않은 불러오기가 있다 — 같은 계정이면 이어 하기 · 버리기, 아니면 버리기 · 처음부터.
        case pendingJob(PendingJob)
        /// 불러올 백업 파일을 고른다.
        case chooseFile
        /// 암호를 받는다 — 무엇을 검사할지와 함께.
        case password(Source)
        /// 검사하는 중(복사 · 풀기 · 검증 · 미리보기). 저장소는 바꾸지 않는다.
        case inspecting(Source)
        /// 검사하지 못했다 — 저장소는 바뀌지 않았다. 출처가 있으면 같은 출처로 다시 해 볼 수 있다(파일 고르기 창 실패면 nil).
        case inspectFailed(ImportFailure, Source?)
        /// 미리보기 — 대상 계정이 있으면 「불러오기」, 없으면 사유.
        case preview(Inspection)
        /// 장 단위로 넣는 중. 진행은 첫 알림 전까지 nil 이다.
        case applying(Inspection, ApplyProgress?)
        /// 끝났다 — 다 넣었거나, 멈췄거나, 넣지 못했다.
        case finished(ImportResult)
    }

    /// 검사할 것.
    public enum Source: Hashable, Sendable {
        /// 사용자가 고른 파일 — 보안 범위 URL. 검사하는 동안만 접근을 연다.
        case file(URL)
        /// 같은 계정의 멈춘 작업 — 암호를 다시 받아 끝난 장 뒤부터 잇는다(`resume`).
        case resume(PendingJob)
        /// 다른 계정에서 시작한 작업의 암호화 사본으로 지금 계정의 새 작업을 시작한다(`restart`).
        case restart(PendingJob)

        /// 멈춘 작업에서 왔는가(이어 하기 · 처음부터).
        var isJob: Bool {
            if case .file = self { return false }
            return true
        }
    }

    /// 끝나지 않은 불러오기를 상태에 담는 상자 — `BackupImportJob` 은 `Hashable` 이 아니어서 같음은 값 전체로, 해시는 작업 id 로 한다.
    /// 이어 하기 · 처음부터 · 버리기에 그대로 넘긴다.
    public struct PendingJob: Hashable, Sendable {
        /// 불러오기가 내놓은 작업.
        public let value: BackupImportJob

        public init(_ value: BackupImportJob) {
            self.value = value
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.value == rhs.value
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(value.jobID)
        }
    }

    /// 검사 결과를 상태에 담는 상자 — `BackupInspection` 은 풀린 백업을 들고 있어 `Hashable` 이 아니고 다시 만들 수도 없다.
    /// 같음은 값 전체로, 해시는 작업 id 로 한다. 적용 · 닫기에 그대로 넘긴다.
    public struct Inspection: Hashable, Sendable {
        /// 불러오기가 내놓은 검사 결과.
        public let value: BackupInspection

        public init(_ value: BackupInspection) {
            self.value = value
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.value == rhs.value
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(value.jobID)
        }
    }

    /// 적용 진행 — 장 단위(`BackupProgress` 를 화면 상태로 옮긴 값).
    public struct ApplyProgress: Hashable, Sendable {
        /// 끝난 장 수(이어 하기면 앞서 끝난 장 포함).
        public var done: Int
        /// 적용할 장 수.
        public var total: Int

        public init(done: Int, total: Int) {
            self.done = done
            self.total = total
        }

        init(_ progress: BackupProgress) {
            self.init(done: progress.done, total: progress.total)
        }
    }

    /// 끝난 장들의 실제 수 — `BackupImportTally` 를 화면 상태로 옮긴 값. 쓰기 직전에 다시 판정한 것이라 미리보기와 다를 수 있다.
    public struct Tally: Hashable, Sendable {
        /// 그 절의 현재 필사로 넣은 수.
        public var new: Int
        /// 같은 내용이 있어 건너뛴 수.
        public var same: Int
        /// 이전 필사 기록으로 넣은 수.
        public var archived: Int
        /// 이 기기에서 뒤에 지운 절이라 기록으로만 넣은 수.
        public var protectedCleared: Int
        /// 비운 기록이라 넣지 않은 수.
        public var skippedEmpty: Int
        /// 해석할 수 없어 넣지 못한 수.
        public var unsupported: Int

        public init(new: Int = 0, same: Int = 0, archived: Int = 0, protectedCleared: Int = 0, skippedEmpty: Int = 0, unsupported: Int = 0) {
            self.new = new
            self.same = same
            self.archived = archived
            self.protectedCleared = protectedCleared
            self.skippedEmpty = skippedEmpty
            self.unsupported = unsupported
        }

        init(_ tally: BackupImportTally) {
            self.init(
                new: tally.new,
                same: tally.same,
                archived: tally.archived,
                protectedCleared: tally.protectedCleared,
                skippedEmpty: tally.skippedEmpty,
                unsupported: tally.unsupported
            )
        }

        /// 넣은 행 수 — 새 필사 · 이전 필사 기록 · 지운 절 기록.
        public var inserted: Int { new + archived + protectedCleared }
        /// 건너뛴 수 — 같은 필사 · 비운 기록.
        public var skipped: Int { same + skippedEmpty }
    }

    /// 적용의 끝 (설계 §4-1 9단계). 멈춰도 넣은 장은 그대로다 — 이미 동기화됐을 수 있어 되돌리지 않는다.
    public enum ImportResult: Hashable, Sendable {
        /// 모든 장을 넣었다.
        case completed(Tally)
        /// 쓰기 게이트가 막혀 그 장부터 멈췄다(로그아웃 · 계정 확인 중 · 소유 근거 없음 · 연결 보류 등).
        case blocked(SyncedWriteBlock, doneChapters: Int, tally: Tally)
        /// iCloud 계정이 바뀌어 멈췄다 — 다른 계정의 저장소에 잇지 않는다.
        case accountChanged(doneChapters: Int, tally: Tally)
        /// 넣는 사이 「모든 필사 삭제」 가 있어 멈췄다.
        case generationChanged(tally: Tally)
        /// 넣지 못했다(저장 실패 등) — 넣은 장은 그대로이고 작업 기록은 이어 하기용으로 남았다.
        case failed(ImportFailure)

        init(_ report: BackupImportReport) {
            switch report {
            case .completed(let tally):
                self = .completed(Tally(tally))
            case .blocked(let block, let doneChapters, let tally):
                self = .blocked(block, doneChapters: doneChapters.count, tally: Tally(tally))
            case .accountChanged(let doneChapters, let tally):
                self = .accountChanged(doneChapters: doneChapters.count, tally: Tally(tally))
            case .generationChanged(_, let tally):
                self = .generationChanged(tally: Tally(tally))
            }
        }

        /// 실제 수 — 넣지 못한 결과면 nil.
        public var tally: Tally? {
            switch self {
            case .completed(let tally): tally
            case .blocked(_, _, let tally), .accountChanged(_, let tally), .generationChanged(let tally): tally
            case .failed: nil
            }
        }

        /// 모든 장을 넣었는가.
        public var isCompleted: Bool {
            if case .completed = self { return true }
            return false
        }
    }

    /// 검사 · 적용 실패 — `BackupImportError` 와, 이 실행에 불러오기가 없는 경우.
    public enum ImportFailure: Error, Hashable, Sendable {
        /// 고른 파일을 앱 작업 영역으로 복사하지 못했다.
        case fileUnreadable
        /// 암호가 맞지 않거나 파일이 손상 · 변조 · 잘렸다(허용 밖 항목 · 형식 검증 실패도 같은 「파일 거부」).
        case wrongPasswordOrDamaged
        /// 이 앱이 읽지 못하는 형식 버전이다.
        case unsupportedFormat
        /// 상한(항목 수 · blob 하나 · 풀린 합계)을 넘었다.
        case tooLarge
        /// 공간이 모자란다.
        case insufficientSpace
        /// 작업 폴더 · 작업 기록을 쓰지 못했다.
        case ioFailed
        /// 저장된 필사를 읽지 못했다.
        case storeUnreadable
        /// 저장소에 쓰지 못했다 — 그 장은 아무것도 쓰지 않았고 앞서 쓴 장은 그대로다.
        case storeWriteFailed
        /// 이 검사 결과로는 더 적용할 수 없다(평문 작업 폴더를 이미 지웠다).
        case inspectionExpired
        /// 그 작업이 없다(이미 끝났거나 버렸다).
        case jobNotFound
        /// 다른 계정에서 시작한 작업이라 잇지 않는다.
        case jobFromOtherAccount
        /// 이 실행에 불러오기가 주입되지 않았다.
        case unavailable

        init(_ error: BackupImportError) {
            switch error {
            case .fileUnreadable: self = .fileUnreadable
            case .wrongPasswordOrDamaged: self = .wrongPasswordOrDamaged
            case .unsupportedFormat: self = .unsupportedFormat
            case .tooLarge: self = .tooLarge
            case .insufficientSpace: self = .insufficientSpace
            case .ioFailed: self = .ioFailed
            case .storeUnreadable: self = .storeUnreadable
            case .storeWriteFailed: self = .storeWriteFailed
            case .inspectionExpired: self = .inspectionExpired
            case .jobNotFound: self = .jobNotFound
            case .jobFromOtherAccount: self = .jobFromOtherAccount
            }
        }

        /// 같은 출처로 암호부터 다시 해 볼 만한가. 파일이 그대로면 결과도 같은 것(미지원 형식 · 상한 초과)과,
        /// 작업이 없거나 다른 계정의 것이거나 불러오기가 없는 것은 아니다.
        public var allowsRetry: Bool {
            switch self {
            case .fileUnreadable, .wrongPasswordOrDamaged, .insufficientSpace, .ioFailed, .storeUnreadable, .storeWriteFailed, .inspectionExpired:
                true
            case .unsupportedFormat, .tooLarge, .jobNotFound, .jobFromOtherAccount, .unavailable:
                false
            }
        }
    }

    public enum Action: Equatable, ViewAction {
        /// 끝나지 않은 불러오기를 읽었다(시트를 열 때 · 작업을 버린 뒤) — 없으면 nil.
        case pendingJobLoaded(PendingJob?)
        /// 검사가 끝났다 — 검사 결과 또는 실패 사유(어느 쪽이든 저장소는 그대로다).
        case inspectFinished(Result<Inspection, ImportFailure>)
        /// 적용이 장 하나를 마쳤다(시작할 때 이미 끝난 장 수로 한 번).
        case applyProgressed(ApplyProgress)
        /// 적용이 끝났다 — 다 넣었거나 멈췄거나 넣지 못했다.
        case applyFinished(ImportResult)
        case view(View)

        @CasePathable
        public enum View: Equatable, Sendable {
            /// 시트가 나타났다 — 처음이면 끝나지 않은 불러오기를 본다.
            case onAppear
            /// 「이어서 불러오기」 — 같은 계정의 멈춘 작업. 암호를 다시 받는다.
            case resumeTapped
            /// 「이 계정으로 처음부터」 — 다른 계정에서 시작한 작업의 사본으로 새로 검사한다. 암호를 다시 받는다.
            case restartTapped
            /// 「버리기」 — 멈춘 작업의 기록과 사본을 지운다. 넣은 필사는 그대로다.
            case discardJobTapped
            /// 「파일 고르기」 · 「다른 파일 고르기」 — 시스템 파일 고르기 창을 띄운다.
            case chooseFileTapped
            /// 시스템 파일 고르기 창이 뜨거나 닫혔다. 고른 결과는 `fileChosen` · `fileChoiceFailed` 로 따로 온다.
            case fileImporterPresentationChanged(Bool)
            /// 파일을 골랐다 — 보안 범위 URL.
            case fileChosen(URL)
            /// 파일 고르기 창이 파일을 내주지 못했다.
            case fileChoiceFailed
            /// 암호 칸을 고쳤다.
            case passwordChanged(String)
            /// 암호를 넣고 「확인」 — 검사한다.
            case inspectTapped
            /// 검사 실패 뒤 「암호 다시 입력」 · 「다시 시도」 — 같은 출처로 암호부터 다시 받는다.
            case retryTapped
            /// 이어 하기 · 처음부터의 검사 실패 뒤 「돌아가기」 — 끝나지 않은 불러오기를 다시 읽는다.
            case backToPendingJobTapped
            /// 미리보기의 「불러오기」 — 대상 계정이 있을 때만 적용한다.
            case applyTapped
            /// 닫기 · 취소 — 기다리던 일을 멈추고 검사 결과를 정리한 뒤 시트를 내린다.
            case closeTapped
        }
    }

    /// effect 취소 id.
    enum CancelID: Hashable {
        /// 멈춘 작업 읽기 · 버리기 · 검사 · 적용 — 한 번에 하나다. 닫으면 멈춘다.
        case work
    }

    @Dependency(\.backupImporter) var importer
    @Dependency(\.backupFileAccess) var fileAccess
    @Dependency(\.dismiss) var dismiss

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(let viewAction):
                return reduceView(&state, viewAction)
            case .pendingJobLoaded(let job):
                guard state.step == .loading else { return .none }
                state.step = job.map(Step.pendingJob) ?? .chooseFile
                return .none
            case .inspectFinished(let result):
                return inspectFinished(&state, result)
            case .applyProgressed(let progress):
                guard case .applying(let inspection, _) = state.step else { return .none }
                state.step = .applying(inspection, progress)
                return .none
            case .applyFinished(let result):
                return applyFinished(&state, result)
            }
        }
    }
}

// MARK: - 화면 사건

extension BackupImportFeature {
    /// 화면 사건을 단계에 맞게 처리한다 — 지금 단계에 맞지 않는 사건(늦게 온 탭)은 버린다.
    /// - Returns: 멈춘 작업 읽기 · 버리기 · 검사 · 적용 · 닫기 effect. 부작용은 effect 로만 낸다.
    private func reduceView(_ state: inout State, _ action: Action.View) -> Effect<Action> {
        switch action {
        case .onAppear:
            // 시트가 다시 나타나도(다른 창이 덮였다 걷힘) 처음 한 번만 읽는다.
            guard state.step == .loading else { return .none }
            return loadPendingJob()
        case .resumeTapped:
            // 이어 하기는 지금 계정이 그 작업의 대상 계정일 때만이다.
            guard case .pendingJob(let job) = state.step, job.value.canResume else { return .none }
            return askPassword(&state, for: .resume(job))
        case .restartTapped:
            // 같은 계정의 작업은 처음부터 하지 않는다 — 이어 하거나 버린다.
            guard case .pendingJob(let job) = state.step, !job.value.canResume else { return .none }
            return askPassword(&state, for: .restart(job))
        case .discardJobTapped:
            guard case .pendingJob(let job) = state.step else { return .none }
            state.step = .loading
            return discardJob(job)
        case .chooseFileTapped:
            guard state.allowsChoosingFile else { return .none }
            state.isFileImporterPresented = true
            return .none
        case .fileImporterPresentationChanged(let isPresented):
            state.isFileImporterPresented = isPresented && state.allowsChoosingFile
            return .none
        case .fileChosen(let url):
            state.isFileImporterPresented = false
            guard state.allowsChoosingFile else { return .none }
            return askPassword(&state, for: .file(url))
        case .fileChoiceFailed:
            state.isFileImporterPresented = false
            guard state.allowsChoosingFile else { return .none }
            Log.error("필사 불러오기 — 파일 고르기 창이 파일을 내주지 못했다")
            state.step = .inspectFailed(.fileUnreadable, nil)
            return .none
        case .passwordChanged(let value):
            guard case .password = state.step else { return .none }
            state.password = value
            return .none
        case .inspectTapped:
            guard case .password(let source) = state.step, !state.password.isEmpty else { return .none }
            return startInspection(&state, source: source)
        case .retryTapped:
            guard case .inspectFailed(let failure, .some(let source)) = state.step, failure.allowsRetry else { return .none }
            return askPassword(&state, for: source)
        case .backToPendingJobTapped:
            guard case .inspectFailed(_, .some(let source)) = state.step, source.isJob else { return .none }
            state.step = .loading
            return loadPendingJob()
        case .applyTapped:
            // 대상 계정이 없는 검사 결과는 미리보기까지다 — 화면은 버튼 대신 사유를 보인다.
            guard case .preview(let inspection) = state.step, inspection.value.canApply else { return .none }
            return startApply(&state, inspection)
        case .closeTapped:
            return close(&state)
        }
    }

    /// 암호 칸을 비우고 그 출처의 암호를 받는다. 부작용 없음.
    private func askPassword(_ state: inout State, for source: Source) -> Effect<Action> {
        state.password = ""
        state.step = .password(source)
        return .none
    }
}

// MARK: - 보안 범위 접근

/// 사용자가 고른 파일의 보안 범위 접근 — 검사가 그 파일을 앱 작업 영역으로 복사하는 동안만 연다(설계 §4-1 2단계).
/// 시험이 여닫는 순서를 보도록 경계로 나눈다(`MailComposeAvailabilityClient` 와 같은 방식).
struct BackupFileAccessClient: Sendable {
    /// 접근을 연다 — 열었으면 true 이고 그때만 닫는다. 보안 범위 URL 이 아니면 false.
    var open: @Sendable (URL) -> Bool
    /// 연 접근을 닫는다.
    var close: @Sendable (URL) -> Void
}

extension BackupFileAccessClient: DependencyKey {
    static let liveValue = Self(
        open: { $0.startAccessingSecurityScopedResource() },
        close: { $0.stopAccessingSecurityScopedResource() }
    )
    /// 시험 기본값 — 열지 않는다(보안 범위가 아니다). 여닫는 순서를 보는 시험이 기록 대역을 넣는다.
    static let testValue = Self(open: { _ in false }, close: { _ in })
}

extension DependencyValues {
    /// 「백업 불러오기」 가 고른 파일의 보안 범위 접근.
    var backupFileAccess: BackupFileAccessClient {
        get { self[BackupFileAccessClient.self] }
        set { self[BackupFileAccessClient.self] = newValue }
    }
}

// MARK: - 문구 — 백업 불러오기

/// 「백업 불러오기」 의 문구. 「원문」 은 공통 규칙의 문장 그대로다 — 고치지 않는다.
/// 문구는 모듈 카탈로그에 ko · en 으로 두고 `SettingsCatalog` 로 꺼낸다 — 수는 카탈로그 복수형이다(영어 현지화 결정 5 · 8).
extension BackupCopy {
    // MARK: 멈춘 불러오기

    /// 멈춘 작업을 찾는 동안.
    static var importLoading: String { SettingsCatalog.string("불러오기를 준비하는 중이에요") }

    /// 멈춘 불러오기 카드의 제목 — 같은 계정이면 이어 할 수 있고, 아니면 왜 잇지 않는가.
    static func pendingJobTitle(_ job: BackupImportJob) -> String {
        if job.canResume { return SettingsCatalog.string("멈춘 불러오기가 있어요") }
        // 지금 연결된 계정이 있는데 대상 계정과 다르다 — 다른 계정에서 시작한 작업이다(원문).
        guard job.writeBlock != nil else { return SettingsCatalog.string("다른 iCloud 계정에서 시작한 불러오기예요") }
        // 지금은 연결되지 않아 어느 계정인지 견줄 수 없다 — 다른 계정이라고 단정하지 않는다.
        return SettingsCatalog.string("멈춘 불러오기를 지금은 이어서 할 수 없어요")
    }

    /// 멈춘 불러오기가 어디까지 넣었는가.
    static func pendingJobProgress(_ job: BackupImportJob) -> String {
        SettingsCatalog.string("\(job.totalChapters)장 중 \(job.doneChapters.count)장까지 넣었어요 · 넣은 필사 \(job.tally.insertCount)개")
    }

    /// 멈춘 불러오기로 무엇을 할 수 있는가.
    static func pendingJobGuidance(_ job: BackupImportJob) -> String {
        if job.canResume {
            return SettingsCatalog.string("이어서 불러오면 남은 장부터 넣어요. 암호는 저장하지 않아서 백업 암호를 다시 입력해야 해요.")
        }
        if let block = job.writeBlock {
            return importBlocked(block) + " " + SettingsCatalog.string("이미 넣은 필사는 그대로 있어요.")
        }
        return SettingsCatalog.string("지금 계정의 필사에는 이어서 넣지 않아요. 이미 넣은 필사는 그대로 있어요.")
    }

    static var resumeAction: String { SettingsCatalog.string("이어서 불러오기") }
    static var restartAction: String { SettingsCatalog.string("이 계정으로 처음부터") }
    static var discardJobAction: String { SettingsCatalog.string("버리기") }
    /// 버리기의 뜻 — 넣은 필사는 지우지 않는다.
    static var discardJobNote: String {
        SettingsCatalog.string("버리면 멈춘 불러오기의 기록과 이 iPad에 남겨 둔 백업 사본만 지워요. 이미 넣은 필사는 그대로 있어요.")
    }

    // MARK: 파일 · 암호

    /// 파일을 고르기 전 — 먼저 확인해 보여 주고, 「불러오기」 를 눌러야 넣는다.
    static var chooseFilePrompt: String {
        SettingsCatalog.string("""
            불러올 백업 파일(.carvebackup)을 골라 주세요. 파일을 먼저 확인해 무엇이 들어오는지 보여 드리고, \
            ‘불러오기’를 눌러야 이 기기에 넣어요.
            """)
    }
    static var chooseFileAction: String { SettingsCatalog.string("파일 고르기") }
    static var chooseOtherFileAction: String { SettingsCatalog.string("다른 파일 고르기") }

    /// 고른 파일 한 줄 — 이름만 보인다(크기 · 시각은 읽지 않는다).
    static func chosenFile(_ name: String) -> String {
        SettingsCatalog.string("고른 파일: \(name)")
    }

    static var importPasswordPlaceholder: String { SettingsCatalog.string("백업 암호") }

    /// 암호를 받는 까닭 — 출처마다.
    static func importPasswordPrompt(_ source: BackupImportFeature.Source) -> String {
        switch source {
        case .file: SettingsCatalog.string("백업을 만들 때 정한 암호를 입력해 주세요.")
        case .resume: SettingsCatalog.string("멈춘 불러오기를 이어 가려면 백업 암호를 다시 입력해 주세요.")
        case .restart: SettingsCatalog.string("멈춘 불러오기의 백업 사본을 지금 계정으로 처음부터 확인해요. 백업 암호를 입력해 주세요.")
        }
    }

    static var inspectAction: String { SettingsCatalog.string("확인") }
    static var inspecting: String { SettingsCatalog.string("백업 파일을 확인하는 중이에요") }

    // MARK: 검사 실패 — 저장소를 바꾸기 전

    /// 검사하지 못한 까닭과 할 일.
    static func inspectFailed(_ failure: BackupImportFeature.ImportFailure) -> String {
        switch failure {
        case .wrongPasswordOrDamaged:
            SettingsCatalog.string("암호가 맞지 않거나 파일이 손상됐어요. 암호를 확인해 다시 입력해 주세요.")
        case .unsupportedFormat:
            SettingsCatalog.string("이 버전의 앱이 읽을 수 없는 형식의 백업이에요. 앱을 업데이트한 뒤 다시 불러와 주세요.")
        case .tooLarge:
            SettingsCatalog.string("백업 파일이 너무 커서 불러올 수 없어요.")
        case .fileUnreadable:
            SettingsCatalog.string("고른 파일을 읽지 못했어요. 파일이 이 iPad에 내려받아져 있는지 확인해 주세요.")
        case .insufficientSpace:
            SettingsCatalog.string("iPad의 저장 공간이 부족해 백업 파일을 확인하지 못했어요. 공간을 비운 뒤 다시 시도해 주세요.")
        case .ioFailed, .storeWriteFailed, .inspectionExpired:
            SettingsCatalog.string("백업 파일을 확인하지 못했어요. 다시 시도해 주세요.")
        case .storeUnreadable:
            SettingsCatalog.string("저장된 필사를 읽지 못해 미리보기를 만들지 못했어요. 잠시 뒤 다시 시도해 주세요.")
        case .jobNotFound:
            SettingsCatalog.string("멈춘 불러오기를 찾지 못했어요. 이미 끝났거나 버린 불러오기예요.")
        case .jobFromOtherAccount:
            SettingsCatalog.string("다른 iCloud 계정에서 시작한 불러오기예요. 지금 계정의 필사에는 이어서 넣지 않아요.")
        case .unavailable:
            SettingsCatalog.string("지금은 백업을 불러올 수 없어요. 앱을 다시 연 뒤 시도해 주세요.")
        }
    }

    /// 검사 실패는 모두 저장소를 바꾸기 전이다.
    static var inspectFailedNote: String { SettingsCatalog.string("확인하는 단계에서 멈춰서 필사는 바뀌지 않았어요.") }

    /// 같은 출처로 다시 해 보는 버튼 — 암호가 틀렸을 수 있으면 그렇게 말한다.
    static func retryTitle(_ failure: BackupImportFeature.ImportFailure) -> String {
        failure == .wrongPasswordOrDamaged ? SettingsCatalog.string("암호 다시 입력") : retryAction
    }

    static var backAction: String { SettingsCatalog.string("돌아가기") }

    // MARK: 미리보기

    static var previewNew: String { SettingsCatalog.string("새 필사") }
    static var previewSame: String { SettingsCatalog.string("같은 필사") }
    static var previewArchived: String { SettingsCatalog.string("이전 필사 기록에 더할 것") }
    static var previewProtectedCleared: String { SettingsCatalog.string("지운 절이라 기록에만") }
    static var previewUnsupported: String { SettingsCatalog.string("넣을 수 없는 것") }

    /// 수 한 칸.
    static func count(_ value: Int) -> String {
        SettingsCatalog.string("\(value)개")
    }

    /// 넣을 수 없는 까닭 하나.
    static func unsupportedReason(_ reason: BackupUnsupportedReason) -> String {
        switch reason {
        case .unknownTranslation: SettingsCatalog.string("모르는 번역본")
        case .unknownBook: SettingsCatalog.string("모르는 성경 권")
        case .outOfRange: SettingsCatalog.string("성경에 없는 장이나 절")
        case .unknownDrawingVersion: SettingsCatalog.string("모르는 필기 형식")
        case .undecodableMetadata: SettingsCatalog.string("읽지 못하는 위치 정보")
        }
    }

    /// 넣을 수 없는 것의 사유별 수 — 사유 순서는 판정 순서(`BackupUnsupportedReason.allCases`)다.
    static func unsupportedDetail(_ counts: [BackupUnsupportedReason: Int]) -> String {
        BackupUnsupportedReason.allCases
            .compactMap { reason in
                guard let matched = counts[reason], matched > 0 else { return nil }
                return "\(unsupportedReason(reason)) \(matched)"
            }
            .joined(separator: " · ")
    }

    /// 고른 백업 한 줄 — 만든 때와 담은 수(manifest).
    static func backupSummary(_ manifest: BackupManifest) -> String {
        let created = DraftRecoveryCopy.dateText(manifest.createdAt)
        return SettingsCatalog.string("\(created)에 만든 백업 · 필사 기록 \(manifest.counts.rows)개 · 남겨 둔 필기 \(manifest.counts.drafts)개")
    }

    /// 이어 하기의 미리보기 — 끝난 장은 건너뛴다.
    static func resumedChapters(_ count: Int) -> String {
        SettingsCatalog.string("앞서 넣은 \(count)장은 건너뛰고 남은 장부터 넣어요.")
    }

    /// 미리보기 수의 뜻 — 넣기 직전에 다시 판정한다(설계 §4-1 9단계).
    static var previewNote: String {
        SettingsCatalog.string("미리보기 수는 지금 기준이에요. 넣기 직전에 절마다 다시 확인해서 실제로 넣는 수는 조금 다를 수 있어요.")
    }

    static var applyAction: String { SettingsCatalog.string("불러오기") }

    /// 대상 계정이 없는 검사 결과 — 「불러오기」 대신 보인다.
    static func previewOnly(_ block: SyncedWriteBlock?) -> String {
        SettingsCatalog.string("지금은 미리보기만 할 수 있어요.") + " " + importBlocked(block)
    }

    /// 지금 불러올 수 없는 까닭 — 「확인이 필요한 필기」 가져오기(`DraftRecoveryCopy.importBlocked`)와 같은 `SyncedWriteBlock` 사유를 불러오기 말로 한다.
    /// 로그인하지 않고 시작한 실행은 연결이 보류되고, 2.0 은 실행 중에 저장소 연결을 바꾸지 않아 다시 열어야 연결된다 — 미로그인 · 보류는 같은 안내다.
    static func importBlocked(_ block: SyncedWriteBlock?) -> String {
        switch block {
        case .signedOut, .connectionHeld:
            SettingsCatalog.string("iCloud 에 로그인한 뒤 앱을 다시 열면 불러올 수 있어요.")
        case .accountUnconfirmed:
            SettingsCatalog.string("iCloud 계정을 확인하는 중이에요. 확인이 끝난 뒤 다시 불러와 주세요.")
        case .ownershipUnverified:
            SettingsCatalog.string("이 iPad의 필사가 지금 iCloud 계정의 것인지 아직 확인하지 못했어요.")
        case .knowledgeUnreadable:
            SettingsCatalog.string("삭제 기록을 읽지 못했어요. 앱을 다시 열어 보세요.")
        case .verseFromOtherSession:
            SettingsCatalog.string("다른 계정을 쓰던 때의 필기라 지금 계정에 넣지 않아요.")
        case nil:
            SettingsCatalog.string("지금은 불러올 수 없어요. 앱을 다시 연 뒤 시도해 주세요.")
        }
    }

    // MARK: 적용 · 결과

    /// 진행 한 줄 — 장 단위.
    static func applying(_ progress: BackupImportFeature.ApplyProgress?) -> String {
        guard let progress, progress.total > 0 else { return SettingsCatalog.string("필사를 넣는 중이에요") }
        return SettingsCatalog.string("필사를 넣는 중이에요 · \(min(progress.done, progress.total))/\(progress.total)장")
    }

    /// 결과의 첫 줄 — 다 넣었는가, 왜 멈췄는가.
    static func resultTitle(_ result: BackupImportFeature.ImportResult) -> String {
        switch result {
        case .completed(let tally) where tally.inserted > 0:
            SettingsCatalog.string("불러오기를 마쳤어요.")
        case .completed:
            SettingsCatalog.string("불러오기를 마쳤어요. 새로 넣은 필사는 없어요.")
        case .blocked(let block, let doneChapters, _):
            SettingsCatalog.string("불러오기를 멈췄어요. \(importBlocked(block)) 넣은 장 \(doneChapters)개는 그대로 있어요.")
        case .accountChanged(let doneChapters, _):
            // 원문.
            SettingsCatalog.string("iCloud 계정이 바뀌어 불러오기를 멈췄어요. 넣은 장 \(doneChapters)개는 그대로 있어요.")
        case .generationChanged:
            SettingsCatalog.string("적용 중에 모든 필사가 지워져 멈췄어요. ‘백업 불러오기’를 다시 열면 처음부터 다시 불러올 수 있어요.")
        case .failed(let failure):
            applyFailed(failure)
        }
    }

    /// 넣은 것 — 실제 수.
    static func insertedLine(_ tally: BackupImportFeature.Tally) -> String {
        SettingsCatalog.string("""
            넣은 필사 \(tally.inserted)개 — 새 필사 \(tally.new) · 이전 필사 기록 \(tally.archived) · \
            지운 절이라 기록에만 \(tally.protectedCleared)
            """)
    }

    /// 건너뛴 것 — 실제 수.
    static func skippedLine(_ tally: BackupImportFeature.Tally) -> String {
        SettingsCatalog.string("건너뛴 것 \(tally.skipped)개 — 같은 필사 \(tally.same) · 비운 기록 \(tally.skippedEmpty)")
    }

    /// 넣지 못한 것 — 해석할 수 없는 항목.
    static func notInsertedLine(_ count: Int) -> String {
        SettingsCatalog.string("넣지 못한 것 \(count)개 — 이 앱이 읽을 수 없는 내용이에요")
    }

    /// 넣은 것이 있을 때 — 이 기기 반영과 iCloud 전송은 다르다(정책 §7-2).
    static var savedLocally: String { SettingsCatalog.string("이 기기에 저장됐어요. iCloud 전송은 따로 진행돼요.") }

    /// 적용하지 못한 까닭과 할 일 — 넣은 장은 그대로이고, 멈춘 작업은 다시 열면 이어 할 수 있다.
    static func applyFailed(_ failure: BackupImportFeature.ImportFailure) -> String {
        switch failure {
        case .inspectionExpired:
            SettingsCatalog.string("불러오기를 이어 가지 못했어요. ‘백업 불러오기’를 다시 열고 암호를 다시 입력하면 이어서 불러올 수 있어요.")
        case .jobNotFound:
            SettingsCatalog.string("멈춘 불러오기를 찾지 못해 멈췄어요. 넣은 장은 그대로 있어요. 파일을 다시 골라 불러와 주세요.")
        case .unavailable:
            SettingsCatalog.string("지금은 백업을 불러올 수 없어요. 앱을 다시 연 뒤 시도해 주세요.")
        case .storeWriteFailed, .storeUnreadable, .ioFailed, .insufficientSpace, .fileUnreadable, .wrongPasswordOrDamaged,
             .unsupportedFormat, .tooLarge, .jobFromOtherAccount:
            SettingsCatalog.string("필사를 넣지 못해 멈췄어요. 넣은 장은 그대로 있어요. ‘백업 불러오기’를 다시 열면 이어서 불러올 수 있어요.")
        }
    }
}
