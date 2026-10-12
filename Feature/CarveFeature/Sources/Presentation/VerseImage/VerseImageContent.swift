//
//  VerseImageContent.swift
//  CarveFeature
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics
import Domain
import Foundation

/// 절 이미지(시안 G1)의 필기 칸 — 캔버스에서 그 절의 필사 영역을 그대로 옮긴 것.
public struct VerseImageHandwriting: Equatable, Sendable {
    /// 절 번호.
    public let verse: Int
    /// 필사 영역 크기(`VerseCanvasRegion.writingRect`). 이미지의 본문 · 필기 폭이 이 폭을 따른다.
    public let writingSize: CGSize
    /// 밑줄 y — 필사 영역 상단 기준(`VerseCanvasRegion.underlineAnchors`).
    public let underlineAnchors: [CGFloat]
    /// 필사 영역 좌상단 원점의 필기(`PKDrawing` 데이터). 획이 없으면 nil — 이미지에는 본문만 담는다.
    public let inkData: Data?
}

/// 사진으로 저장하는 절 이미지 한 장의 내용(시안 G1) — 본문 · 필기 · 출처.
public struct VerseImageContent: Equatable, Sendable {
    /// 본문.
    let sentence: String
    /// 본문 모양 — 필사 화면과 같은 글꼴 · 크기 · 줄 간격 · 자간으로 그린다.
    let setting: SentenceSetting
    /// 아래에 적는 출처(「시편 23장 1절 · 개역개정」 · 「Psalm 23:1 · KJV」).
    let reference: String
    /// 필기 칸.
    let handwriting: VerseImageHandwriting

    /// 역할: 출처 문구를 짓는다 — 참조는 `BibleReference`, 뒤에 장의 번역본 약칭을 붙인다(영어 현지화 결정 3 · 11).
    ///   권 이름 · 장절 표기는 번역본이 아니라 앱 언어를 따른다 — 한국어 기기는 KJV 절도 「시편 23장 1절 · KJV」 다.
    /// 입력 · 출력: 장(번역본 포함) · 절 번호 · 합쳐진 절의 끝 번호 · 로케일 → 「시편 23장 1절 · 개역개정」, 「신명기 6장 18-19절 · BSB」.
    ///   `verseEnd` 가 `verse` 보다 크면 범위로, 아니면 절 하나로 적는다. 로케일이 nil 이면 앱(기기) 언어다.
    /// 부작용: 없음.
    static func reference(chapter: BibleChapter, verse: Int, verseEnd: Int? = nil, locale: Locale? = nil) -> String {
        let verses: BibleReference.Verses
        if let verseEnd, verseEnd > verse {
            verses = .range(verse...verseEnd)
        } else {
            verses = .verse(verse)
        }
        return BibleReference(chapter: chapter, verses: verses, showsTranslation: true).text(locale: locale)
    }
}
