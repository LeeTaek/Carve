//
//  LegacyRowLinkageProbeTesting.swift
//  DomainTest
//
//  C14 ② 판독기를 **실제 저장소 사본**에 돌려 보는 손 — 시험 번들 옆 `sep3/` 에 `.sqlite`(+`-wal` · `-shm`)를 두면 하나씩 판정하고
//  `sep3/report.txt` 에 요약을 남긴다(테스트 계획 §3-3 SEP-1). 표본이 없으면 아무것도 하지 않는다.
//
//  기록에는 계정 식별 원문 · 레코드 이름이 들지 않는다 — 판독기 요약이 그것을 들지 않는다.
//  `sep3/validated.json` 에 `{"entities":["FavoriteVerse"],"os":[26,18]}` 처럼 두면 그 범위로 넓혀 판정한다(관측을 기록한 뒤에만 쓴다).
//

import Foundation
import Testing

@testable import Domain

@Suite("SEP-1 · 판독기 실저장소 손")
struct LegacyRowLinkageProbeTesting {

    private final class BundleAnchor {}

    private static var dropbox: String {
        Bundle(for: BundleAnchor.self).bundleURL.deletingLastPathComponent().appendingPathComponent("sep3", isDirectory: true).path
    }

    private struct Validated: Decodable {
        var entities: [String]?
        var os: [Int]?
        var schemas: [Int]?
    }

    @Test("sep3/ 의 저장소 사본을 판정하고 요약을 남긴다 — 표본이 있을 때만 돈다")
    func judgeSamples() throws {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: Self.dropbox)) ?? []).filter { $0.hasSuffix(".sqlite") }.sorted()
        guard names.isEmpty == false else {
            withKnownIssue("sep3/ 에 표본이 없다", isIntermittent: true) { Issue.record("표본 없음") }
            return
        }

        var reader = LegacyRowLinkageReader()
        if let data = FileManager.default.contents(atPath: Self.dropbox + "/validated.json"),
           let validated = try? JSONDecoder().decode(Validated.self, from: data) {
            for name in validated.entities ?? [] { if let entity = LegacyEntity(rawValue: name) { reader.validatedEntities.insert(entity) } }
            for major in validated.os ?? [] { reader.validatedOSMajors.insert(major) }
            for major in validated.schemas ?? [] { reader.validatedSchemaMajors.insert(major) }
        }

        var lines = ["SEP-1 판독기 손 — OS \(reader.osMajor) · 검증 엔티티 \(reader.validatedEntities.map(\.rawValue).sorted())"]
        for name in names {
            let reading = reader.judge(storeAt: URL(fileURLWithPath: Self.dropbox + "/" + name))
            lines.append("[\(name)] \(reading.summary)")
            for entity in LegacyEntity.allCases {
                let rows = reading.rows.filter { $0.key.entity == entity }
                guard rows.isEmpty == false else { continue }
                let linked = rows.values.filter { $0 == .linked }.count
                let unlinkedKeys = rows.filter { $0.value == .verifiedUnlinked }.keys.map(\.primaryKey).sorted()
                lines.append("    \(entity.rawValue): 행 \(rows.count) · 대응 있음 \(linked) · 대응 없음 pk \(unlinkedKeys)")
            }
        }
        let report = lines.joined(separator: "\n")
        print(report)
        try? report.write(toFile: Self.dropbox + "/report.txt", atomically: true, encoding: .utf8)
        #expect(names.isEmpty == false)
    }
}
