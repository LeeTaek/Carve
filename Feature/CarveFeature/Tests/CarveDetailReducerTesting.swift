//
//  CarveDetailReducerTesting.swift
//  FeatureCarveTest
//
//  Created by 이택성 on 7/16/24.
//  Copyright © 2024 leetaek. All rights reserved.


@testable import CarveFeature
@testable import Domain
import Testing

import ComposableArchitecture


struct CarveDetailReducerTesting {
    
    @Test(arguments: [
        TitleVO.init(title: .samuel1, chapter: 4),
        TitleVO.initialState,
        TitleVO(title: .samuel2, chapter: 2)
    ])
    func fetchBible(title: TitleVO) throws {
//        #expect(throws: Never.self) {
//            try reducer.fetchBible(chapter: title)
//        }
    }
}
