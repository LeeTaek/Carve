//
//  BackupArchivePassword.swift
//  Domain
//
//  사용자 암호 → AppleArchive `setPassword` 에 넘길 값. 이 규칙은 파일 형식의 일부다 — 바꾸면 이미 만든 백업을 열 수 없다.
//

import CryptoKit
import Foundation

/// AppleArchive 의 암호(scrypt) 모드는 UTF-8 **20~256 바이트** 암호만 받는다 — 밖이면 `setPassword` 가 `invalidValue` 로 거부한다
/// (Xcode 27 SDK 의 AEA 「internal size range」, macOS · iPadOS 시뮬레이터에서 확인). 화면 규칙은 8자 이상이라 그대로 넘기면 8~19 바이트 암호를 쓸 수 없다.
/// 그래서 고정 이름공간과 NFC 로 정규화한 암호를 이은 UTF-8 의 SHA-256 소문자 hex(늘 64바이트)를 넘긴다(2026-10-02 사용자 결정).
/// 키 유도(scrypt · 파일마다 무작위 salt) · 암호화 · 무결성은 그대로 SDK 가 한다 — 이 값은 길이를 맞추는 고정 표기일 뿐 저장하지 않는다.
///
/// macOS 진단(암호는 사용자가 넣는다):
/// `aea decrypt -i <파일> -o x.aar -password-value "$(printf '%s' 'carve.backupPassword/1|<암호>' | shasum -a 256 | cut -c1-64)"` → `aa extract -i x.aar -d <폴더>`
/// 주의: 쉘의 printf 는 받은 바이트 그대로 해시한다 — 한글 암호는 NFC(완성형)로 입력한다(터미널에 직접 친 한글은 보통 NFC 다).
enum BackupArchivePassword {
    /// 이름공간 — 형식이 바뀌면 판을 올린다.
    static let namespace = "carve.backupPassword/1"

    /// `setPassword` 에 넘길 값 — `SHA-256("<이름공간>|" + NFC(암호))` 의 소문자 hex 64자.
    /// - 입력: 사용자 암호 원문. NFC 로 정규화한다 — 한글 암호가 입력 경로(하드웨어 키보드 · 붙여넣기)에 따라 조합형/완성형 바이트가 달라도 같은 파일을 연다
    /// - 출력: 64바이트 ASCII 문자열
    /// - 부작용: 없음. 결과를 로그 · 파일에 남기지 않는다
    static func encoded(_ password: String) -> String {
        let normalized = password.precomposedStringWithCanonicalMapping
        let digest = SHA256.hash(data: Data("\(namespace)|\(normalized)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
