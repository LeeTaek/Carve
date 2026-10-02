//
//  BackupFormatItemIDTesting.swift
//  DomainTest
//
//  필사 백업 형식 — 항목 id(설계 §2-5)의 결정성과 구성요소 경계.
//

import Foundation
import Testing

@testable import Domain

@Suite("백업 형식 — 항목 id")
struct BackupFormatItemIDTesting {

    private let rowUUID = "5C0E5D0B-2F7A-4C55-9D51-0E1B9C2E7A10"

    /// 다른 구현(Python hashlib)으로 계산한 값 — 형식이 바뀌면 이 값이 깨진다.
    @Test("알려진 입력은 늘 같은 id 다")
    func knownVectorsAreStable() {
        #expect(
            BackupItemID.make(kind: .row, sourceKey: rowUUID, fingerprint: nil)
                == "row-d90a394f7b558515fafcee8c6811da45b9378eb3ed5513218d445afcd3c2cbf6"
        )
        let draftKey = BackupItemID.draftSourceKey(
            draftScope: "local", sessionID: "S1", translation: "NKRV", title: "1-01Genesis.txt", chapter: 1, verse: 4, revision: 7
        )
        #expect(draftKey == "local|S1|NKRV|1-01Genesis.txt|1|4|7")
        #expect(
            BackupItemID.make(kind: .draft, sourceKey: draftKey, fingerprint: "vc1-abc")
                == "draft-3cc0d0bf267cc5e91fe1487c2979f71b5b22ca46d04f0c545ff96da102897573"
        )
    }

    @Test("같은 입력은 같은 id, 모양은 종류 접두 + 소문자 hex 64자")
    func idIsDeterministicAndWellFormed() {
        let first = BackupItemID.make(kind: .row, sourceKey: rowUUID, fingerprint: "vc1-1234")
        let second = BackupItemID.make(kind: .row, sourceKey: rowUUID, fingerprint: "vc1-1234")
        let draft = BackupItemID.make(kind: .draft, sourceKey: rowUUID, fingerprint: "vc1-1234")

        #expect(first == second)
        #expect(first.hasPrefix("row-"))
        #expect(BackupFormat.isBlobName(String(first.dropFirst("row-".count))))
        #expect(draft.hasPrefix("draft-"))
        // 종류는 접두만이 아니라 해시 입력에도 들어간다.
        #expect(draft.dropFirst("draft-".count) != first.dropFirst("row-".count))
    }

    @Test("정규 문자열은 구성요소마다 UTF-8 바이트 길이를 앞에 붙인다")
    func canonicalStringPrefixesUTF8Lengths() {
        #expect(
            BackupItemID.canonical(kind: .row, sourceKey: rowUUID, fingerprint: "vc1-x")
                == "18:carve.backupItem/1|3:row|36:\(rowUUID)|5:vc1-x"
        )
        // 문자 수(3)가 아니라 UTF-8 바이트 수(9)다.
        #expect(BackupItemID.canonical(kind: .draft, sourceKey: "창세기", fingerprint: nil) == "18:carve.backupItem/1|5:draft|9:창세기|5:empty")
    }

    @Test("구분자를 품은 값이 경계를 넘어도 id 가 갈린다")
    func separatorsInsideComponentsDoNotCollide() {
        // 길이 접두가 없으면 둘 다 "…|A|B|C" 가 된다.
        let first = BackupItemID.make(kind: .row, sourceKey: "A|B", fingerprint: "C")
        let second = BackupItemID.make(kind: .row, sourceKey: "A", fingerprint: "B|C")
        #expect(first != second)
    }

    @Test("지문이 없으면 \"empty\" 자리이고, 내용이 바뀌면 id 가 바뀐다")
    func missingFingerprintUsesEmptyAndContentChangesTheID() {
        let cleared = BackupItemID.make(kind: .row, sourceKey: rowUUID, fingerprint: nil)
        let withInk = BackupItemID.make(kind: .row, sourceKey: rowUUID, fingerprint: "vc1-aaaa")
        let otherInk = BackupItemID.make(kind: .row, sourceKey: rowUUID, fingerprint: "vc1-bbbb")

        #expect(BackupItemID.canonical(kind: .row, sourceKey: rowUUID, fingerprint: nil).hasSuffix("|5:empty"))
        #expect(cleared == BackupItemID.make(kind: .row, sourceKey: rowUUID, fingerprint: BackupItemID.emptyFingerprint))
        #expect(cleared != withInk)
        // 같은 행이 다른 내용이 되면 다른 id 다(정책 §12-5 C5).
        #expect(withInk != otherInk)
    }

    @Test("행 키가 다르면 같은 내용도 다른 id 다")
    func differentRowsHaveDifferentIDs() {
        let fingerprint = "vc1-same"
        #expect(
            BackupItemID.make(kind: .row, sourceKey: rowUUID, fingerprint: fingerprint)
                != BackupItemID.make(kind: .row, sourceKey: "1-01Genesis.txt.1.3.1773450123", fingerprint: fingerprint)
        )
    }
}
