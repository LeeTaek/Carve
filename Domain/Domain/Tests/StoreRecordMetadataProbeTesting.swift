//
//  StoreRecordMetadataProbeTesting.swift
//  DomainTest
//
//  SEP-0 — 공개 API 타당성 (테스트 계획 §3-3, 정책 §12-6 C14 ②).
//
//  C14 의 판정은 "행별 미러링 레코드 대응" 을 읽어야 한다. 사설 테이블을 직접 읽기 **전에**, Core Data 의 공개
//  API(`NSPersistentCloudKitContainer.recordID(for:)`)를 **미러링을 켜지 않고** 쓸 수 있는지부터 본다.
//
//  세 가지를 함께 본다 — ① 유효한 대응을 돌려주는가 ② 호출이 저장소 파일을 바꾸지 않는가 ③ 미러링이 깨어나지 않는가.
//  ③ 은 이 시험만으로는 다 볼 수 없다(네트워크 · 이벤트는 앱 실행에서 본다). 여기서는 ① · ② 와 "무엇을 돌려주는지" 를 기록한다.
//
//  표본이 있어야 돌아간다 — 환경 변수 `SEP0_STORE` 에 **동기화된 저장소의 사본 경로**를 준다. 없으면 건너뛴다.
//      SEP0_STORE=/path/Carve.dev.sqlite  xcodebuild test -only-testing:DomainTest/StoreRecordMetadataProbeTesting …
//

import CoreData
import CryptoKit
import Foundation
import SwiftData
import Testing

@testable import Domain

/// 이 파일이 가르는 것은 **판독기를 공개 API 로 만들 수 있는가**다. 되면 사설 스키마 의존이 사라지고,
/// 안 되면 사설 판독기를 쓰되 검증한 범위 밖을 「알 수 없음」 으로 두어야 한다(C14 ②).
@Suite("SEP-0 · 미러링 대응 판독")
struct StoreRecordMetadataProbeTesting {

