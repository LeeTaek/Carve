//
//  VerseContentFingerprintTesting.swift
//  DomainTest
//
//  내용 지문 — 같은 필기는 기기 · 버전이 달라도 같은 지문이어야 한다 (F18, 정책 §12-6).
//

import Foundation
import Testing

@testable import Domain

/// 지문이 갈리면 복구 사본 blob 을 공유하지 못하고 legacy 보존도 같은 내용을 둘로 본다.
/// 그 원인이 되는 **JSON 키 순서 차이(F18)** 를 여기서 막는다.
@Suite("절 내용 지문")
struct VerseContentFingerprintTesting {

    private let metadataInOneOrder = Data("""
    {"metadataSchemaVersion":1,"baseWritingWidth":300,"baseWritingHeight":400,\
    "baseUnderlineAnchors":[0,30],"layoutSignature":"cl2-abc"}
    """.utf8)

    private let metadataInAnotherOrder = Data("""
    {"layoutSignature":"cl2-abc","baseUnderlineAnchors":[0,30],"baseWritingHeight":400,\
    "baseWritingWidth":300,"metadataSchemaVersion":1}
    """.utf8)

    @Test("메타데이터 키 순서가 달라도 같은 지문이다")
    func keyOrderDoesNotChangeTheFingerprint() {
        let line = Data("stroke".utf8)
        let first = VerseContentFingerprint.make(lineData: line, drawingVersion: 3, layoutMetadataBlob: metadataInOneOrder)
        let second = VerseContentFingerprint.make(lineData: line, drawingVersion: 3, layoutMetadataBlob: metadataInAnotherOrder)

        #expect(first == second)
        #expect(first.hasPrefix("vc1-"))
    }

    @Test("획 · 좌표 형식이 다르면 다른 지문이다")
    func contentAndCoordinateFormatSeparateTheFingerprint() {
        let base = VerseContentFingerprint.make(lineData: Data("a".utf8), drawingVersion: 3, layoutMetadataBlob: metadataInOneOrder)
        let otherLine = VerseContentFingerprint.make(lineData: Data("b".utf8), drawingVersion: 3, layoutMetadataBlob: metadataInOneOrder)
        // 같은 획이라도 좌표 형식이 다르면 화면에서 다른 위치다(F12 · R28).
        let otherFormat = VerseContentFingerprint.make(lineData: Data("a".utf8), drawingVersion: 2, layoutMetadataBlob: metadataInOneOrder)

        #expect(base != otherLine)
        #expect(base != otherFormat)
    }

    @Test("빈 내용과 내용 없음을 구분한다")
    func emptyContentIsNotTheSameAsMissingContent() {
        let missing = VerseContentFingerprint.make(lineData: nil, drawingVersion: nil, layoutMetadataBlob: nil)
        let empty = VerseContentFingerprint.make(lineData: Data(), drawingVersion: nil, layoutMetadataBlob: nil)

        #expect(missing != empty)
    }

    /// 형식을 모르면 정규화한 척하지 않는다 — 다른 바이트는 다른 내용으로 둔다.
    @Test("디코드하지 못한 메타데이터는 원본 바이트로 구분한다")
    func undecodableMetadataFallsBackToRawBytes() {
        let line = Data("stroke".utf8)
        let first = VerseContentFingerprint.make(lineData: line, drawingVersion: 3, layoutMetadataBlob: Data("깨진 값 1".utf8))
        let second = VerseContentFingerprint.make(lineData: line, drawingVersion: 3, layoutMetadataBlob: Data("깨진 값 2".utf8))
        let sameAgain = VerseContentFingerprint.make(lineData: line, drawingVersion: 3, layoutMetadataBlob: Data("깨진 값 1".utf8))

        #expect(first != second)
        #expect(first == sameAgain)
    }
}
