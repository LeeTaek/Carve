//
//  BackupDiskSpace.swift
//  Domain
//
//  백업 쓰기 · 풀기 전에 남은 공간을 본다 — 공간 부족을 쓰다가 실패하기 전에 알린다.
//

import Foundation

/// 남은 공간 읽기. `volumeAvailableCapacityForImportantUsage` 는 필수 사유 API(DiskSpace)다 — 개인정보 매니페스트에 사유를 선언한다.
enum BackupDiskSpace {
    /// 그 경로가 있는 볼륨에서 사용자가 시작한 중요한 쓰기에 쓸 수 있는 바이트.
    /// - 입력: 이미 있는 파일 · 폴더 경로
    /// - 출력: 바이트 수. 읽지 못하면 nil — 부르는 쪽은 판정을 건너뛴다
    /// - 부작용: 없음
    static func availableCapacity(at url: URL) -> Int64? {
        try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }
}
