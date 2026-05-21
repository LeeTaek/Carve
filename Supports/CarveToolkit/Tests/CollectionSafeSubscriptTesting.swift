//
//  CollectionSafeSubscriptTesting.swift
//  CarveToolkitTest
//
//  Created by Codex on 5/21/26.
//

@testable import CarveToolkit
import Testing

struct CollectionSafeSubscriptTesting {
    @Test("유효한 인덱스는 컬렉션 원소를 반환한다")
    func returnsElementForValidIndex() {
        let verses = ["창세기", "출애굽기", "레위기"]

        #expect(verses[safe: verses.index(verses.startIndex, offsetBy: 1)] == "출애굽기")
    }

    @Test("끝 인덱스는 컬렉션 범위 밖이므로 nil을 반환한다")
    func returnsNilForEndIndex() {
        let verses = ["창세기", "출애굽기", "레위기"]

        #expect(verses[safe: verses.endIndex] == nil)
    }
}
