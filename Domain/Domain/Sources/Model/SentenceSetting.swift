//
//  SentenceSetting.swift
//  Domain
//
//  Created by 이택성 on 6/12/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI
import Resources

public struct SentenceSetting: Sendable, Codable, Equatable, Hashable {
    public var lineSpace: CGFloat
    public var fontSize: CGFloat
    public var traking: CGFloat
    public var baseLineHeight: CGFloat
    public var textHeight: CGFloat
    public var fontFamily: FontCase
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
    
    public init(lineSpace: CGFloat, 
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

public enum FontCase: String, CaseIterable, Sendable, Codable {
    case gothic = "NanumGothic"
    case myeongjo = "NanumMyeongjo"
    case flower = "NanumFlowerScent"
        
    public func font(size: CGFloat) -> UIFont {
        switch self {
        case .flower: ResourcesFontFamily.나눔손글씨꽃내음.regular.font(size: size)
        case .gothic: ResourcesFontFamily.NanumGothic.regular.font(size: size)
        case .myeongjo: ResourcesFontFamily.NanumMyeongjo.regular.font(size: size)
        }
    }
    
    public var title: String {
        switch self {
        case .flower: "나눔꽃향기"
        case .gothic: "나눔바른고딕"
        case .myeongjo: "나눔명조"
        }
    }
}
