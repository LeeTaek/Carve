//
//  BibleSourceView.swift
//  SettingsFeature
//
//  설정 → 앱 버전 → 「성경 본문 출처」 — 번역본마다 이름 · 판 · 권리 · 출처(영어 현지화 결정 11).
//

import SwiftUI

import ComposableArchitecture
import UIComponents

/// 번역본 묶음을 구분선으로 나눠 위에서 아래로 적는다. 값이 길어(권리 · 주소) 이름 아래에 값을 두는 두 줄 행으로 둔다.
public struct BibleSourceView: View {
    private let store: StoreOf<BibleSourceFeature>

    public init(store: StoreOf<BibleSourceFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CarveSpacing.large) {
                Text(BibleSourceCopy.summary)
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(store.entries) { entry in
                    CarveDivider()
                    entrySection(entry)
                }
            }
            .padding(CarveSpacing.large)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CarveColor.surface)
        .navigationTitle(BibleSourceCopy.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 번역본 하나 — 이름 · 약칭과 그 아래 판 · 권리 · 출처. 적을 것이 없는 줄은 두지 않는다(개역개정은 이름만).
    private func entrySection(_ entry: BibleSourceEntry) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name())
                    .font(CarveTypography.title)
                    .foregroundStyle(CarveColor.ink)
                if let abbreviation = entry.abbreviation() {
                    Text(abbreviation)
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if let edition = entry.edition() {
                detailRow(BibleSourceCopy.editionLabel, value: edition)
            }
            if let rights = entry.rights() {
                detailRow(BibleSourceCopy.rightsLabel, value: rights)
            }
            if let officialSite = entry.officialSite {
                detailRow(BibleSourceCopy.officialSiteLabel, value: officialSite)
            }
            if let textSource = entry.textSource {
                detailRow(BibleSourceCopy.textSourceLabel, value: textSource)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 항목 이름과 그 아래 값. 주소를 옮겨 적을 수 있게 값은 고를 수 있는 글자로 둔다.
    private func detailRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(CarveTypography.caption)
                .foregroundStyle(CarveColor.secondary)
            Text(value)
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        BibleSourceFeature()
    }
    NavigationStack {
        BibleSourceView(store: store)
    }
}
