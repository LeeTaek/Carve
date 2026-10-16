//
//  NotebookShelfView.swift
//  CarveFeature
//
//  Created by Claude on 10/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Domain
import SwiftUI

import ComposableArchitecture
import UIComponents

/// 책장 화면(2.2 회차별 필사책, 설계 §6-1). 차트 · 즐겨찾기처럼 앱 스택에 올라가며 시스템 막대의 뒤로 가기도 그대로 쓴다.
///
/// 필사책 카드 격자(이름 · 시작 월 · 쓴 절 수 · 지금 쓰는 중 · 완료 배지)와 「새 필사책」 카드, 아래에 옛 기기 안내 한 줄(결정 14).
/// 카드를 누르면 그 필사책으로 필사 화면에 돌아가고, 카드의 더보기 메뉴로 이름 바꾸기 · 완료 표시 · 지우기를 한다.
@ViewAction(for: NotebookShelfFeature.self)
public struct NotebookShelfView: View {
    @Bindable public var store: StoreOf<NotebookShelfFeature>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 화면 언어 — 미리 만드는 문구(이름 · 시작 월 · 쓴 절 수 · 안내 · 제안 이름)를 이 값으로 만든다.
    @Environment(\.locale) private var locale

    /// 카드 격자 폭의 상한 — 즐겨찾기 목록과 같다(시안 1180pt 화면에서 좌우 64pt 안쪽).
    private static let contentMaxWidth: CGFloat = 1052

