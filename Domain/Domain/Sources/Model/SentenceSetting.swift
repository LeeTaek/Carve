//
//  SentenceSetting.swift
//  Domain
//
//  Created by 이택성 on 6/12/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI
import Resources

/// 줄 간격, 폰트 크기, 자간, 기준 라인 높이, 텍스트 높이, 폰트 패밀리, 라인 수 등 성경 본문 텍스트 렌더링 옵션.
public struct SentenceSetting: Sendable, Codable, Equatable, Hashable {
    /// 각 줄 사이의 간격.
    public var lineSpace: CGFloat
    /// 본문 텍스트의 폰트 크기.
    public var fontSize: CGFloat
    /// 자간.
    public var traking: CGFloat
    /// 한 줄의 기준 라인 높이. 줄 수(lineCount)와 함께 전체 텍스트 높이를 계산할 때 사용.
    public var baseLineHeight: CGFloat
    /// 실제 렌더링된 텍스트의 높이 값.
    public var textHeight: CGFloat
    /// 본문에 사용할 폰트.
    public var fontFamily: FontCase
    /// 한 화면(혹은 한 절)을 구성할 때 사용할 줄 수(line count).
    public var lineCount: Int
    
    public static let initialState = SentenceSetting(
        lineSpace: 30,
        fontSize: 20,
        traking: 1,
        baseLineHeight: 20,
        textHeight: .zero,
        fontFamily: .gothic,
        lineCount: 3
    )
    
    public init(
        lineSpace: CGFloat,
        fontSize: CGFloat,
        traking: CGFloat,
        baseLineHeight: CGFloat,
        textHeight: CGFloat,
        fontFamily: FontCase,
        lineCount: Int
    ) {
        self.lineSpace = lineSpace
        self.fontSize = fontSize
        self.traking = traking
        self.baseLineHeight = baseLineHeight
        self.textHeight = textHeight
        self.fontFamily = fontFamily
        self.lineCount = lineCount
    }
}

/// 문장 설정에서 사용할 수 있는 폰트.
/// 실제 폰트 리소스(ResourcesFontFamily)를 매핑하여 UIKit 폰트로 변환.
public enum FontCase: String, CaseIterable, Sendable, Codable {
    /// 나눔고딕.
    case gothic = "NanumGothic"
    /// 나눔명조.
    case myeongjo = "NanumMyeongjo"
    /// 나눔꽃내음.
    case flower = "NanumFlowerScent"
        
    /// 주어진 사이즈로 UIKit UIFont 인스턴스를 생성.
    /// - Parameter size: 적용할 폰트 크기.
    /// - Returns: 대응되는 UIFont 인스턴스.
    public func font(size: CGFloat) -> UIFont {
        switch self {
        case .flower: ResourcesFontFamily.나눔손글씨꽃내음.regular.font(size: size)
        case .gothic: ResourcesFontFamily.NanumGothic.regular.font(size: size)
        case .myeongjo: ResourcesFontFamily.NanumMyeongjo.regular.font(size: size)
        }
    }
    
    /// UI에서 표시할 때 사용할 폰트 이름(한글 라벨).
    public var title: String {
        switch self {
        case .flower: "나눔꽃향기"
        case .gothic: "나눔바른고딕"
        case .myeongjo: "나눔명조"
        }
    }
}
