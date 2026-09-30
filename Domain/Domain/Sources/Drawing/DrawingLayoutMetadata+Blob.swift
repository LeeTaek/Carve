//
//  DrawingLayoutMetadata+Blob.swift
//  Domain
//
//  Created by Claude on 9/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// `BibleDrawing.layoutMetadataData` blob 과 DTO 사이의 변환. **인코딩 형식은 여기 한 곳에서만 정한다.**
///
/// JSON 을 쓴다 — Phase 1 의 라운드트립 검증(§20-5)과 V4 마이그레이션 테스트가 같은 형식을 전제한다.
public extension DrawingLayoutMetadata {
    /// blob 으로 인코딩한다.
    /// - Returns: `layoutMetadataData` 에 기록할 Data.
    func encodedBlob() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// blob 을 디코드한다. 형식이 맞지 않으면 nil — 좌표 형식의 진실은 `drawingVersion` 이므로 여기서 던지지 않는다.
    /// - Parameter blob: `layoutMetadataData`.
    /// - Returns: 디코드된 metadata.
    static func decode(blob: Data?) -> DrawingLayoutMetadata? {
        guard let blob else { return nil }
        return try? JSONDecoder().decode(DrawingLayoutMetadata.self, from: blob)
    }
}
