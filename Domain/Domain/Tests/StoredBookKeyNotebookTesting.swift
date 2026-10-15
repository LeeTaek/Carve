//
//  StoredBookKeyNotebookTesting.swift
//  DomainTest
//
//  Created by Claude on 10/15/26.
//

@testable import Domain
import Foundation
import SwiftData
import Testing

/// 필사책 행 귀속(2.2 「회차별 필사책」 결정 1 · 혼재 버전 규칙 ①) — 기본 필사책 행은 지금 형식 그대로, 그 밖은 `nb_<토큰>~` 접두.
///
/// 옛 앱은 접두 행을 풀지 못해 건너뛴다 — 2.0.0 은 `BibleTitle(rawValue:)`, 2.1 은 `StoredBookKey.decode(_:)` 로 푼다. 그 동작을 흉내 내 고정한다.
struct StoredBookKeyNotebookTesting {
    private static let notebook = NotebookID.make(uuid: UUID(uuidString: "0F3A9C2E-7B41-4D6A-9E15-2C8B7D04A1F3")!)

    @Test("기본 필사책의 titleName 은 옛 함수와 같다 — 세 번역본 · 모든 권")
    func defaultNotebookKeepsLegacyTitleName() {
        for translation in Translation.allCases {
            for title in BibleTitle.allCases {
                let chapter = BibleChapter(title: title, chapter: 1, translation: translation)
                let legacy = StoredBookKey.titleName(title: title, translation: translation)

                #expect(StoredBookKey.titleName(title: title, translation: translation, notebook: .default) == legacy)
                #expect(StoredBookKey.titleName(for: NotebookChapter(notebook: .default, chapter: chapter)) == legacy)
                #expect(StoredBookKey.titleName(for: NotebookChapter(notebook: .default, chapter: chapter)) == StoredBookKey.titleName(for: chapter))
            }
        }
    }

    @Test("번역본 × 필사책 — 지은 titleName 은 같은 권 · 번역본 · 필사책으로 풀린다")
    func titleNameRoundTripsForEveryTranslationAndNotebook() throws {
        for notebook in [NotebookID.default, Self.notebook] {
            for translation in Translation.allCases {
                for title in BibleTitle.allCases {
                    // When
                    let titleName = StoredBookKey.titleName(title: title, translation: translation, notebook: notebook)
                    let decoded = try #require(StoredBookKey.decodeRow(titleName), "\(titleName)")

                    // Then
                    #expect(decoded == StoredRowKey(title: title, translation: translation, notebook: notebook))
                }
            }
        }
    }

    @Test("기본이 아닌 필사책 행은 nb_<토큰>~ 접두에 지금 titleName 을 잇는다")
    func notebookRowFormat() {
        let token = Self.notebook.rawValue

        #expect(StoredBookKey.titleName(title: .genesis, translation: .NKRV, notebook: Self.notebook) == "nb_\(token)~1-01Genesis.txt")
        #expect(StoredBookKey.titleName(title: .psalms, translation: .KJV, notebook: Self.notebook) == "nb_\(token)~KJV-1-19Psalms.txt")
        let page = NotebookChapter(notebook: Self.notebook, chapter: BibleChapter(title: .john, chapter: 3, translation: .BSB))
        #expect(StoredBookKey.titleName(for: page) == "nb_\(token)~BSB-2-04John.txt")
    }

    @Test("StoredRowKey.page(chapter:) 는 같은 필사책 · 권 · 번역본의 장을 짓는다")
    func rowKeyBuildsPage() throws {
        let titleName = StoredBookKey.titleName(title: .psalms, translation: .KJV, notebook: Self.notebook)

        let page = try #require(StoredBookKey.decodeRow(titleName)).page(chapter: 119)

        #expect(page == NotebookChapter(notebook: Self.notebook, chapter: BibleChapter(title: .psalms, chapter: 119, translation: .KJV)))
    }

    @Test("옛 decode 는 필사책 접두 행을 풀지 못한다 — 2.1 이 건너뛴다")
    func legacyDecodeSkipsNotebookRows() {
        for translation in Translation.allCases {
            for title in BibleTitle.allCases {
                let titleName = StoredBookKey.titleName(title: title, translation: translation, notebook: Self.notebook)
                #expect(StoredBookKey.decode(titleName) == nil, "\(titleName)")
            }
        }
    }

    @Test("BibleTitle(rawValue:) 도 필사책 접두 행을 풀지 못한다 — 2.0.0 이 건너뛴다")
    func bibleTitleRawValueSkipsNotebookRows() {
        for translation in Translation.allCases {
            for title in BibleTitle.allCases {
                let titleName = StoredBookKey.titleName(title: title, translation: translation, notebook: Self.notebook)
                #expect(BibleTitle(rawValue: titleName) == nil, "\(titleName)")
            }
        }
    }

