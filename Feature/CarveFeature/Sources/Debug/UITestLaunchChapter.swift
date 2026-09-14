//
//  UITestLaunchChapter.swift
//  CarveFeature
//
//  Created by Claude on 9/14/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

#if DEBUG
import CarveToolkit
import Domain
import Foundation

import ComposableArchitecture

/// 실기기 UI 테스트가 시작할 장 (Debug 전용).
///
/// 앱은 마지막으로 연 장(`@Shared(.appStorage("title"))`)에서 시작한다. UI 테스트는 특정 장을 전제하므로
/// (필기가 있는 시편 119편 · 자동화 전용 시편 122편) 기기에 남은 장에 따라 결과가 갈리지 않게 실행 인자로 시작 장을 정한다.
///
/// | 인자 | 동작 |
/// |---|---|
/// | `-UITestChapter <BibleChapter JSON>` | Store 를 만들기 전에 시작 장을 저장한다. 예: `{"title":"1-19Psalms.txt","chapter":119}` |
public enum UITestLaunchChapter {
    public static let argument = "-UITestChapter"

    /// 인자에서 시작 장을 읽는다. 인자가 없거나 값이 장이 아니면 nil.
    static func chapter(in arguments: [String]) -> BibleChapter? {
        guard let index = arguments.firstIndex(of: argument),
              arguments.indices.contains(index + 1),
              let data = arguments[index + 1].data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BibleChapter.self, from: data)
    }

    /// 인자가 있으면 시작 장을 저장한다. 헤더 · 탐색 상태가 시작 장을 읽기 전, 앱 진입점에서 Store 를 만들기 전에 부른다.
    ///
    /// 앱과 같은 `@Shared(.appStorage("title"))` 로 써서 저장 형식이 어긋나지 않게 한다.
    public static func apply(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard arguments.contains(argument) else { return }
        guard let chapter = chapter(in: arguments) else {
            Log.info("UITEST 시작 장 인자를 장으로 읽지 못해 무시함")
            return
        }
        @Shared(.appStorage("title")) var currentTitle: BibleChapter = .initialState
        $currentTitle.withLock { $0 = chapter }
        Log.info("UITEST 시작 장", "\(chapter.title.rawValue) \(chapter.chapter)")
    }
}
#endif
