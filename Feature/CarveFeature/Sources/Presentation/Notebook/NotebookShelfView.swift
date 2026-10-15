//
//  NotebookShelfView.swift
//  CarveFeature
//
//  Created by Claude on 10/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture
import UIComponents

/// 책장 화면(2.2 회차별 필사책). 차트 · 즐겨찾기처럼 앱 스택에 올라가며 시스템 막대의 뒤로 가기도 그대로 쓴다.
///
/// 지금은 빈 화면과 필사 화면으로 돌아가는 버튼만 있다. 카드 격자 · 「새 필사책」 · 옛 기기 안내는 책장 내용을 채울 때 더한다.
@ViewAction(for: NotebookShelfFeature.self)
public struct NotebookShelfView: View {
    public let store: StoreOf<NotebookShelfFeature>

    public init(store: StoreOf<NotebookShelfFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack {
            Button {
                send(.backTapped)
            } label: {
                // 새 문구를 만들지 않고 이미 있는 「닫기」 를 쓴다 — 책장 문구는 책장 내용과 함께 더한다.
                Text("닫기", bundle: .module)
            }
            .accessibilityIdentifier("notebookShelfBack")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CarveColor.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            send(.onAppear)
        }
    }
}
