//
//  UIComponentsLocalizationCatalogTesting.swift
//  UIComponentsTest
//
//  Created by Claude on 10/6/26.
//

@testable import UIComponents
import Foundation
import Testing

/// 모듈 카탈로그(`Resources/Localizable.xcstrings`, 원문 언어 ko)의 문구가 영어로도 옮겨졌는지 본다(영어 현지화 결정 5 · 7).
///
/// 카탈로그는 빌드에서 리소스 번들의 `<언어>.lproj/Localizable.strings`(문구)와 `Localizable.stringsdict`(복수형 · 변형)로
/// 컴파일된다. 그 언어로 컴파일될 문구가 없으면 파일이 생기지 않으므로 빈 카탈로그는 키 집합이 비어 통과한다.
/// 한국어 쪽에는 카탈로그에 ko 값이 명시된 키만 들어간다 — 원문을 키에서 그대로 쓰는(ko 값이 없는) 키는 컴파일되지 않는다.
struct UIComponentsLocalizationCatalogTesting {
    @Test("모듈 리소스 번들이 호스트 없는 시험에서 열린다")
    func moduleBundleOpens() {
        #expect(Bundle.module.bundleURL.lastPathComponent == "UIComponents_UIComponents.bundle")
    }

    @Test("한국어 Localizable 키는 모두 영어에도 있다")
    func koreanKeysAreAlsoInEnglish() throws {
        let korean = try Self.compiledKeys(in: .module, localization: "ko")
        let english = try Self.compiledKeys(in: .module, localization: "en")
        let untranslated = korean.subtracting(english).sorted()
        #expect(untranslated.isEmpty, "영어 번역이 없는 키: \(untranslated)")
    }

    /// 역할: 컴파일된 카탈로그에서 한 언어의 키 집합을 읽는다.
    /// 입력 · 출력: 리소스 번들과 언어 코드 → `<언어>.lproj` 의 `Localizable.strings` · `Localizable.stringsdict` 키 합집합(파일이 없으면 빈 집합).
    /// 부작용: 없음(파일 읽기만).
    private static func compiledKeys(in bundle: Bundle, localization: String) throws -> Set<String> {
        let resourceURL = try #require(bundle.resourceURL)
        let directory = resourceURL.appendingPathComponent("\(localization).lproj", isDirectory: true)
        var keys: Set<String> = []
        for fileExtension in ["strings", "stringsdict"] {
            let tableURL = directory.appendingPathComponent("Localizable.\(fileExtension)")
            guard FileManager.default.fileExists(atPath: tableURL.path) else { continue }
            let data = try Data(contentsOf: tableURL)
            let table = try PropertyListSerialization.propertyList(from: data, format: nil)
            let entries = try #require(table as? [String: Any], "\(tableURL.lastPathComponent) 가 사전이 아니다")
            keys.formUnion(entries.keys)
        }
        return keys
    }
}
