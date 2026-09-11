//
//  ChapterLayoutSignature.swift
//  Domain
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics
import CryptoKit
import Foundation

/// 레이아웃 signature 생성기 (설계 §6-5).
///
/// **`Hashable.hashValue`를 쓰지 않는다.** Swift 해시 시드는 프로세스마다 달라지므로
/// 영속 metadata에 기록하면 앱을 재실행할 때마다 값이 달라져 항상 "레이아웃 불일치"로 판정된다.
/// 대신 canonical 문자열을 만들고 그 SHA256 digest를 사용한다. 같은 입력이면 언제·어느 프로세스에서
/// 계산하든 같은 문자열이 나온다.
public enum ChapterLayoutSignature {
    /// signature 인코딩 형식 자체의 버전.
    /// 구성요소나 인코딩 규칙이 바뀌면 올린다. 값이 바뀌면 기존 metadata와 의도적으로 불일치가 난다.
    ///
    /// - 2: `lineSpace` 의 뜻이 "줄 거리" 에서 "줄 사이 빈 공간" 으로 바뀌었다(`SentenceSetting.linePitch`).
    ///   같은 `lineSpace=30` 이라도 다른 레이아웃이므로 버전으로 구분한다.
    public static let formatVersion = 2

    /// signature의 원본이 되는 canonical 문자열.
    ///
    /// 설계 §6-5가 나열한 항목을 모두 포함한다:
    /// `formatVersion`, `fontFamily.rawValue`, `fontSize`, tracking, `lineSpace`, `writingWidth`, layoutDirection.
    /// - Parameters:
    ///   - setting: 본문 렌더링 설정.
    ///   - writingWidth: 필사 영역 폭.
    ///   - isLeftHanded: 왼손 모드 여부(layoutDirection).
    /// - Returns: 사람이 읽을 수 있는 canonical 문자열.
    public static func canonicalString(
        setting: SentenceSetting,
        writingWidth: CGFloat,
        isLeftHanded: Bool
    ) -> String {
        [
            "carve.chapterLayout/\(formatVersion)",
            "font=\(setting.fontFamily.rawValue)",
            "fontSize=\(canonicalNumber(setting.fontSize))",
            "tracking=\(canonicalNumber(setting.traking))",
            "lineSpace=\(canonicalNumber(setting.lineSpace))",
            "writingWidth=\(canonicalNumber(writingWidth))",
            "direction=\(isLeftHanded ? "leftHanded" : "rightHanded")"
        ].joined(separator: "|")
    }

    /// 영속 가능한 레이아웃 signature.
    /// - Parameters:
    ///   - setting: 본문 렌더링 설정.
    ///   - writingWidth: 필사 영역 폭.
    ///   - isLeftHanded: 왼손 모드 여부(layoutDirection).
    /// - Returns: `cl<formatVersion>-<sha256 hex>` 형태의 문자열.
    public static func make(
        setting: SentenceSetting,
        writingWidth: CGFloat,
        isLeftHanded: Bool
    ) -> String {
        let canonical = canonicalString(
            setting: setting,
            writingWidth: writingWidth,
            isLeftHanded: isLeftHanded
        )
        let digest = SHA256.hash(data: Data(canonical.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "cl\(formatVersion)-\(hex)"
    }

    /// 부동소수를 프로세스·로케일과 무관하게 같은 문자열로 인코딩한다.
    ///
    /// `"\(cgFloat)"`는 값에 따라 표현이 달라질 수 있고(`20.0` / `2e+01` 등) 로케일 영향도 받을 수 있으므로
    /// 소수점 4자리로 고정한다. `String(format:)`은 로케일을 받지 않으면 항상 POSIX 규칙(소수점 `.`)을 쓴다.
    /// `-0.0`이 `"-0.0000"`으로 인코딩되어 `0.0`과 다른 signature를 만드는 것을 막기 위해 0은 정규화한다.
    /// - Parameter value: 인코딩할 값.
    /// - Returns: 고정 자릿수 문자열.
    private static func canonicalNumber(_ value: CGFloat) -> String {
        let normalized = value == 0 ? CGFloat(0) : value
        return String(format: "%.4f", Double(normalized))
    }
}
