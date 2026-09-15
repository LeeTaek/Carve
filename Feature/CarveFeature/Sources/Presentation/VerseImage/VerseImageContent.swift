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
    /// 아래에 적는 출처(「시편 23장 1절 · 개역한글」).
    let reference: String
    /// 필기 칸.
    let handwriting: VerseImageHandwriting

    /// 출처 문구. 헤더 · 즐겨찾기 목록처럼 시편도 「장」 으로 적는다.
    /// - Parameters:
    ///   - chapter: 권 · 장.
    ///   - verse: 절 번호.
    ///   - translation: 번역본.
    static func reference(chapter: BibleChapter, verse: Int, translation: Translation = .NKRV) -> String {
        "\(chapter.title.koreanTitle()) \(chapter.chapter)장 \(verse)절 · \(translation.displayName)"
    }
}
