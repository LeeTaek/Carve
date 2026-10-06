//
//  BackupExportTestSupport.swift
//  SettingsFeatureTest
//
//  「필사 백업」 시험의 공용 준비물 — 고정 시각 · 내보내기 대역 · TestStore.
//

@testable import SettingsFeature
import Domain
import Foundation

import ComposableArchitecture

/// 백업 시험의 고정 시각(2026-10-06 12:00 UTC) — 기본 파일 이름의 날짜가 이 날이다.
enum BackupTestTime {
    static let now = Date(timeIntervalSince1970: 1_791_288_000)
    /// 날짜를 읽는 시간대 — 기기 시간대와 상관없이 같은 날이 되게 고정한다.
    static let timeZone = TimeZone.gmt
    /// 그날 만든 백업의 기본 파일 이름(설계 §3-1 7단계).
    static let fileName = "새기다 필사 백업 2026-10-06.carvebackup"
}

extension BackupExportResult {
    /// 내보내기 대역이 돌려주는 파일 — 작업 폴더 안의 자리만 흉내 낸다(파일은 만들지 않는다).
    static let fixture = BackupExportResult(
        fileURL: URL(fileURLWithPath: "/tmp/BackupWork/00000000-0000-0000-0000-0000000000AA/\(BackupTestTime.fileName)"),
        counts: BackupCounts(rows: 12, drafts: 3, blobs: 9),
        backupID: "00000000-0000-0000-0000-0000000000BB"
    )
}

/// 정해 둔 결과를 돌려주는 내보내기 대역. 부른 암호 · 파일 이름과 지운 결과를 적는다.
final class StubBackupExporter: BackupExporting {
    /// `export` 를 부른 기록.
    struct Call: Equatable, Sendable {
        let password: String
        let fileName: String?
    }

    /// 돌려줄 결과.
    private let outcome: Result<BackupExportResult, BackupExportError>
    /// 결과 전에 알릴 진행.
    private let steps: [BackupProgress]
    /// true 면 취소될 때까지 끝나지 않는다(만드는 중에 닫기).
    private let suspends: Bool
    let calls = LockIsolated<[Call]>([])
    let discarded = LockIsolated<[BackupExportResult]>([])

    init(
        outcome: Result<BackupExportResult, BackupExportError> = .success(.fixture),
        steps: [BackupProgress] = [],
        suspends: Bool = false
    ) {
        self.outcome = outcome
        self.steps = steps
        self.suspends = suspends
    }

    func export(password: String, progress: @Sendable (BackupProgress) async -> Void) async throws -> BackupExportResult {
        try await export(password: password, fileName: nil, progress: progress)
    }

    func export(password: String, fileName: String?, progress: @Sendable (BackupProgress) async -> Void) async throws -> BackupExportResult {
        calls.withValue { $0.append(Call(password: password, fileName: fileName)) }
        for step in steps {
            await progress(step)
        }
        if suspends {
            try await Task<Never, Never>.never()
        }
        return try outcome.get()
    }

    func discard(_ result: BackupExportResult) async {
        discarded.withValue { $0.append(result) }
    }
}

/// 시험마다 따로 둔 UserDefaults — 광고 제거 여부(`isAdFree`)가 다른 시험과 섞이지 않는다.
func backupDefaults(adFree: Bool) -> UserDefaults {
    let defaults = UserDefaults.inMemory
    defaults.set(adFree, forKey: "isAdFree")
    return defaults
}

/// 「백업 만들기」 TestStore — 시각 · 시간대 · UUID · 시계를 고정한다.
@MainActor
func makeExportStore(
    _ state: BackupExportFeature.State = BackupExportFeature.State(),
    exporter: StubBackupExporter? = StubBackupExporter(),
    adFree: Bool = true,
    clock: TestClock<Duration> = TestClock()
) -> TestStoreOf<BackupExportFeature> {
    let defaults = backupDefaults(adFree: adFree)
    return TestStore(initialState: state) {
        BackupExportFeature()
    } withDependencies: {
        $0.defaultAppStorage = defaults
        $0.backupExporter = exporter
        $0.continuousClock = clock
        $0.date = .constant(BackupTestTime.now)
        $0.timeZone = BackupTestTime.timeZone
        $0.uuid = .incrementing
    }
}

extension BackupExportFeature.State {
    /// 암호를 두 칸 모두 맞게 넣은 상태 — 시작을 누르기 직전.
    static func passwordConfirmed(_ password: String = "abcd1234") -> Self {
        var state = Self()
        state.step = .password
        state.password = password
        state.passwordConfirmation = password
        return state
    }

    /// 그 id 의 flush 답을 기다리는 상태.
    static func flushing(_ id: UUID, password: String = "abcd1234") -> Self {
        var state = passwordConfirmed(password)
        state.step = .flushing(id: id)
        return state
    }
}
