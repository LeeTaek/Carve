//
//  NotebookNaming.swift
//  CarveFeature
//
//  Created by Claude on 10/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Domain
import Foundation

/// 필사책 이름 — 보이는 이름 · 새 필사책 이름 제안 · 입력한 이름 검사(2.2 회차별 필사책, 설계 §6-3 · §6-4 · §6-10).
///
/// - 사용자가 지은 이름은 **옮기지 않는다** — 그대로 보인다(`Text(verbatim:)` 꼴).
/// - 이름이 없을 때만 화면 언어의 기본 표시를 쓴다 — 기본 필사책은 「첫 번째 필사」(en 「First Notebook」), 그 밖은 「이름 없는 필사책」(en 「Untitled Notebook」).
/// - 서수는 문자열로 잇지 않고 카탈로그 문구로 쓴다(룰북 localization.md 3) — ko 「두 번째 필사」 … 「열 번째 필사」 · 「11번째 필사」, en 「Notebook 2」.
/// - 모든 함수가 로케일을 받는다 — 뷰는 환경 locale, 리듀서는 `AppLanguage.displayLocale()`, 시험은 고른 로케일을 넘긴다.
enum NotebookNaming {
    /// 이름의 글자 수 상한(설계 §6-4).
    static let maxLength = 40

    /// 역할: 카드 · 헤더 · 확인창에 보일 필사책 이름.
    /// 입력 · 출력: 저장된 이름(nil · 빈 문자열 = 이름 없음) · 기본 필사책인가 · 로케일 → 사용자가 지은 이름 그대로, 없으면 화면 언어의 기본 표시.
    /// 부작용: 없음.
    static func displayName(_ name: String?, isDefault: Bool, locale: Locale) -> String {
        if let name, !name.isEmpty { return name }
        return isDefault ? ordinalName(1, locale: locale) : CarveFeatureCatalog.string("이름 없는 필사책", locale: locale)
    }

    /// 역할: 책장 카드 · 확인창의 필사책 이름(`displayName(_:isDefault:locale:)` 를 필사책 값으로 부른다).
    /// 입력 · 출력: 필사책 · 로케일 → 보일 이름.
    /// 부작용: 없음.
    static func displayName(of notebook: NotebookSnapshot, locale: Locale) -> String {
        displayName(notebook.name, isDefault: notebook.id.isDefault, locale: locale)
    }

    /// 역할: n 번째 필사책의 이름 — 기본 필사책의 기본 이름(1)과 새 필사책 이름 제안(2 이상)이 쓴다.
    /// 입력 · 출력: 서수(1 이상, 그보다 작으면 1) · 로케일 → ko 「첫 번째 필사」 … 「열 번째 필사」 · 「11번째 필사」, en 「First Notebook」 · 「Notebook 2」.
    /// 부작용: 없음.
    static func ordinalName(_ ordinal: Int, locale: Locale) -> String {
        // 한국어 서수(첫 · 두 · … · 열)는 숫자와 꼴이 달라 문구마다 따로 둔다. 영어는 「Notebook n」 꼴이다.
        switch ordinal {
        case ...1: CarveFeatureCatalog.string("첫 번째 필사", locale: locale)
        case 2: CarveFeatureCatalog.string("두 번째 필사", locale: locale)
        case 3: CarveFeatureCatalog.string("세 번째 필사", locale: locale)
        case 4: CarveFeatureCatalog.string("네 번째 필사", locale: locale)
        case 5: CarveFeatureCatalog.string("다섯 번째 필사", locale: locale)
        case 6: CarveFeatureCatalog.string("여섯 번째 필사", locale: locale)
        case 7: CarveFeatureCatalog.string("일곱 번째 필사", locale: locale)
        case 8: CarveFeatureCatalog.string("여덟 번째 필사", locale: locale)
        case 9: CarveFeatureCatalog.string("아홉 번째 필사", locale: locale)
        case 10: CarveFeatureCatalog.string("열 번째 필사", locale: locale)
        default: CarveFeatureCatalog.string("\(ordinal)번째 필사", locale: locale)
        }
    }

    /// 역할: 새 필사책 이름 제안 — 「지금 필사책 수 + 1」 번째(기본 필사책 하나뿐이면 「두 번째 필사」 · 「Notebook 2」).
    ///   그 이름을 이미 쓰는 필사책이 있으면 다음 서수로 넘어간다. 제안일 뿐 사용자가 고칠 수 있다.
    /// 입력 · 출력: 지금 필사책들 · 로케일 → 제안 이름.
    /// 부작용: 없음.
    static func suggestedName(existing notebooks: some Collection<NotebookSnapshot>, locale: Locale) -> String {
        let taken = Set(notebooks.map { displayName(of: $0, locale: locale) })
        // 목록을 아직 읽지 않았어도 기본 필사책은 늘 있다 — 2 부터 센다.
        let first = max(notebooks.count, 1) + 1
        // 겹치는 이름은 많아야 필사책 수만큼이라 그 안에서 빈 서수가 나온다.
        for ordinal in first...(first + notebooks.count) where !taken.contains(ordinalName(ordinal, locale: locale)) {
            return ordinalName(ordinal, locale: locale)
        }
        return ordinalName(first, locale: locale)
    }

    /// 서수 꼴 이름 → 서수 표(한국어 · 영어, 1 ~ 99). `ordinalName` 의 카탈로그 문구로 만들어 문구를 고쳐도 따라온다.
    private static let ordinalsByName: [String: Int] = {
        var table: [String: Int] = [:]
        for locale in [Locale(identifier: "ko"), Locale(identifier: "en")] {
            for ordinal in 1...99 {
                table[ordinalName(ordinal, locale: locale)] = ordinal
            }
        }
        return table
    }()

    /// 역할: 이름이 서수 꼴(「세 번째 필사」 · 「11번째 필사」 · 「Notebook 3」 · 「First Notebook」)이면 그 서수 — 책장 표지의 번호(시안 P1).
    /// 입력 · 출력: 보이는 이름 → 서수(1 ~ 99), 서수 꼴이 아니면 nil. 이름을 지은 언어와 화면 언어가 달라도 풀리도록 한국어 · 영어 꼴을 모두 본다.
    /// 부작용: 없음.
    static func ordinal(inName name: String) -> Int? {
        ordinalsByName[name.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    /// 역할: 입력한 이름을 저장할 이름으로 바꾼다 — 앞뒤 공백 · 줄바꿈을 자른다.
    /// 입력 · 출력: 입력 → 자른 이름. 비었거나 `maxLength` 글자를 넘으면 nil(받지 않는다).
    /// 부작용: 없음.
    static func validatedName(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }
        return trimmed
    }
}