    public init(store: StoreOf<NotebookShelfFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            content
                .frame(maxWidth: Self.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, CarveSpacing.xLarge)
                .padding(.top, CarveSpacing.large)
                // 아래 안내가 마지막 줄을 가리지 않게 비운다.
                .padding(.bottom, CarveSpacing.xLarge * 3)
        }
        .background(CarveColor.canvas)
        .navigationTitle(Text("책장", bundle: .module, comment: "책장 화면 제목 · 서재 열 아래 책장 버튼(2.2 필사책)"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                titleView
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    send(.backTapped)
                } label: {
                    Text("닫기", bundle: .module)
                }
                .accessibilityIdentifier("notebookShelfBack")
            }
        }
        .overlay(alignment: .bottom) {
            noticeView
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: store.notice)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: store.notebooks)
        .alert($store.scope(state: \.deleteAlert, action: \.deleteAlert))
        .sheet(item: editorBinding) { editor in
            // 저장 중 · 실패는 리듀서가 바꾼다 — 시트가 떠 있는 동안 바뀐 값을 읽는다.
            let current = store.editor ?? editor
            NotebookNameSheet(
                isCreating: current.purpose == .create,
                initialName: initialName(for: current.purpose),
                isSaving: current.isSaving,
                failureMessage: current.failure.map { Self.failureMessage($0, purpose: current.purpose, locale: locale) },
                onSave: { send(.editorSaveTapped($0)) },
                onCancel: { send(.editorDismissed) }
            )
        }
        .onAppear {
            send(.onAppear)
        }
    }

    /// 제목 — 책장 아이콘과 「책장」.
    private var titleView: some View {
        HStack(spacing: CarveSpacing.xSmall) {
            CarveIcon.library.image
                .foregroundStyle(CarveColor.accent)
                .accessibilityHidden(true)
            Text("책장", bundle: .module)
                .font(CarveTypography.title)
                .foregroundStyle(CarveColor.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.large) {
            Text("같은 말씀을 필사책마다 따로 쓰고 간직해요", bundle: .module, comment: "책장 화면 머리 문장(2.2 필사책)")
                .font(.body)
                .foregroundStyle(CarveColor.ink)

            if !store.hasLoaded {
                // 조회 중 — 실패 화면으로 깜빡이지 않도록 자리만 둔다.
                Color.clear.frame(height: 240)
            } else if store.loadFailed {
                loadFailedState
            } else {
                grid
            }

            // 옛 기기 안내(결정 14) — 2.2 이전 앱에는 처음부터 있던 필사책만 보인다(설계 §4-2).
            Text("2.2 이전 버전을 쓰는 기기에서는 처음부터 있던 필사책만 보여요", bundle: .module, comment: "책장 아래 · 새 필사책 시트의 옛 기기 안내(2.2 필사책)")
                .font(CarveTypography.label)
                .foregroundStyle(CarveColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 필사책 카드 격자 — 필사책마다 카드 하나, 마지막에 「새 필사책」.
    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: CarveSpacing.large, alignment: .top)],
            alignment: .leading,
            spacing: CarveSpacing.large
        ) {
            ForEach(store.notebooks) { notebook in
                NotebookCard(
                    notebook: notebook,
                    isCurrent: notebook.id == store.currentNotebook,
                    isDisabled: store.isWorking,
                    onChoose: { send(.notebookTapped(notebook.id)) },
                    onRename: { send(.renameTapped(notebook.id)) },
                    onToggleCompletion: { send(.completionToggled(notebook.id)) },
                    onDelete: { send(.deleteTapped(notebook.id)) }
                )
                .transition(.opacity)
            }
            NewNotebookCard {
                send(.newNotebookTapped)
            }
            .disabled(store.isWorking)
        }
    }

    private var loadFailedState: some View {
        CarveEmptyState(
            CarveFeatureCatalog.string("필사책을 불러오지 못했어요", locale: locale),
            message: CarveFeatureCatalog.string("잠시 후 다시 시도해 주세요.", locale: locale),
            actionTitle: CarveFeatureCatalog.string("다시 시도", locale: locale)
        ) {
            send(.retryLoadTapped)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    @ViewBuilder
    private var noticeView: some View {
        if let notice = store.notice {
            CarveStatusMessage(.failure, message: Self.noticeMessage(notice, locale: locale))
                .padding(.horizontal, CarveSpacing.large)
                .padding(.bottom, CarveSpacing.large)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .onChange(of: notice, initial: true) { _, notice in
                    AccessibilityNotification.Announcement(Self.noticeMessage(notice, locale: locale)).post()
                }
        }
    }

    /// 이름 시트의 표시. 「취소」 · 끌어내림으로 닫히면 리듀서에 알린다.
    private var editorBinding: Binding<NotebookShelfFeature.NameEditor?> {
        Binding(
            get: { store.editor },
            set: { editor in
                if editor == nil { send(.editorDismissed) }
            }
        )
    }

    /// 이름 시트 입력란의 처음 이름 — 새 필사책은 제안 이름, 이름 바꾸기는 지금 보이는 이름(이름이 없으면 기본 표시).
    private func initialName(for purpose: NotebookShelfFeature.NameEditor.Purpose) -> String {
        switch purpose {
        case .create:
            NotebookNaming.suggestedName(existing: store.notebooks, locale: locale)
        case .rename(let notebook):
            store.notebooks[id: notebook].map { NotebookNaming.displayName(of: $0, locale: locale) } ?? ""
        }
    }
}

// MARK: - 문구

extension NotebookShelfView {
    /// 역할: 카드의 시작 월(「2026년 10월 시작」 · 「Started October 2026」) — 넘긴 로케일의 연 · 월 서식(결정 9).
    /// 입력 · 출력: 만든 시각 · 달력(시간대 포함) · 로케일(뷰는 환경 locale 을 넘긴다) → 문구.
    /// 부작용: 없음.
    static func startedText(_ date: Date, calendar: Calendar = .current, locale: Locale) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .year()
            .month(.wide)
        return CarveFeatureCatalog.string("\(date.formatted(style)) 시작", locale: locale)
    }

    /// 역할: 카드의 쓴 절 수(「12절 필사」 · 「12 verses written」) — 모든 번역본을 합친 수, 복수형 카탈로그.
    /// 입력 · 출력: 절 수 · 로케일 → 문구.
    /// 부작용: 없음.
    static func writtenVersesText(_ count: Int, locale: Locale) -> String {
        CarveFeatureCatalog.string("\(count)절 필사", locale: locale)
    }

    /// 역할: 관리 동작을 동기화 저장소에 쓰지 않고 막은 안내 — 「지금은 필사책을 만들거나 고칠 수 없어요. <사유>」.
    /// 입력 · 출력: 막은 사유 · 로케일 → 문구. 사유 문장은 즐겨찾기와 같은 것(`SyncedWriteBlock.reasonText`)이다.
    /// 부작용: 없음.
    static func blockedMessage(_ block: SyncedWriteBlock, locale: Locale) -> String {
        CarveFeatureCatalog.string("지금은 필사책을 만들거나 고칠 수 없어요. \(block.reasonText(locale: locale))", locale: locale)
    }

    /// 역할: 책장 아래 결과 안내 문구.
    /// 입력 · 출력: 안내 · 로케일 → 문구.
    /// 부작용: 없음.
    static func noticeMessage(_ notice: NotebookShelfFeature.Notice, locale: Locale) -> String {
        switch notice {
        case .blocked(let block): blockedMessage(block, locale: locale)
        case .completionFailed: CarveFeatureCatalog.string("완료 표시를 바꾸지 못했어요", locale: locale)
        case .deleteFailed: CarveFeatureCatalog.string("필사책을 지우지 못했어요", locale: locale)
        }
    }

    /// 역할: 이름 시트 안의 실패 문구.
    /// 입력 · 출력: 실패 · 시트 용도 · 로케일 → 문구.
    /// 부작용: 없음.
    static func failureMessage(
        _ failure: NotebookShelfFeature.Failure,
        purpose: NotebookShelfFeature.NameEditor.Purpose,
        locale: Locale
    ) -> String {
        switch (failure, purpose) {
        case (.blocked(let block), _): blockedMessage(block, locale: locale)
        case (.saveFailed, .create): CarveFeatureCatalog.string("필사책을 만들지 못했어요", locale: locale)
        case (.saveFailed, .rename): CarveFeatureCatalog.string("이름을 바꾸지 못했어요", locale: locale)
        }
    }
}

