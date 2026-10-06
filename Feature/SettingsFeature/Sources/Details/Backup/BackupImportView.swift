//
//  BackupImportView.swift
//  SettingsFeature
//
//  설정 → 필사 백업 → 「백업 불러오기」 시트(설계 docs/backup-import-design.md §4-1). 지금은 비어 있는 시트다 — 흐름은 다음 작업이 채운다.
//

import SwiftUI

import ComposableArchitecture
import UIComponents

@ViewAction(for: BackupImportFeature.self)
public struct BackupImportView: View {
    @Bindable public var store: StoreOf<BackupImportFeature>

    public init(store: StoreOf<BackupImportFeature>) {
        self.store = store
    }

    public var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CarveColor.surface)
            .onAppear { send(.onAppear) }
    }
}
