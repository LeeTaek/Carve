//
//  NotebookSnapshot.swift
//  Domain
//
//  Created by Claude on 10/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 필사책의 상태 — 표시일 뿐 쓰기를 막지 않는다(결정 7: 완료 표시 뒤에도 계속 쓸 수 있다).
///
/// 저장소의 `DrawingNotebook.status` 는 열거형 열이 아니라 **String 열**이다. 옛 앱이 모르는 열거값을 디코딩하다 죽을 수 있어서다
/// (혼재 버전 규칙 ④ — 영어 번역본 열 U3 와 같은 이유). 그래서 읽을 때는 `init(stored:)` 로 풀고, 모르는 값은 `active` 로 읽는다.
public enum NotebookStatus: String, Sendable {
    /// 쓰는 중(기본).
    case active
    /// 완료 표시를 했다.
    case completed

    /// 역할: 저장한 상태 문자열을 푼다.
    /// 입력 · 출력: `"completed"` 면 `completed`, 그 밖(nil · 모르는 값 · `"active"`)은 `active`.
    /// 부작용: 없음.
    public init(stored: String?) {
        self = stored.flatMap(NotebookStatus.init(rawValue:)) ?? .active
    }
}

/// 책장 카드 하나에 필요한 필사책 정보 — 메타데이터(`DrawingNotebook`)와 잉크 행(`BibleDrawing`)을 합친 값.
///
/// 메타데이터가 없어도 행이 있으면 필사책이다(혼재 버전 규칙 ⑥ — 지운 필사책의 행이 늦게 오거나 메타데이터보다 행이 먼저 오면
/// 「이름 없는 필사책」 으로 보인다. 숨기거나 기본 필사책에 합치지 않는다). 기본 필사책은 메타데이터가 없어도 늘 있다.
public struct NotebookSnapshot: Hashable, Sendable, Identifiable {
    /// 필사책 ID.
    public var id: NotebookID
    /// 사용자가 붙인 이름. nil 은 메타데이터에 이름이 없다는 뜻 — 화면이 기본 필사책은 「첫 번째 필사」, 그 밖은 「이름 없는 필사책」 으로 보인다.
    public var name: String?
    /// 완료 표시 여부.
    public var status: NotebookStatus
    /// 만든 시각(책장 카드의 시작 월 · 정렬). 메타데이터가 없으면 nil.
    public var createdAt: Date?
    /// 완료를 표시한 시각. 완료가 아니면 nil.
    public var completedAt: Date?
    /// 대표 행에 잉크가 있는 절 수 — 모든 번역본을 합친다.
    public var writtenVerseCount: Int
    /// 메타데이터 레코드(`DrawingNotebook`)가 있는가. 행만 있는 필사책 · 이름을 바꾼 적 없는 기본 필사책은 false.
    public var hasMetadata: Bool

    public init(
        id: NotebookID,
        name: String?,
        status: NotebookStatus,
        createdAt: Date?,
        completedAt: Date?,
        writtenVerseCount: Int,
        hasMetadata: Bool
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.writtenVerseCount = writtenVerseCount
        self.hasMetadata = hasMetadata
    }
}

/// 필사책 저장소의 실패.
public enum NotebookRepositoryError: Error, Equatable, Sendable {
    /// 기본 필사책은 지울 수 없다(결정 7).
    case cannotDeleteDefault
}
