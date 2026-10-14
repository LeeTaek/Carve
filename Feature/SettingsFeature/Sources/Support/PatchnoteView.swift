//
//  PatchnoteView.swift
//  SettingsFeature
//
//  Created by Codex on 9/11/26.
//

import SwiftUI

import ComposableArchitecture
import UIComponents

@ViewAction(for: PatchnoteFeature.self)
public struct PatchnoteView: View {
    public enum Style {
        case modal
        case detail
    }

    @Bindable public var store: StoreOf<PatchnoteFeature>
    private let style: Style
    /// 화면 언어 — 앱 안에서 언어를 고르면 바뀐 점 · 제목도 바로 따라온다(즉시 전환 단계 3).
    @Environment(\.locale) private var locale

    public init(store: StoreOf<PatchnoteFeature>, style: Style = .modal) {
        self.store = store
        self.style = style
    }

    @ViewBuilder
    public var body: some View {
        switch style {
        case .modal:
            modalContent
        case .detail:
            detailContent
        }
    }

    /// 설정의 패치노트 — 모든 출시를 최근 것부터 보인다.
    private var detailContent: some View {
        let releases = PatchnoteFeature.releases(locale: locale)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("패치노트", bundle: .module)
                    .font(CarveTypography.sectionTitle)
                    .foregroundStyle(CarveColor.secondary)

                ForEach(releases) { release in
                    // 가장 최근 출시(맨 앞) 위에는 구분선을 두지 않는다.
                    if release != releases.first {
                        CarveDivider()
                    }
                    VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
                        Text(Self.title(of: release, locale: locale))
                            .font(CarveTypography.title)
                            .foregroundStyle(CarveColor.ink)
                        Text("바뀐 점", bundle: .module)
                            .font(CarveTypography.caption)
                            .foregroundStyle(CarveColor.secondary)
                    }

                    notes(of: release)
                }
            }
            .padding(CarveSpacing.large)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CarveColor.canvas)
    }

    /// 업데이트 뒤 자동으로 띄우는 창 — 이번 출시만 보인다.
    private var modalContent: some View {
        let latest = PatchnoteFeature.latest(locale: locale)
        return CarveModalCard(title: Self.title(of: latest, locale: locale), subtitle: SettingsCatalog.string("바뀐 점", locale: locale)) {
            VStack(alignment: .leading, spacing: 24) {
                notes(of: latest)
            }
        } actions: {
            Button {
                send(.helpTapped)
            } label: {
                Text("도움말 보기", bundle: .module)
                    .foregroundStyle(CarveColor.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            Rectangle()
                .fill(CarveColor.divider)
                .frame(width: 1)
            Button {
                send(.closeTapped)
            } label: {
                Text("닫기", bundle: .module)
                    .foregroundStyle(CarveColor.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
        }
    }

    /// 출시 제목(「새기다 2.1」 · 「Carve 2.1」) — 뷰는 환경 `locale` 을 넘긴다.
    private static func title(of release: PatchnoteFeature.Release, locale: Locale) -> String {
        SettingsCatalog.string("새기다 \(release.version)", locale: locale)
    }

    /// 한 출시의 바뀐 점 — 사이에 구분선을 둔다.
    @ViewBuilder
    private func notes(of release: PatchnoteFeature.Release) -> some View {
        ForEach(Array(release.notes.enumerated()), id: \.offset) { index, note in
            if index > 0 {
                CarveDivider()
            }
            noteSection(title: note.title, body: note.body)
        }
    }

    private func noteSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CarveColor.ink)
            Text(body)
                .font(.system(size: 12))
                .foregroundStyle(CarveColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
