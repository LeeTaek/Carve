//
//  NotebookPageTestSupport.swift
//  DomainTest
//
//  기본 필사책 page — 필사책을 나르기 전부터 있던 시험이 page API 로 옮겨 쓴다(2.2 「회차별 필사책」 t4 — 옛 장 API 를 지운 뒤).
//

@testable import Domain

extension BibleChapter {
    /// 기본 필사책(2.2 이전의 모든 필사)의 page — 옛 장 API(뜻은 「기본 필사책」)를 쓰던 시험의 뜻 그대로다. 다른 필사책은 `NotebookChapter` 를 직접 짓는다.
    var inDefaultNotebook: NotebookChapter {
        NotebookChapter(notebook: .default, chapter: self)
    }
}
