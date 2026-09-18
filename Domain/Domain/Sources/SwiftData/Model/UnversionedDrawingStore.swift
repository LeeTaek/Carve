//
//  UnversionedDrawingStore.swift
//  Domain
//
//  1.0.x 가 버전 없이 만든 저장소의 모델 — V1 폴백을 허용하는 모양의 허용 목록 (테스트 계획 MIG-F1).
//

import Foundation
import SwiftData

/// 1.0.x(1.1.0 이전)가 `Schema([DrawingVO.self])` 로 **버전 없이** 만든 저장소의 `DrawingVO` 모양들.
///
/// V1 폴백은 이 목록 중 하나와 **모델 해시가 정확히 맞는 저장소에만** 허용한다. 엔티티가 `DrawingVO` 하나뿐이라는 것은
/// 1.0.x 저장소의 필요조건일 뿐이다 — 이름만 보고 허용하면 필드가 다른 `DrawingVO` 저장소도 V1 로 갈아치운다(2026-09-17 리뷰).
///
/// 릴리스 커밋의 선언을 그대로 옮긴 **동결 정의**다. 고치면 해시가 바뀌어 그 모양의 저장소가 폴백 대상에서 빠진다.
/// 1.0.x 앱은 마이그레이션 플랜 없이 열었으므로 저장소는 **마지막으로 연 1.0.x 릴리스의 모양**이다.
/// 1.0.0 · 1.0.2 ~ 1.0.7 릴리스 커밋에서 모양은 아래 둘뿐이었다.
enum UnversionedDrawingStore {
    /// 1.0.0 ~ 1.0.3 — `creationDate` · `updateDate` 가 없다.
    ///
    /// - Note: 1.0.0 은 앞의 네 속성을 `let` 으로 선언했다(`0998d2ff` "iOS18 Swiftdata crash 수정" 에서 `var`).
    ///         조회 조건(`titleName` · `titleChapter` · `section`)에 쓰였으므로 저장 속성이었다.
    enum Release100 {
        @Model
        final class DrawingVO {
            var id: String!
            var titleName: String?
            var titleChapter: Int?
            var section: Int?
            @Attribute(.externalStorage) var lineData: Data?
            var isWritten: Bool = false

            init() { }
        }
    }

    /// 1.0.4 ~ 1.0.7 — `f7fa2f85` 에서 `creationDate` · `updateDate` 가 더해졌다.
    enum Release104 {
        @Model
        final class DrawingVO {
            var id: String!
            var titleName: String?
            var titleChapter: Int?
            var section: Int?
            var creationDate: Date?
            var updateDate: Date?
            @Attribute(.externalStorage) var lineData: Data?
            var isWritten: Bool = false

            init() { }
        }
    }

    /// 허용 목록. 한 항목이 저장소 하나의 모델 전체다.
    static var modelSets: [[any PersistentModel.Type]] {
        [[Release100.DrawingVO.self], [Release104.DrawingVO.self]]
    }
}
