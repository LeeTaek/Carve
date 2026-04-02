//
//  CarveDetailReducerTesting.swift
//  FeatureCarveTest
//
//  Created by 이택성 on 7/16/24.
//  Copyright © 2024 leetaek. All rights reserved.


@testable import CarveFeature
import Testing

struct CarveDetailReducerTesting {
    @Test
    func featureCanBeInitializedAfterBibleTextClientRefactor() {
        // 본문 조회 책임 분리 이후에도 Feature 자체는 의존성 선언만으로 정상 구성되어야 한다.
        _ = CarveDetailFeature()
    }
}
