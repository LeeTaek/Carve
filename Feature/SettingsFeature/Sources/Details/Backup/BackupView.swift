//
//  BackupView.swift
//  SettingsFeature
//
//  설정 → 「필사 백업」 — 범위 안내와 「백업 만들기」 · 「백업 불러오기」 두 줄(설계 docs/backup-import-design.md §1 · §3 · §4).
//

import SwiftUI

import ComposableArchitecture
import UIComponents

@ViewAction(for: BackupFeature.self)
public struct BackupView: View {
    @Bindable public var store: StoreOf<BackupFeature>
    /// 화면 언어 — 앱 안에서 언어를 고르면 이 화면의 미리 만드는 문구도 바로 따라온다(즉시 전환 단계 3).
    @Environment(\.locale) private var locale

    public init(store: StoreOf<BackupFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CarveSpacing.large) {
                Text(BackupCopy.title(locale: locale))
                    .font(CarveTypography.sectionTitle)
                    .foregroundStyle(CarveColor.secondary)
                    .accessibilityAddTraits(.isHeader)

                // 무엇을 담고 무엇을 담지 않는가 — 만들기 전에 먼저 말한다.
                Text(BackupCopy.exportScope(locale: locale))
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.ink)
                    .fixedSize(horizontal: false, vertical: true)

                CarveDivider()

                VStack(alignment: .leading, spacing: CarveSpacing.medium) {
                    BackupExportView(store: store.scope(state: \.export, action: \.export))
                    // 불러오기는 구매와 상관없이 열린다(정책 §6-4).
                    BackupActionRow(
                        title: BackupCopy.importTitle(locale: locale),
                        description: BackupCopy.importDescription(locale: locale),
                        actionTitle: BackupCopy.importAction(locale: locale),
                        role: .primary
                    ) {
                        send(.importTapped)
                    }
                }

                CarveDivider()

                Text(BackupCopy.importGuidance(locale: locale))
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(CarveSpacing.large)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CarveColor.surface)
        .sheet(item: $store.scope(state: \.importer, action: \.importer)) { importStore in
            BackupImportView(store: importStore)
        }
    }
}

/// 필사 백업 화면의 한 줄 — 제목 · 설명과 오른쪽 버튼. 버튼은 설명과 묶지 않고 따로 읽히게 둔다.
struct BackupActionRow: View {
    let title: String
    let description: String
    let actionTitle: String
    let role: CarveButtonRole
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: CarveSpacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.ink)
                Text(description)
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button(actionTitle, action: action)
                .buttonStyle(.carve(role))
        }
        .frame(minHeight: CarveSize.minimumHitTarget)
    }
}

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        BackupFeature()
    }
    BackupView(store: store)
}
