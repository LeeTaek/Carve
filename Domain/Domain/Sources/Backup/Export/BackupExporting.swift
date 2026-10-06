//
//  BackupExporting.swift
//  Domain
//
//  필사 백업 내보내기의 계약 — 「백업 만들기」 가 부르는 경계와 결과 · 오류 · 진행 (설계 docs/backup-import-design.md §3).
//

import Dependencies
import Foundation

/// 필사 백업 파일(`.carvebackup`) 만들기 — 이 기기의 `BibleDrawing` 행 전부와 지금 환경이 여는 묶음의 저장소에 반영되지 않은 초안을
/// 암호화한 파일 하나로 쓴다 (설계 §3 · 정책 §6-1).
///
/// - 환경(계정 상태 · 저장소 소유 · 여는 초안 묶음)은 구현이 `DrawingEditEnvironmentClient` 로 **장마다** 다시 읽는다 — 시작 때와 다르면
///   `BackupExportError.accountChanged` 로 멈춘다(다른 계정의 초안이 한 파일에 섞이지 않게).
/// - 부르기 전에 열린 필사 화면의 flush 가 `.durable` 이어야 한다(캔버스 flush 계약) — 그 판정은 부르는 쪽(Feature)이 한다.
/// - 구매(광고 제거) 여부는 묻지 않는다 — 판정은 Feature 가 한다.
public protocol BackupExporting: Sendable {
    /// 백업 파일을 만든다. 파일 이름은 기본 이름(「새기다 필사 백업 YYYY-MM-DD.carvebackup」)이다.
    /// - Parameters:
    ///   - password: 사용자 암호 원문(8자 이상 · 두 번 입력 확인은 화면이 한다). 저장 · 기록하지 않는다.
    ///   - progress: 장 단위 진행. 시작할 때 `done == 0` 으로 한 번, 장을 마칠 때마다 한 번 부른다.
    /// - Returns: 다 쓰고 다시 열어 대조까지 마친 파일. 파일은 앱의 작업 폴더에 있다 — 사용자가 저장 위치를 고른 뒤 `discard(_:)` 로 지운다.
    /// - Throws: `BackupExportError`, 취소면 `CancellationError`. 실패 · 취소면 작업 폴더를 지우고 파일을 내놓지 않는다.
    func export(password: String, progress: @Sendable (BackupProgress) async -> Void) async throws -> BackupExportResult

    /// 백업 파일을 만든다 — 파일 이름을 부르는 쪽이 정한다.
    /// - Parameter fileName: 만들 파일의 이름. nil 이거나 쓸 수 없는 이름이면 기본 이름이다. 확장자가 없으면 `.carvebackup` 을 붙인다.
    ///   기본 구현은 이름을 무시하고 `export(password:progress:)` 를 부른다(시험 대역용) — `LiveBackupExporter` 는 이름을 따른다.
    func export(password: String, fileName: String?, progress: @Sendable (BackupProgress) async -> Void) async throws -> BackupExportResult

    /// 내보낸 파일과 그 작업 폴더를 지운다 — 사용자가 저장 위치를 고른 뒤(저장 · 취소 · 실패 모두) 부른다(설계 §3-1 9단계).
    /// 기본 구현은 아무것도 하지 않는다(시험 대역용). 지우지 못해도 다음 앱 시작의 `BackupWorkDirectory.removeStale()` 이 지운다.
    func discard(_ result: BackupExportResult) async
}

public extension BackupExporting {
    func export(password: String, fileName: String?, progress: @Sendable (BackupProgress) async -> Void) async throws -> BackupExportResult {
        try await export(password: password, progress: progress)
    }

    func discard(_ result: BackupExportResult) async {}
}

/// 다 만든 백업 파일 (설계 §3-1 8단계).
public struct BackupExportResult: Equatable, Sendable {
    /// 암호화한 백업 파일 — 앱의 작업 폴더(`BackupWork/<UUID>/`) 안이다. 사용자가 고른 곳으로 옮긴 뒤 `discard` 로 지운다.
    public let fileURL: URL
    /// 담은 행 · 초안 · blob 의 수(manifest 의 `counts` 와 같다).
    public let counts: BackupCounts
    /// 이 백업의 UUID 문자열(manifest 의 `backupID` 와 같다).
    public let backupID: String

    /// 결과를 묶는다.
    public init(fileURL: URL, counts: BackupCounts, backupID: String) {
        self.fileURL = fileURL
        self.counts = counts
        self.backupID = backupID
    }
}

