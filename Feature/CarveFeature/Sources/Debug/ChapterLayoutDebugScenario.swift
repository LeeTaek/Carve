//
//  ChapterLayoutDebugScenario.swift
//  CarveFeature
//
//  Created by Claude on 9/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

#if DEBUG
import CarveToolkit
import Foundation
import SwiftUI

import ComposableArchitecture

/// Phase 2 측정용 무인 시나리오 (Debug 전용, 설계 §18-3 의 절차를 실행 인자로 재현).
///
/// 시뮬레이터에 터치를 주입할 수단이 이 머신에는 없다 (S4 §20-4 와 같은 `xcode-select` 제약, 호스트 쪽 도구도 없음).
/// S4 하네스가 그랬듯 앱이 스스로 시나리오를 수행하고 `Log.info` 로 시각을 남긴다 — `log stream --level debug` 로 받는다.
///
/// | 인자 | 동작 |
/// |---|---|
/// | `-ChapterLayoutAutoScroll` | settle 8 s 뒤 1 s 간격으로 11단계에 걸쳐 마지막 절까지 스크롤 (§18-3 (C) "flick 11회" 근사) |
/// | `-ChapterLayoutAutoNext` | settle 8 s 뒤 다음 장으로 이동 (§18-3 (B) "장 전환 진입") |
enum ChapterLayoutDebugScenario {
    static let scrollArgument = "-ChapterLayoutAutoScroll"
    static let nextChapterArgument = "-ChapterLayoutAutoNext"

    static var isScrollEnabled: Bool { ProcessInfo.processInfo.arguments.contains(scrollArgument) }
    static var isNextChapterEnabled: Bool { ProcessInfo.processInfo.arguments.contains(nextChapterArgument) }

    /// §18-3 (C) 근사. 절 목록을 11등분해 각 지점의 절이 화면 하단에 오도록 애니메이션 스크롤한다.
    /// - Parameters:
    ///   - verseIDs: 스크롤 대상 행 id (본문 순서).
    ///   - proxy: 현재 `ScrollViewProxy`.
    @MainActor
    static func runScroll(verseIDs: @escaping () -> [String], proxy: @escaping () -> ScrollViewProxy?) async {
        try? await Task.sleep(for: .seconds(8))
        let ids = verseIDs()
        let steps = 11
        guard !ids.isEmpty else {
            Log.info("AUTOSCROLL 대상 없음")
            return
        }
        Log.info("AUTOSCROLL start", "verses=\(ids.count)")
        for step in 1...steps {
            let index = max(0, min(ids.count - 1, Int((Double(ids.count) * Double(step) / Double(steps)).rounded()) - 1))
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy()?.scrollTo(ids[index], anchor: .bottom)
            }
            Log.info("AUTOSCROLL step", "\(step)/\(steps)", ids[index])
            try? await Task.sleep(for: .seconds(1))
        }
        Log.info("AUTOSCROLL done")
    }

    /// §18-3 (B) 근사. settle 뒤 다음 장으로 이동한다.
    /// - Parameter moveToNext: 헤더의 다음 장 액션을 보내는 클로저.
    @MainActor
    static func runNextChapter(moveToNext: @escaping () -> Void) async {
        try? await Task.sleep(for: .seconds(8))
        Log.info("AUTONEXT moveToNext")
        moveToNext()
    }
}
#endif