    @Test("접두는 번역본 rawValue 로 시작하지 않고, 토큰에는 「.」 이 없다")
    func notebookPrefixAvoidsTranslationPrefixesAndDots() {
        for notebook in [Self.notebook, NotebookID.make(uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)] {
            let titleName = StoredBookKey.titleName(title: .genesis, translation: .KJV, notebook: notebook)
            for translation in Translation.allCases {
                #expect(!titleName.hasPrefix(translation.rawValue), "\(titleName)")
            }
            #expect(!notebook.rawValue.contains("."))
            #expect(!notebook.rawValue.contains("~"))
            // business id 는 `"<titleName>.<장>.<절>.<시각>"` — 「.」 은 권 rawValue 의 확장자 하나뿐이다.
            #expect(titleName.filter { $0 == "." }.count == 1)
        }
    }

    @Test("나쁜 토큰(대문자 · 길이 · 구분자 없음 · default · 16진 밖)은 decodeRow 가 nil 이다")
    func malformedTokensDecodeAsNil() {
        let token = Self.notebook.rawValue
        #expect(StoredBookKey.decodeRow("nb_\(token.uppercased())~1-01Genesis.txt") == nil)
        #expect(StoredBookKey.decodeRow("nb_\(token.dropLast())~1-01Genesis.txt") == nil)
        #expect(StoredBookKey.decodeRow("nb_\(token)0~1-01Genesis.txt") == nil)
        #expect(StoredBookKey.decodeRow("nb_\(token)1-01Genesis.txt") == nil)
        #expect(StoredBookKey.decodeRow("nb_\(token)") == nil)
        #expect(StoredBookKey.decodeRow("nb_default~1-01Genesis.txt") == nil)
        #expect(StoredBookKey.decodeRow("nb_\(token.dropLast())g~1-01Genesis.txt") == nil)
        #expect(StoredBookKey.decodeRow("nb_~1-01Genesis.txt") == nil)
        #expect(StoredBookKey.decodeRow("NB_\(token)~1-01Genesis.txt") == nil)
        // 토큰은 맞아도 뒤가 풀리지 않으면 nil.
        #expect(StoredBookKey.decodeRow("nb_\(token)~NotABook.txt") == nil)
        #expect(StoredBookKey.decodeRow("nb_\(token)~NKRV-1-01Genesis.txt") == nil)
        #expect(StoredBookKey.decodeRow("nb_\(token)~nb_\(token)~1-01Genesis.txt") == nil)
        #expect(StoredBookKey.decodeRow("nb_\(token)~") == nil)
    }

    @Test("접두 없는 행은 기본 필사책이고, 모르는 이름은 nil 이다")
    func unprefixedRowsBelongToDefaultNotebook() {
        #expect(StoredBookKey.decodeRow("1-01Genesis.txt") == StoredRowKey(title: .genesis, translation: .NKRV, notebook: .default))
        #expect(StoredBookKey.decodeRow("KJV-1-19Psalms.txt") == StoredRowKey(title: .psalms, translation: .KJV, notebook: .default))
        #expect(StoredBookKey.decodeRow("ESV-1-01Genesis.txt") == nil)
        #expect(StoredBookKey.decodeRow("") == nil)
    }

    @Test("어느 필사책에서도 NKRV- 접두는 만들지 않는다")
    func nkrvPrefixIsNeverProducedForNotebooks() {
        for notebook in [NotebookID.default, Self.notebook] {
            for title in BibleTitle.allCases {
                let titleName = StoredBookKey.titleName(title: title, translation: .NKRV, notebook: notebook)
                #expect(!titleName.contains("NKRV-"), "\(titleName)")
                #expect(titleName.hasSuffix(title.rawValue))
            }
        }
    }

    @Test("translation 열은 필사책과 무관하게 번역본으로만 정한다")
    func translationColumnIgnoresNotebook() throws {
        let container = try ModelContainer(for: AppStoreSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defer { withExtendedLifetime(container) {} }

        for notebook in [NotebookID.default, Self.notebook] {
            for translation in Translation.allCases {
                let page = NotebookChapter(notebook: notebook, chapter: BibleChapter(title: .genesis, chapter: 1, translation: translation))
                let row = BibleDrawing(page: page, verse: 1, rowUUID: "row")

                #expect(row.titleName == StoredBookKey.titleName(for: page))
                #expect(row.translation == StoredBookKey.translationColumn(for: translation))
                #expect(row.id.hasPrefix(StoredBookKey.titleName(for: page) + ".1.1."))
            }
        }
        // 옛 이니셜라이저는 기본 필사책 행을 짓는다 — 2.2 이전과 같은 형식.
        let legacy = BibleDrawing(bibleTitle: BibleChapter(title: .psalms, chapter: 23, translation: .KJV), verse: 4, rowUUID: "legacy")
        #expect(legacy.titleName == "KJV-1-19Psalms.txt")
        #expect(legacy.translation == nil)
        #expect(legacy.id.hasPrefix("KJV-1-19Psalms.txt.23.4."))
    }
}
