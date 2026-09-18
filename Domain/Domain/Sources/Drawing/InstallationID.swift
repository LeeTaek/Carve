//
//  InstallationID.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 이 설치의 ID — 복구 사본 · 격리본의 `deviceID`, 전역 식별자가 없는 legacy 행의 논리 ID(§12-6 C3 ⑤)에 쓴다.
///
/// 파일에 한 번 만들고 계속 쓴다. **있는데 읽지 못하면 새로 만들지 않고 던진다** — 바뀌면 같은 원본의 논리 ID 가 달라진다.
public enum InstallationID {
    /// 앱이 쓰는 위치. CloudKit 으로 동기화되지 않는 Application Support 아래다.
    public static var liveURL: URL {
        URL.applicationSupportDirectory.appending(path: "installation-id")
    }

    public static func load(at url: URL, fileManager: FileManager = .default) throws -> String {
        if fileManager.fileExists(atPath: url.path) {
            let text = String(decoding: try Data(contentsOf: url), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            return text
        }
        let id = UUID().uuidString
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DurableFile.write(Data(id.utf8), to: url)
        return id
    }
}
