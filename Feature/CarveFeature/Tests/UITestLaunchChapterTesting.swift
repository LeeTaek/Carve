//
//  UITestLaunchChapterTesting.swift
//  FeatureCarveTest
//
//  Created by Claude on 9/14/26.
//

@testable import CarveFeature
import ComposableArchitecture
import Domain
import Foundation
import Testing

/// 실기기 UI 테스트의 시작 장 인자(`-UITestChapter`, Debug 전용).
@MainActor
struct UITestLaunchChapterTesting {
    @Test("장 JSON 을 받으면 앱이 읽는 시작 장(title)으로 저장한다")
    func appliesChapterFromArgument() throws {
        let suite = "UITestLaunchChapterTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            UITestLaunchChapter.apply(arguments: ["CarveApp", "-SingleCanvas", "-UITestChapter", #"{"title":"1-19Psalms.txt","chapter":122}"#])
        }

        let stored = try #require(defaults.data(forKey: "title"))
        #expect(try JSONDecoder().decode(BibleChapter.self, from: stored) == BibleChapter(title: .psalms, chapter: 122))
    }

    @Test("인자가 없거나 값이 장이 아니면 시작 장을 건드리지 않는다")
    func ignoresMissingOrInvalidArgument() throws {
        #expect(UITestLaunchChapter.chapter(in: ["CarveApp"]) == nil)
        #expect(UITestLaunchChapter.chapter(in: ["CarveApp", "-UITestChapter"]) == nil)
        #expect(UITestLaunchChapter.chapter(in: ["CarveApp", "-UITestChapter", "시편 119"]) == nil)
        #expect(UITestLaunchChapter.chapter(in: ["CarveApp", "-UITestChapter", #"{"title":"없는책","chapter":1}"#]) == nil)

        let suite = "UITestLaunchChapterTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            UITestLaunchChapter.apply(arguments: ["CarveApp", "-UITestChapter", "시편 119"])
        }
        #expect(defaults.data(forKey: "title") == nil)
    }
}