/// 내보내기 실패 (설계 §3-1 5 · 6단계). 파일은 내놓지 않고 작업 폴더를 지운 뒤 던진다. 암호 · 평문 바이트는 담지 않는다.
public enum BackupExportError: Error, Equatable, Sendable {
    /// 장 사이에 저장소 세대가 바뀌었다 — 그 사이 「모든 필사 삭제」 가 있었다. 다시 시도하면 지금 저장소로 처음부터 만든다.
    case generationChanged
    /// 장 사이에 계정 상태 · 저장소 소유 · 여는 초안 묶음이 바뀌었다 — 두 계정의 초안이 한 파일에 섞이지 않게 멈췄다.
    case accountChanged
    /// 저장소의 필사 행을 읽지 못했다.
    case storeUnreadable
    /// 초안을 읽지 못한 장이 있다 — 그 장을 조용히 빼지 않고 멈췄다(설계 §3-4). 「확인이 필요한 필기」 에서 그 파일을 볼 수 있다.
    case draftsUnreadable
    /// 작업 폴더 · 백업 파일을 쓸 공간이 모자란다.
    case insufficientSpace
    /// 작업 폴더 · 백업 파일을 쓰지 못했다(공간 부족 밖의 입출력 실패).
    case writeFailed
    /// 다 쓴 파일을 같은 암호로 다시 열어 대조한 결과가 맞지 않는다(설계 §3-1 6단계).
    case verificationFailed
}

/// 내보내기 진행 — 장 단위다.
public struct BackupProgress: Equatable, Sendable {
    /// 마친 장 수.
    public let done: Int
    /// 읽을 장 수(행이 있는 장 ∪ 여는 묶음에 초안이 있는 장).
    public let total: Int

    /// 진행을 만든다.
    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}

/// 백업 파일의 기본 이름 — 「새기다 필사 백업 YYYY-MM-DD.carvebackup」 (설계 §3-1 7단계).
public enum BackupExportFileName {
    /// 이름 앞부분.
    public static let prefix = "새기다 필사 백업"

    /// 기본 이름. 날짜는 그레고리력 · 주어진 시간대의 연-월-일이다.
    /// - Parameters:
    ///   - date: 만든 날(리듀서는 `@Dependency(\.date)` 의 `date.now`).
    ///   - timeZone: 날짜를 읽을 시간대. 기본은 기기의 시간대.
    /// - Returns: 예: `새기다 필사 백업 2026-10-06.carvebackup`. 부작용 없음.
    public static func defaultName(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = [padded(parts.year ?? 0, width: 4), padded(parts.month ?? 0, width: 2), padded(parts.day ?? 0, width: 2)]
            .joined(separator: "-")
        return "\(prefix) \(day).\(BackupFormat.fileExtension)"
    }

    /// 부르는 쪽이 준 이름을 파일 이름으로 쓸 수 있게 다듬는다 — 경로 구분자(`/` · `:`)를 바꾸고, 앞의 `.`(숨김 · `..`)과 앞뒤 공백을 떼고,
    /// 확장자가 없으면 `.carvebackup` 을 붙인다.
    /// - Returns: 다듬은 이름. 남는 것이 없으면 nil — 부르는 쪽이 기본 이름을 쓴다. 부작용 없음.
    static func sanitized(_ name: String?) -> String? {
        guard let name else { return nil }
        var cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let suffix = "." + BackupFormat.fileExtension
        if !cleaned.lowercased().hasSuffix(suffix) {
            cleaned += suffix
        }
        return cleaned
    }

    /// 0 을 앞에 채운 숫자.
    private static func padded(_ value: Int, width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(width - digits.count, 0)) + digits
    }
}

private enum BackupExporterKey: DependencyKey {
    /// 앱이 이 실행의 저장소 actor · 편집 환경 · 보존 영역으로 만든 `LiveBackupExporter` 를 주입한다(`App.swift`). 없으면 백업을 만들 수 없다.
    static let liveValue: (any BackupExporting)? = nil
    /// 시험 기본값 — 저장소를 건드리지 않는다(공유 SwiftData actor 를 쓰지 않는다). 내보내기를 보는 시험이 대역을 넣는다.
    static let testValue: (any BackupExporting)? = nil
}

public extension DependencyValues {
    /// 「백업 만들기」 — 필사 백업 파일 내보내기.
    var backupExporter: (any BackupExporting)? {
        get { self[BackupExporterKey.self] }
        set { self[BackupExporterKey.self] = newValue }
    }
}
