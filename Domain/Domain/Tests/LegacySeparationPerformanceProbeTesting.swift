//
//  LegacySeparationPerformanceProbeTesting.swift
//  DomainTest
//
//  SEP-6 — 게이트의 시작 시간 · 메모리 (테스트 계획 §3-3). **매 실행 전체 검사**(D4)가 큰 저장소에서 얼마나 드는지 잰다.
//
//  시험 번들 옆 `sep6/plan.json` 이 있을 때만 돈다 — 정규 시험을 느리게 하지 않는다.
//      {"counts":[1000,5000,31102],"inkBytes":2000,"unlinkedCounts":[100,1000]}
//  `counts` 는 **모두 대응 있음**(동기화하던 사용자의 매 실행 — 연결 경로), `unlinkedCounts` 는 **모두 대응 없음**(무계정 1.3.0 — 분리본을 쓰는 경로).
//  결과는 `sep6/report.txt`.
//

import Darwin
import Foundation
import SwiftData
import Testing

@testable import Domain

@Suite("SEP-6 · 게이트 성능 손")
struct LegacySeparationPerformanceProbeTesting {

    private final class BundleAnchor {}

    private static var dropbox: String {
        Bundle(for: BundleAnchor.self).bundleURL.deletingLastPathComponent().appendingPathComponent("sep6", isDirectory: true).path
    }

    private struct Plan: Decodable {
        var counts: [Int]?
        var unlinkedCounts: [Int]?
        var inkBytes: Int?
    }

    @Test("큰 저장소에서 게이트의 판정 · 보존 시간과 메모리를 잰다 — sep6/plan.json 이 있을 때만 돈다")
    func measure() throws {
        guard let data = FileManager.default.contents(atPath: Self.dropbox + "/plan.json"),
              let plan = try? JSONDecoder().decode(Plan.self, from: data) else {
            withKnownIssue("sep6/plan.json 이 없다", isIntermittent: true) { Issue.record("지시서 없음") }
            return
        }
        let ink = plan.inkBytes ?? 2_000
        var lines = ["SEP-6 게이트 성능 — OS \(ProcessInfo.processInfo.operatingSystemVersionString) · 필기 \(ink)바이트/행"]
        lines.append("  | 행 | 대응 | 저장소 | 사본+판정 | 게이트 전체 | 재실행 | 분리본 파일 · 크기 | 메모리 증가(최대) |")
        for count in plan.counts ?? [] {
            lines.append(try run(count: count, linked: true, ink: ink))
        }
        for count in plan.unlinkedCounts ?? [] {
            lines.append(try run(count: count, linked: false, ink: ink))
        }
        let report = lines.joined(separator: "\n")
        print(report)
        try? report.write(toFile: Self.dropbox + "/report.txt", atomically: true, encoding: .utf8)
        #expect(lines.count > 2)
    }

    private func run(count: Int, linked: Bool, ink: Int) throws -> String {
        let directory = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Carve.sqlite")
        try seed(url, count: count, ink: ink)
        try LinkageFixture.ensureMirroringTables(url)
        if linked {
            try LinkageFixture.exec(url, """
            INSERT INTO ANSCKRECORDMETADATA (Z_ENT, Z_OPT, ZENTITYID, ZENTITYPK, ZNEEDSUPLOAD, ZNEEDSCLOUDDELETE, ZNEEDSLOCALDELETE, ZCKRECORDNAME)
            SELECT 17012, 1, (SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'BibleDrawing'), Z_PK, 0, 0, 0, hex(randomblob(16)) FROM ZBIBLEDRAWING;
            """)
            try LinkageFixture.addIdentityKeys(url)
        }
        let storeBytes = Self.size(of: directory)
        let area = PreservationArea(root: directory.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite")
        var gate = LegacySeparationGate(area: area)
        gate.reader.osMajor = 26

        let clock = ContinuousClock()
        let judgeStart = clock.now
        let reading = gate.reader.judge(storeAt: url)
        let judged = clock.now - judgeStart

        let sampler = FootprintSampler()
        sampler.start()
        let gateStart = clock.now
        let decision = gate.decide(storeURL: url)
        let total = clock.now - gateStart
        let peak = sampler.stop()
        // 재실행 — 같은 저장소 · 같은 대상이면 이미 있는 기록을 쓴다(매 실행 전체 검사, D4).
        let rerunStart = clock.now
        let again = gate.decide(storeURL: url)
        let rerun = clock.now - rerunStart
        #expect(again.hold?.jobID == decision.hold?.jobID)

        let files = (FileManager.default.enumerator(atPath: area.separationDirectory.path)?.allObjects.count) ?? 0
        let expected = linked ? decision == .connect(reading) : decision.hold?.reason == .unlinkedRowsAwaitSeparation(count: count)
        #expect(expected, "판정이 기대와 다르다: \(reading.summary)")
        let timings = "\(Self.milliseconds(judged)) | \(Self.milliseconds(total)) | \(Self.milliseconds(rerun))"
        return "  | \(count) | \(linked ? "모두 있음" : "모두 없음") | \(Self.megabytes(storeBytes)) | \(timings) | "
            + "\(files)개 · \(Self.megabytes(Self.size(of: area.separationDirectory))) | \(Self.megabytes(peak)) |"
    }

    /// 앱 스키마로 행을 넣는다. 필기 바이트는 행마다 조금씩 다르게 — 같은 내용이 되지 않게.
    private func seed(_ url: URL, count: Int, ink: Int) throws {
        let container = try ModelContainer(
            for: AppStoreSchema.schema, migrationPlan: DrawingDataMigrationPlan.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let chapter = BibleChapter(title: .psalms, chapter: 119)
        for index in 0 ..< count {
            let bytes = Data((0 ..< ink).map { UInt8(truncatingIfNeeded: ($0 &* 31) &+ index) })
            context.insert(BibleDrawing(bibleTitle: chapter, verse: index + 1, lineData: bytes, rowUUID: "perf-\(index)"))
            if index % 2_000 == 1_999 { try context.save() }
        }
        try context.save()
    }

    private static func size(of directory: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return walker.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }.reduce(0) { $0 + Int64($1) }
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return String(format: "%.0fms", Double(seconds) * 1_000 + Double(attoseconds) / 1e15)
    }

    private static func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1fMB", Double(bytes) / 1_048_576)
    }
}

/// 게이트가 도는 동안 프로세스 메모리(phys_footprint)의 **증가분 최댓값**을 5ms 마다 잰다.
private final class FootprintSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private var baseline: UInt64 = 0
    private var peak: UInt64 = 0
    private var thread: Thread?

    func start() {
        baseline = Self.footprint()
        peak = baseline
        running = true
        let thread = Thread { [weak self] in
            while let self, self.isRunning {
                let value = Self.footprint()
                self.lock.lock(); self.peak = max(self.peak, value); self.lock.unlock()
                usleep(5_000)
            }
        }
        self.thread = thread
        thread.start()
    }

    private var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    /// - Returns: 시작 때보다 늘어난 최댓값(바이트).
    func stop() -> Int64 {
        let value = Self.footprint()
        lock.lock()
        running = false
        peak = max(peak, value)
        let result = Int64(peak) - Int64(baseline)
        lock.unlock()
        usleep(10_000)
        return max(0, result)
    }

    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
