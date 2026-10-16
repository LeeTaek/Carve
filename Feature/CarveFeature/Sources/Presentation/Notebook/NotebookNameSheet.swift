//
//  NotebookNameSheet.swift
//  CarveFeature
//
//  Created by Claude on 10/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

import UIComponents

/// 이름 시트 — 새 필사책을 만들거나 필사책 이름을 바꾼다(설계 §6-3 · §6-4).
///
/// 입력은 시트가 갖고 저장할 때 리듀서(`NotebookShelfFeature.editorSaveTapped`)로 보낸다. 앞뒤 공백을 자른 이름이 비었으면 저장 버튼을 막고,
/// 40자를 넘게 쓰지 못하게 한다(리듀서도 같은 검사를 한다). 새 필사책 시트에는 빈 종이 안내와 옛 기기 안내(결정 6 · 14)를 둔다.
struct NotebookNameSheet: View {
    /// 새 필사책인가 — 아니면 이름 바꾸기.
    let isCreating: Bool
    /// 저장하는 중 — 버튼과 끌어내려 닫기를 막는다.
    let isSaving: Bool
    /// 저장하지 못했거나 막은 까닭. 있으면 저장 버튼 위에 보인다.
    let failureMessage: String?
    let onSave: (String) -> Void
    let onCancel: () -> Void

    /// 입력란. 처음 값은 새 필사책이면 제안 이름, 이름 바꾸기면 지금 보이는 이름이다.
    @State private var name: String
    @FocusState private var isFieldFocused: Bool
    /// 화면 언어 — 제목 · 입력란 안내를 이 값으로 만든다.
    @Environment(\.locale) private var locale

    init(
        isCreating: Bool,
        initialName: String,
        isSaving: Bool,
        failureMessage: String?,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.isCreating = isCreating
        self.isSaving = isSaving
        self.failureMessage = failureMessage
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: String(initialName.prefix(NotebookNaming.maxLength)))
    }

    /// 저장할 수 있는가 — 자른 이름이 비지 않았고 상한 안이다.
    private var canSave: Bool {
        !isSaving && NotebookNaming.validatedName(name) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            CarvePanelHeader(title) {
                Button(action: onCancel) {
                    Text("취소", bundle: .module)
                }
                .buttonStyle(.carve(.secondary))
                .disabled(isSaving)
            }

            VStack(alignment: .leading, spacing: CarveSpacing.medium) {
                VStack(alignment: .trailing, spacing: CarveSpacing.xxSmall) {
                    TextField(CarveFeatureCatalog.string("필사책 이름", locale: locale), text: $name)
                        .textFieldStyle(.plain)
                        .font(CarveTypography.body)
                        .submitLabel(.done)
                        .focused($isFieldFocused)
                        .onSubmit(save)
                        .padding(.horizontal, CarveSpacing.medium)
                        .frame(minHeight: CarveSize.minimumHitTarget)
                        .background(CarveColor.fill, in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous))
                        .accessibilityIdentifier("notebookNameField")
                    // 글자 수 — 숫자뿐이라 옮기지 않는다.
                    Text(verbatim: "\(name.count)/\(NotebookNaming.maxLength)")
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.secondary)
                        .accessibilityHidden(true)
                }

                if isCreating {
                    VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
                        Text("지금 보던 장이 새 필사책의 빈 종이로 열려요", bundle: .module, comment: "새 필사책 시트 안내(2.2 필사책 결정 6)")
                        Text("2.2 이전 버전을 쓰는 기기에서는 처음부터 있던 필사책만 보여요", bundle: .module)
                    }
                    .font(CarveTypography.label)
                    .foregroundStyle(CarveColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let failureMessage {
                    CarveStatusMessage(.failure, message: failureMessage)
                }

                Button(action: save) {
                    if isCreating {
                        Text("만들기", bundle: .module, comment: "새 필사책 시트의 만들기 버튼(2.2 필사책)")
                    } else {
                        Text("저장", bundle: .module, comment: "이름 바꾸기 시트의 저장 버튼(2.2 필사책)")
                    }
                }
                .buttonStyle(.carve(.primary, fillsWidth: true))
                .disabled(!canSave)
                .accessibilityIdentifier("notebookNameSave")
            }
            .padding(CarveSpacing.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .carvePresentationSurface()
        .interactiveDismissDisabled(isSaving)
        .onChange(of: name) { _, newValue in
            // 40자를 넘게 쓰지 못한다(설계 §6-4) — 붙여 넣어도 앞 40자만 남긴다.
            guard newValue.count > NotebookNaming.maxLength else { return }
            name = String(newValue.prefix(NotebookNaming.maxLength))
        }
        .onAppear {
            isFieldFocused = true
        }
    }

    /// 제목 — 「새 필사책」 · 「이름 바꾸기」.
    private var title: String {
        if isCreating {
            CarveFeatureCatalog.string("새 필사책", locale: locale)
        } else {
            CarveFeatureCatalog.string("이름 바꾸기", locale: locale)
        }
    }

    private func save() {
        guard canSave else { return }
        onSave(name)
    }
}
