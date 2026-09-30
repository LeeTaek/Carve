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

    /// §18-3 (C) 근사. 절 목록을 11등분해 각 지점의 절이 화면 하단에 오도록 스크롤한다.
    ///
    /// 스크롤 수단은 호출부가 준다 — N-Canvas 는 `ScrollViewProxy`, 단일 Canvas 는 `scrollToVerse` 액션.
    /// - Parameters:
    ///   - verses: 스크롤 대상 절 번호 (본문 순서).
    ///   - scrollTo: 절 하나로 스크롤하는 클로저.
    @MainActor
    static func runScroll(verses: @escaping () -> [Int], scrollTo: @escaping (Int) -> Void) async {
        try? await Task.sleep(for: .seconds(8))
        let targets = verses()
        let steps = 11
        guard !targets.isEmpty else {
            Log.info("AUTOSCROLL 대상 없음")
            return
        }
        Log.info("AUTOSCROLL start", "verses=\(targets.count)")
        for step in 1...steps {
            let index = max(0, min(targets.count - 1, Int((Double(targets.count) * Double(step) / Double(steps)).rounded()) - 1))
            scrollTo(targets[index])
            Log.info("AUTOSCROLL step", "\(step)/\(steps)", "verse=\(targets[index])")
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