// MARK: - 카드

/// 필사책 카드 — 이름 · 시작 월 · 쓴 절 수 · 「지금 쓰는 중」 · 「완료됨」 배지와 더보기 메뉴(설계 §6-1).
private struct NotebookCard: View {
    let notebook: NotebookSnapshot
    /// 이 기기의 지금 필사책인가 — 배지와 강조 테두리.
    let isCurrent: Bool
    /// 완료 표시 · 지우기를 저장하는 중 — 고르기 · 메뉴를 막는다.
    let isDisabled: Bool
    let onChoose: () -> Void
    let onRename: () -> Void
    let onToggleCompletion: () -> Void
    let onDelete: () -> Void
    /// 화면 언어 — 이름이 없을 때의 기본 표시 · 시작 월 · 쓴 절 수를 이 값으로 만든다.
    @Environment(\.locale) private var locale

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CarveRadius.card, style: .continuous)
    }

    private var isCompleted: Bool {
        notebook.status == .completed
    }

    var body: some View {
        Button(action: onChoose) {
            VStack(alignment: .leading, spacing: CarveSpacing.small) {
                badges
                // 사용자가 지은 이름은 옮기지 않는다(`NotebookNaming`).
                Text(verbatim: NotebookNaming.displayName(of: notebook, locale: locale))
                    .font(CarveTypography.title)
                    .foregroundStyle(CarveColor.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                Spacer(minLength: CarveSpacing.small)
                VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
                    if let createdAt = notebook.createdAt {
                        Text(verbatim: NotebookShelfView.startedText(createdAt, locale: locale))
                    }
                    Text(verbatim: NotebookShelfView.writtenVersesText(notebook.writtenVerseCount, locale: locale))
                }
                .font(CarveTypography.label)
                .foregroundStyle(CarveColor.secondary)
            }
            // 오른쪽 위 더보기 버튼 자리를 비운다.
            .padding(.trailing, CarveSize.minimumHitTarget - CarveSpacing.small)
            .padding(CarveSpacing.large)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
            .carveSurface(.panel, in: shape)
            .overlay {
                if isCurrent {
                    shape.strokeBorder(CarveColor.accent, lineWidth: 2)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .overlay(alignment: .topTrailing) {
            moreMenu
        }
    }

    /// 「지금 쓰는 중」 · 「완료됨」 배지 줄. 배지가 없어도 자리를 지켜 카드끼리 이름 높이가 맞는다.
    private var badges: some View {
        HStack(spacing: CarveSpacing.xxSmall) {
            if isCurrent {
                Text("지금 쓰는 중", bundle: .module, comment: "책장 카드 배지 — 이 기기의 지금 필사책(2.2 필사책)")
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.accent)
                    .padding(.horizontal, CarveSpacing.xSmall)
                    .padding(.vertical, 2)
                    .background(CarveColor.selected, in: Capsule())
            }
            if isCompleted {
                HStack(spacing: 2) {
                    CarveIcon.checkmark.image
                        .resizable()
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                    Text("완료됨", bundle: .module, comment: "책장 카드 배지 — 완료로 표시한 필사책(2.2 필사책)")
                        .font(CarveTypography.caption)
                }
                .foregroundStyle(CarveColor.ink)
                .padding(.horizontal, CarveSpacing.xSmall)
                .padding(.vertical, 2)
                .background(CarveColor.fill, in: Capsule())
            }
        }
        .frame(minHeight: 22, alignment: .leading)
    }

    /// 카드 더보기 — 이름 바꾸기 · 완료로 표시/완료 취소 · 필사책 지우기(기본 필사책에는 없다, 결정 7).
    private var moreMenu: some View {
        Menu {
            Button(action: onRename) {
                Label {
                    Text("이름 바꾸기", bundle: .module, comment: "책장 카드 메뉴 · 이름 시트 제목(2.2 필사책)")
                } icon: {
                    CarveIcon.pen.image
                }
            }
            Button(action: onToggleCompletion) {
                Label {
                    if isCompleted {
                        Text("완료 취소", bundle: .module, comment: "책장 카드 메뉴 — 완료 표시를 지운다(2.2 필사책)")
                    } else {
                        Text("완료로 표시", bundle: .module, comment: "책장 카드 메뉴 — 표시일 뿐 계속 쓸 수 있다(2.2 필사책)")
                    }
                } icon: {
                    CarveIcon.checkmark.image
                }
            }
            if !notebook.id.isDefault {
                Button(role: .destructive, action: onDelete) {
                    Label {
                        Text("필사책 지우기", bundle: .module, comment: "책장 카드 메뉴 — 확인 뒤 그 필사책과 필기를 지운다(2.2 필사책)")
                    } icon: {
                        CarveIcon.trash.image
                    }
                }
            }
        } label: {
            CarveIcon.more.image
                .foregroundStyle(CarveColor.secondary)
                .frame(width: CarveSize.minimumHitTarget, height: CarveSize.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .padding(.top, CarveSpacing.xSmall)
        .padding(.trailing, CarveSpacing.xSmall)
        .accessibilityLabel(Text("더보기", bundle: .module))
        .accessibilityValue(Text(verbatim: NotebookNaming.displayName(of: notebook, locale: locale)))
    }
}

/// 「새 필사책」 카드 — 이름 시트를 연다.
private struct NewNotebookCard: View {
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CarveRadius.card, style: .continuous)
        Button(action: action) {
            VStack(spacing: CarveSpacing.small) {
                Image(systemName: "plus")
                    .font(.title2.weight(.light))
                    .accessibilityHidden(true)
                Text("새 필사책", bundle: .module, comment: "책장의 새 필사책 카드 · 새 필사책 시트 제목(2.2 필사책)")
                    .font(CarveTypography.title)
            }
            .foregroundStyle(CarveColor.accent)
            .frame(maxWidth: .infinity, minHeight: 176)
            .background {
                shape.strokeBorder(CarveColor.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("newNotebookCard")
    }
}