    /// 표본 저장소. 없으면 이 파일의 시험을 건너뛴다.
    ///
    /// 시험 프로세스에는 호스트 환경 변수가 닿지 않는 경우가 있어(`TEST_RUNNER_…` 무시됨, 2026-09-21 확인)
    /// **기기의 `/tmp/sep0`** 도 함께 본다 — 호스트의
    /// `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/tmp/sep0` 와 같은 자리다.
    private static var samplePath: String? {
        if let given = ProcessInfo.processInfo.environment["SEP0_STORE"], given.isEmpty == false { return given }
        for dropbox in Self.dropboxes {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dropbox)) ?? []
            if let first = names.filter({ $0.hasSuffix(".sqlite") }).sorted().first {
                return dropbox + "/" + first
            }
        }
        return nil
    }

    /// 표본을 놓아 둘 수 있는 자리. **시험 번들 옆의 `sep0`** 이 기본이다 — 빌드 산출물 폴더라 세션마다 경로가 달라도
    /// 시험이 스스로 찾는다.
    private static var dropboxes: [String] {
        let beside = Bundle(for: BundleAnchor.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("sep0", isDirectory: true).path
        return [beside, "/tmp/sep0"]
    }

    /// 번들 자리를 찾기 위한 앵커.
    private final class BundleAnchor {}

    /// 저장소 한 벌(본 파일 · WAL · SHM · 외부 저장 폴더)을 임시 자리에 복사한다. **원본은 읽기만 한다.**
    private func copyStore(from source: URL) throws -> URL {
        let directory = URL.temporaryDirectory.appendingPathComponent("sep0-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: source.path + suffix)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            try FileManager.default.copyItem(at: from, to: URL(fileURLWithPath: destination.path + suffix))
        }
        let support = source.deletingLastPathComponent()
            .appendingPathComponent(".\(source.deletingPathExtension().lastPathComponent)_SUPPORT", isDirectory: true)
        if FileManager.default.fileExists(atPath: support.path) {
            try FileManager.default.copyItem(at: support, to: directory.appendingPathComponent(support.lastPathComponent, isDirectory: true))
        }
        return destination
    }

    /// 파일 한 벌의 지문 — 호출 전후를 견주어 "저장소를 바꾸지 않았다" 를 확인한다.
    private func fingerprints(of store: URL) -> [String: String] {
        var result: [String: String] = [:]
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: store.path + suffix)
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            result[url.lastPathComponent] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        return result
    }

    /// 미러링을 **켜지 않고** 연다. `cloudKitContainerOptions = nil` 이 그 뜻이다.
    private func openWithoutMirroring(_ store: URL, readOnly: Bool) throws -> NSPersistentCloudKitContainer {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: AppStoreSchema.models) else {
            throw ProbeFailure.modelUnavailable
        }
        let container = NSPersistentCloudKitContainer(name: "SEP0Probe", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: store)
        description.cloudKitContainerOptions = nil
        description.setOption(readOnly as NSNumber, forKey: NSReadOnlyPersistentStoreOption)
        // 마이그레이션을 이 자리에서 일으키지 않는다 — 표본은 이미 앱 스키마로 열린 저장소여야 한다.
        description.shouldMigrateStoreAutomatically = false
        description.shouldInferMappingModelAutomatically = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }

    private enum ProbeFailure: Error { case modelUnavailable }

    /// 엔티티마다 행을 세고, 그 행의 `recordID(for:)` 가 값을 주는지 본다.
    private func probe(_ container: NSPersistentCloudKitContainer) -> [String: (rows: Int, withRecordID: Int, sample: String?)] {
        var report: [String: (rows: Int, withRecordID: Int, sample: String?)] = [:]
        let context = container.newBackgroundContext()
        context.performAndWait {
            for entity in container.managedObjectModel.entities {
                guard let name = entity.name else { continue }
                let request = NSFetchRequest<NSManagedObject>(entityName: name)
                request.fetchLimit = 500
                guard let objects = try? context.fetch(request) else {
                    report[name] = (rows: -1, withRecordID: -1, sample: "조회 실패")
                    continue
                }
                var withID = 0
                var sample: String?
                for object in objects {
                    guard let recordID = container.recordID(for: object.objectID) else { continue }
                    withID += 1
                    // 레코드 이름은 계정 식별이 아니지만, 기록에는 앞 8자만 남긴다.
                    if sample == nil { sample = String(recordID.recordName.prefix(8)) + "…" }
                }
                report[name] = (rows: objects.count, withRecordID: withID, sample: sample)
            }
        }
        return report
    }

    @Test("공개 API 로 대응을 읽을 수 있는가 — 표본이 있을 때만 돈다")
    func readsRecordIDWithoutMirroring() throws {
        guard let path = Self.samplePath else {
            withKnownIssue("SEP0_STORE 가 없다 — 표본 저장소를 주면 돈다", isIntermittent: true) {
                Issue.record("표본 없음")
            }
            return
        }
        let original = URL(fileURLWithPath: path)
        let copy = try copyStore(from: original)
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }

        let before = fingerprints(of: copy)

        // 읽기 전용으로 먼저 시도하고, 열리지 않으면 사본을 읽고 쓰며 연다(사본이므로 원본은 안전하다).
        var readOnly = true
        var container: NSPersistentCloudKitContainer
        do {
            container = try openWithoutMirroring(copy, readOnly: true)
        } catch {
            readOnly = false
            container = try openWithoutMirroring(copy, readOnly: false)
        }

        let report = probe(container)
        let after = fingerprints(of: copy)

        var lines = ["SEP-0 결과", "  읽기 전용으로 열림: \(readOnly)"]
        for (name, value) in report.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(name): 행 \(value.rows) · 대응 있음 \(value.withRecordID) · 표본 \(value.sample ?? "없음")")
        }
        lines.append("  파일 지문 그대로: \(before == after)")
        for name in Set(before.keys).union(after.keys).sorted() where before[name] != after[name] {
            lines.append("    바뀐 파일: \(name) (\(before[name] == nil ? "없다가 생김" : after[name] == nil ? "사라짐" : "내용 바뀜"))")
        }
        print(lines.joined(separator: "\n"))

        // 판정 기준 ② — 판독이 저장소를 바꾸지 않아야 한다. 읽기 전용으로 열렸을 때만 강제한다.
        // 읽기 전용으로 열어도 파일이 바뀌는지는 **관측 결과**로 남긴다(2026-09-21: 바뀐다).
        // 그래서 C14 의 판정은 본 저장소가 아니라 사본에서 한다.
        if readOnly && before != after {
            Comment(rawValue: "읽기 전용 판독이 파일을 바꿨다 — 판정은 사본에서 해야 한다")
        }
        // ① 은 값으로 판정하지 않고 기록한다 — 표본에 동기화된 행이 있어야 의미가 있다.
        #expect(report.isEmpty == false)
    }
}
