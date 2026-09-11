//
//  PencilPalatteFeatureTesting.swift
//  CarveFeatureTest
//
//  Created by Claude on 9/11/26.
//

@testable import CarveFeature
import Foundation
import PencilKit
import Testing

import ComposableArchitecture

@MainActor
struct PencilPalatteFeatureTesting {
    /// 팔레트의 펜 칸 하나가 연필 · 펜 · 형광펜을 대표한다(시안 M2). 지우개를 쓴 뒤 펜 칸을 누르면 마지막 잉크로 돌아가야 한다.
    @Test("지우개를 골라도 마지막 잉크는 남는다")
    func eraserKeepsLastInkType() async throws {
        let suite = "PencilPalatteFeatureTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // State 가 Equatable 이 아니라 TestStore 대신 리듀서를 직접 부른다(HeaderFeatureTesting 과 같은 방식).
        withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            var state = PencilPalatteFeature.State()
            let reducer = PencilPalatteFeature()

            _ = reducer.reduce(into: &state, action: .view(.setPencilType(.marker)))
            #expect(state.lastInkType == .marker)

            _ = reducer.reduce(into: &state, action: .view(.setPencilType(.monoline)))
            #expect(state.pencilConfig.pencilType == .monoline)
            #expect(state.lastInkType == .marker)
        }
    }
}
