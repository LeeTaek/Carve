//
//  ChapterCanvasMemoryProbe.swift
//  CarveFeature
//
//  R20 진단 — 회전 시 전이 peak 이 **jetsam 한도까지 얼마나 근접하는가** (2026-09-09 신설).
//
//  ## 왜 footprint 만으로는 부족한가
//  Instruments 의 `memory-physical-footprint` 는 "얼마나 썼는가" 만 말한다. 죽는지 아닌지는
//  **그 기기의 한도까지 얼마나 남았는가**로 정해지고, 한도는 기기 RAM 에 따라 다르다.
//  보유 기기(8 GB)에서 1.8 GiB 를 봐도 4 GB 기기에서 위험한지 알 수 없었던 이유가 이것이다.
//
//  `os_proc_available_memory()` 는 **한도까지 남은 바이트**를 돌려준다. peak 순간의 이 값과
//  그때의 footprint 를 함께 보면 한도 자체를 역산할 수 있고(대략 `footprint + available`),
//  한도가 RAM 에 대체로 비례하므로 저메모리 기기의 여유를 **추정**할 수 있다.
//  ⚠️ 추정이지 예측이 아니다. 실제 확인은 배포 후 MetricKit 의
//  `MXAppExitMetric.cumulativeMemoryResourceLimitExitCount` 로 한다.
//

#if DEBUG
import CarveToolkit
import Darwin
import Foundation
import os

/// 100 ms 간격으로 footprint 와 잔여 메모리를 재고, **최저 여유를 갱신할 때만** 찍는다.
@MainActor
final class ChapterCanvasMemoryProbe {
    static let launchArgument = "-CanvasMemoryProbe"

    private var polling: Task<Void, Never>?
    private var lowestAvailable = Int.max
    private var highestFootprint: UInt64 = 0

    init() {
        print("MemoryProbe start limitEstimate=\(Self.megabytes(Self.available() + Int(Self.footprint()))) MB")
        polling = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled else { return }
                self.sample()
            }
        }
    }

    deinit { polling?.cancel() }

    private func sample() {
        let available = Self.available()
        let footprint = Self.footprint()
        var changed = false
        if available < lowestAvailable { lowestAvailable = available; changed = true }
        if footprint > highestFootprint { highestFootprint = footprint; changed = true }
        guard changed else { return }
        // 한도 = 지금 쓴 것 + 남은 것. 샘플마다 조금씩 흔들리므로 참고값이다.
        let limit = Int(footprint) + available
        print("MemoryProbe footprint=\(Self.megabytes(Int(footprint))) MB"
            + " available=\(Self.megabytes(available)) MB"
            + " limit≈\(Self.megabytes(limit)) MB"
            + " headroom=\(String(format: "%.1f", Double(available) / Double(max(limit, 1)) * 100))%")
    }

    /// jetsam 한도까지 남은 바이트.
    private static func available() -> Int { os_proc_available_memory() }

    /// Instruments 의 `memory-physical-footprint` 와 같은 값.
    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    private static func megabytes(_ bytes: Int) -> String { String(format: "%.1f", Double(bytes) / 1_048_576) }
}
#endif
