//
//  BibleSourceFeatureTesting.swift
//  SettingsFeatureTest
//
//  설정 → 앱 버전 → 「성경 본문 출처」(영어 현지화 결정 11) — 번역본 항목과 앱 정보에서 들어가는 경로.
//

@testable import SettingsFeature
import Domain
import Foundation
import Testing

import ComposableArchitecture

@Suite("성경 본문 출처")
@MainActor
struct BibleSourceFeatureTesting {
    private static let english = Locale(identifier: "en")
    private static let korean = Locale(identifier: "ko")

    // MARK: - 항목

    @Test("항목은 번역본마다 하나씩 셋이고 Translation.allCases 순서다")
    func entriesFollowTranslationOrder() {
        // Given · When
        let entries = BibleSourceFeature.State.initialState.entries

        // Then
        #expect(entries.count == 3)
        #expect(entries.map(\.translation) == Translation.allCases)
        #expect(entries.map(\.translation) == [.NKRV, .KJV, .BSB])
    }

    @Test("KJV 는 1769년 표준판 본문 · 영국 밖에서 공개 도메인 · 본문 사본 출처 주소를 적는다")
    func kingJamesEntry() throws {
        // Given
        let entry = try #require(BibleSourceEntry.all.first { $0.translation == .KJV })

        // Then — 한국어
        #expect(entry.name(locale: Self.korean) == "King James Version")
        #expect(entry.abbreviation(locale: Self.korean) == "KJV")
        #expect(entry.edition(locale: Self.korean) == "1769년 표준판 본문")
        #expect(entry.rights(locale: Self.korean) == "영국 밖에서는 공개 도메인")
        #expect(entry.officialSite == nil)
        #expect(entry.textSource == "github.com/christislord12/kjv-txt-files")

        // Then — 영어
        #expect(entry.edition(locale: Self.english) == "1769 standard edition")
        #expect(entry.rights(locale: Self.english) == "Public domain outside the UK")
    }

    @Test("BSB 는 CC0 1.0 으로 2023년 4월 30일 공개 도메인 헌정 · 공식 사이트 · 본문 사본 출처 주소를 적는다")
    func bereanStandardEntry() throws {
        // Given
        let entry = try #require(BibleSourceEntry.all.first { $0.translation == .BSB })

        // Then — 한국어
        #expect(entry.name(locale: Self.korean) == "Berean Standard Bible")
        #expect(entry.abbreviation(locale: Self.korean) == "BSB")
        #expect(entry.edition(locale: Self.korean) == nil)
        #expect(entry.rights(locale: Self.korean) == "CC0 1.0 — 2023년 4월 30일 공개 도메인에 헌정")
        #expect(entry.officialSite == "berean.bible")
        #expect(entry.textSource == "bereanbible.com/bsb_usfm.zip")

        // Then — 영어(날짜도 그 언어의 서식)
        #expect(entry.rights(locale: Self.english) == "CC0 1.0 — dedicated to the public domain on April 30, 2023")
    }

    @Test("개역개정은 이름만 두고 권리 · 판 · 출처는 비운다(허락 근거 확인 전)")
    func koreanRevisedEntryHasNameOnly() throws {
        // Given
        let entry = try #require(BibleSourceEntry.all.first { $0.translation == .NKRV })

        // Then — 이름은 앱 언어를 따른다. 한국어는 약칭이 이름과 같아 따로 적지 않는다
        #expect(entry.name(locale: Self.korean) == "개역개정")
        #expect(entry.abbreviation(locale: Self.korean) == nil)
        #expect(entry.name(locale: Self.english) == "New Korean Revised Version")
        #expect(entry.abbreviation(locale: Self.english) == "NKRV")
        #expect(entry.edition(locale: Self.korean) == nil)
        #expect(entry.rights(locale: Self.korean) == nil)
        #expect(entry.officialSite == nil)
        #expect(entry.textSource == nil)
    }

    @Test("화면 이름은 앱 언어를 따른다")
    func titleIsLocalized() {
        #expect(BibleSourceCopy.title(locale: Self.korean) == "성경 본문 출처")
        #expect(BibleSourceCopy.title(locale: Self.english) == "Bible Text Sources")
    }

    // MARK: - 들어가는 경로

    @Test("앱 정보의 「성경 본문 출처」 행을 누르면 출처 화면을 쌓는다")
    func appVersionPushesBibleSource() async {
        // Given
        let store = TestStore(initialState: AppVersionFeature.State()) {
            AppVersionFeature()
        }

        // When · Then
        await store.send(.pushToBibleSource) {
            $0.path[id: 0] = .bibleSource(.initialState)
        }
    }
}
