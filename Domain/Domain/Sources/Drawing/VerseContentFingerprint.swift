//
//  VerseContentFingerprint.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CryptoKit
import Foundation

/// 내용 지문 (정책 §12-6 용어) — `lineData` 바이트 · 좌표 형식(`drawingVersion`) ·
/// **키를 정렬해 다시 인코딩한** 레이아웃 메타데이터의 SHA-256.
///
/// 메타데이터를 다시 인코딩하는 이유는 F18 이다. 같은 내용이라도 JSON 키 순서가 기기 · 버전마다 달라,
/// 원본 바이트를 그대로 해시하면 같은 필기가 다른 지문이 된다. 지문이 갈리면 복구 사본 blob 을 공유하지
/// 못하고, legacy 보존 · 논리 ID(§12-6 C3 ⑤)도 같은 내용을 다른 것으로 본다.
///
/// `Hashable.hashValue` 를 쓰지 않는 이유는 `ChapterLayoutSignature` 와 같다 — 해시 시드가 프로세스마다 달라진다.
public enum VerseContentFingerprint {
    /// 지문 인코딩 형식 자체의 버전. 구성요소나 인코딩 규칙이 바뀌면 올린다.
    public static let formatVersion = 1

    /// 내용 지문을 만든다.
    /// - Parameters:
    ///   - lineData: `PKDrawing` 바이트. 없으면 "빈 내용" 으로 구분한다.
    ///   - drawingVersion: 좌표 형식. 같은 획이라도 좌표 형식이 다르면 다른 내용이다(F12 · R28).
    ///   - layoutMetadataBlob: `layoutMetadataData` 원본 바이트.
    /// - Returns: `vc<formatVersion>-<sha256 hex>` 형태의 문자열.
    public static func make(lineData: Data?, drawingVersion: Int?, layoutMetadataBlob: Data?) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("carve.verseContent/\(formatVersion)".utf8))
        // 길이를 먼저 넣어 구성요소 경계를 고정한다 — 이어 붙인 바이트가 우연히 같아지는 것을 막는다.
        hasher.update(data: Data("|line=\(lineData?.count ?? -1)|".utf8))
        if let lineData { hasher.update(data: lineData) }
        hasher.update(data: Data("|coord=\(drawingVersion.map(String.init) ?? "-")|".utf8))
        let metadata = canonicalMetadata(layoutMetadataBlob)
        hasher.update(data: Data("meta=\(metadata.count)|".utf8))
        hasher.update(data: metadata)
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return "vc\(formatVersion)-\(hex)"
    }

    /// 키 순서 · 공백 차이를 없앤 메타데이터 바이트.
    ///
    /// 디코드하지 못하면 **원본 바이트를 그대로 쓴다.** 알 수 없는 형식을 정규화한 척하며 다른 내용과 합치지 않는다.
    static func canonicalMetadata(_ blob: Data?) -> Data {
        guard let blob else { return Data() }
        guard let metadata = DrawingLayoutMetadata.decode(blob: blob) else { return blob }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(metadata)) ?? blob
    }
}
