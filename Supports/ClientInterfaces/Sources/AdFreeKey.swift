//
//  AdFreeKey.swift
//  ClientInterfaces
//
//  Created by Claude on 9/14/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import ComposableArchitecture

public extension SharedReaderKey where Self == AppStorageKey<Bool>.Default {
    /// 광고 제거를 샀는지(UserDefaults 캐시).
    ///
    /// - 판정 기준은 StoreKit 이다. 이 값을 쓰는 곳은 App 타겟의 구매 클라이언트 하나뿐이고 나머지는 읽기만 한다.
    /// - 캐시를 두는 이유는 실행 직후 StoreKit 판정이 끝나기 전에 광고 자리가 잠깐 보이지 않게 하기 위해서다.
    static var isAdFree: Self {
        Self[.appStorage("isAdFree"), default: false]
    }
}
