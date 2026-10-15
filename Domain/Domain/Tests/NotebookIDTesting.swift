//
//  NotebookIDTesting.swift
//  DomainTest
//
//  Created by Claude on 10/15/26.
//

@testable import Domain
import Foundation
import Testing

import Dependencies

/// 필사책 ID 형식(2.2 「회차별 필사책」 인터페이스 동결 ①) — 행 접두 · 지금 필사책 저장값 · 백업이 같은 검사를 쓴다.
struct NotebookIDTesting {
    private static let uuid = UUID(uuidString: "0F3A9C2E-7B41-4D6A-9E15-2C8B7D04A1F3")!

    @Test("make(uuid:) 는 uuidString 에서 - 를 빼고 소문자로 바꾼 32자리다")
    func makeStripsHyphensAndLowercases() {
        // When
        let notebook = NotebookID.make(uuid: Self.uuid)

        // Then
        #expect(notebook.rawValue == "0f3a9c2e7b414d6a9e152c8b7d04a1f3")
        #expect(notebook.rawValue.count == 32)
        #expect(!notebook.isDefault)
        #expect(NotebookID(rawValue: notebook.rawValue) == notebook)
    }

    @Test("rawValue 는 default 또는 소문자 16진 32자리만 받는다")
    func rawValueAcceptsOnlyDefaultOrLowercaseHex() {
        #expect(NotebookID(rawValue: "default") == .default)
        #expect(NotebookID(rawValue: "0123456789abcdef0123456789abcdef") != nil)

        #expect(NotebookID(rawValue: "") == nil)
        #expect(NotebookID(rawValue: "Default") == nil)
        #expect(NotebookID(rawValue: "0F3A9C2E7B414D6A9E152C8B7D04A1F3") == nil)          // 대문자
        #expect(NotebookID(rawValue: "0f3a9c2e-7b41-4d6a-9e15-2c8b7d04a1f3") == nil)      // - 포함
        #expect(NotebookID(rawValue: "0f3a9c2e7b414d6a9e152c8b7d04a1f") == nil)           // 31자리
        #expect(NotebookID(rawValue: "0f3a9c2e7b414d6a9e152c8b7d04a1f30") == nil)         // 33자리
        #expect(NotebookID(rawValue: "0f3a9c2e7b414d6a9e152c8b7d04a1fg") == nil)          // 16진 밖
        #expect(NotebookID(rawValue: "0f3a9c2e7b414d6a.e152c8b7d04a1f3") == nil)          // .
        #expect(NotebookID(rawValue: "０f3a9c2e7b414d6a9e152c8b7d04a1f3") == nil)          // 전각 숫자
    }

    @Test("default 는 rawValue 「default」 이고 기본 필사책이다")
    func defaultNotebook() {
        #expect(NotebookID.default.rawValue == "default")
        #expect(NotebookID.default.isDefault)
    }

    @Test("Codable — 문자열 하나로 쓰고 읽으며, 형식이 맞지 않는 값은 읽지 않는다")
    func codableRoundTripsAsSingleString() throws {
        // Given
        let notebook = NotebookID.make(uuid: Self.uuid)
        let page = NotebookChapter(notebook: notebook, chapter: BibleChapter(title: .psalms, chapter: 23, translation: .KJV))

        // When
        let encodedID = try JSONEncoder().encode(notebook)
        let encodedPage = try JSONEncoder().encode(page)

        // Then
        #expect(String(bytes: encodedID, encoding: .utf8) == "\"0f3a9c2e7b414d6a9e152c8b7d04a1f3\"")
        #expect(try JSONDecoder().decode(NotebookID.self, from: encodedID) == notebook)
        #expect(try JSONDecoder().decode(NotebookID.self, from: Data("\"default\"".utf8)) == .default)
        #expect(try JSONDecoder().decode(NotebookChapter.self, from: encodedPage) == page)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(NotebookID.self, from: Data("\"NOT-A-NOTEBOOK\"".utf8))
        }
    }

    @Test("NotebookChapter 는 필사책이 다르면 같은 장이어도 다르다")
    func notebookChapterDistinguishesNotebooks() {
        let chapter = BibleChapter(title: .genesis, chapter: 1)
        let defaultPage = NotebookChapter(notebook: .default, chapter: chapter)
        let otherPage = NotebookChapter(notebook: .make(uuid: Self.uuid), chapter: chapter)

        #expect(defaultPage != otherPage)
        #expect(Set([defaultPage, otherPage, defaultPage]).count == 2)
    }

    @Test("NotebookStatus 는 completed 만 완료이고, 모르는 값 · nil 은 active 다")
    func statusReadsUnknownAsActive() {
        #expect(NotebookStatus(stored: "completed") == .completed)
        #expect(NotebookStatus(stored: "active") == .active)
        #expect(NotebookStatus(stored: nil) == .active)
        #expect(NotebookStatus(stored: "archived") == .active)
        #expect(NotebookStatus(stored: "Completed") == .active)
    }

    @Test("notebookRepository 의 testValue 는 기본 필사책 하나만 돌려주고 쓰기는 버린다")
    func emptyTestValueListsOnlyDefault() async throws {
        // Given — 시험 문맥의 기본 의존성(공유 SwiftData actor 를 깨우지 않는 빈 스텁)
        @Dependency(\.notebookRepository) var repository
        let notebook = NotebookID.make(uuid: Self.uuid)

        // When
        try await repository.create(id: notebook, name: "두 번째 필사", now: Date(timeIntervalSince1970: 1_760_000_000))
        try await repository.delete(.default)
        let notebooks = try await repository.notebooks()

        // Then
        #expect(notebooks.map(\.id) == [.default])
        #expect(notebooks.first?.hasMetadata == false)
        #expect(notebooks.first?.name == nil)
    }
}
