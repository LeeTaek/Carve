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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("패치노트")
                    .font(CarveTypography.sectionTitle)
                    .foregroundStyle(CarveColor.secondary)

                ForEach(PatchnoteFeature.releases) { release in
                    if release != PatchnoteFeature.latest {
                        CarveDivider()
                    }
                    VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
                        Text(Self.title(of: release))
                            .font(CarveTypography.title)
                            .foregroundStyle(CarveColor.ink)
                        Text("바뀐 점")
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
        CarveModalCard(title: Self.title(of: PatchnoteFeature.latest), subtitle: "바뀐 점") {
            VStack(alignment: .leading, spacing: 24) {
                notes(of: PatchnoteFeature.latest)
            }
        } actions: {
            Button {
                send(.helpTapped)
            } label: {
                Text("도움말 보기")
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
                Text("닫기")
                    .foregroundStyle(CarveColor.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
        }
    }

    private static func title(of release: PatchnoteFeature.Release) -> String {
        "새기다 \(release.version)"
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
