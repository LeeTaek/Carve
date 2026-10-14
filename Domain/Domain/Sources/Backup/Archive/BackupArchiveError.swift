//
//  BackupArchiveError.swift
//  Domain
//
//  백업 파일(Apple Encrypted Archive) 쓰기 · 풀기 오류 — 설계 docs/backup-import-design.md §2-1 · §2-8 · §4-2.
//

import Foundation

/// 백업 컨테이너(`BackupArchive`)가 던지는 오류. 암호 · 평문 바이트는 담지 않는다.
public enum BackupArchiveError: Error, Equatable, Sendable {
    /// 암호가 맞지 않거나 파일이 변조 · 잘림 · 손상됐다 — 셋을 구분하지 않는다(설계 §2-1).
    case wrongPasswordOrDamaged
    /// 허용 밖 항목(다른 이름 · 경로 이탈 · 절대 경로 · 링크 · 종류가 맞지 않음 · 중복 · 모르는 바이트 필드)을 만나 멈췄다.
    /// `name` 은 그 항목의 아카이브 안 경로(준비 폴더라면 상대 경로) 원문이고, 길면 앞부분만 담는다.
    case entryRejected(name: String)
    /// 항목 하나의 바이트 또는 풀린 바이트 합계가 상한을 넘었다.
    case tooLarge
    /// 쓸 곳의 남은 공간이 모자란다.
    case insufficientSpace
    /// 파일을 열거나 읽거나 쓰지 못했다(위 사유 밖의 입출력 실패).
    case ioFailed
}

extension BackupArchiveError {
    /// 오류에 담는 항목 이름의 최대 길이 — 파일이 정한 임의 길이의 문자열을 그대로 들고 다니지 않는다.
    static let rejectedNameLimit = 256

    /// 항목 이름을 담은 `entryRejected` — 이름이 길면 앞부분만 담는다.
    static func rejected(_ name: String) -> BackupArchiveError {
        .entryRejected(name: String(name.prefix(rejectedNameLimit)))
    }
}
