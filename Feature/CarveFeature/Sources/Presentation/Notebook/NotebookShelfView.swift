//
//  NotebookShelfView.swift
//  CarveFeature
//
//  Created by Claude on 10/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Domain
import SwiftUI

import CarveToolkit
import ComposableArchitecture
import UIComponents

/// 책장 화면(2.2 회차별 필사책, 설계 §6-1 · 시안 `docs/design/assets/figma/p1-notebook-shelf.svg`). 차트 · 즐겨찾기처럼 앱 스택에 올라간다.
///
/// 시스템 막대 대신 종이 위에 떠 있는 버튼 둘(「‹ 서재」 · 「+ 새 필사책」)을 두고, 큰 제목 · 머리 문장 · 「나의 필사책 N」 아래에
/// 필사책 표지 격자(표지 · 이름 · 시작 월 · 쓴 절 수 · 지금 쓰는 중 · 완료 배지)와 점선 「새 필사책」, 맨 아래 옛 기기 안내(결정 14)를 둔다.
/// 표지를 누르면 그 필사책으로 필사 화면에 돌아가고, 이름 옆 더보기 메뉴로 이름 바꾸기 · 완료 표시 · 지우기를 한다.
@ViewAction(for: NotebookShelfFeature.self)
public struct NotebookShelfView: View {
    @Bindable public var store: StoreOf<NotebookShelfFeature>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// 화면 언어 — 미리 만드는 문구(이름 · 시작 월 · 쓴 절 수 · 안내 · 제안 이름)를 이 값으로 만든다.
    @Environment(\.locale) private var locale
    /// 스크롤 영역의 보이는 높이 — 필사책이 적어도 옛 기기 안내를 화면 맨 아래에 둔다(시안).
    @State private var visibleHeight: CGFloat = 0

    public init(store: StoreOf<NotebookShelfFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
                Spacer(minLength: CarveSpacing.medium)
                compatibilityNotice
            }
            .padding(.horizontal, horizontalInset)
            .padding(.top, CarveSpacing.xSmall)
            .padding(.bottom, CarveSpacing.small)
            .frame(minHeight: visibleHeight, alignment: .top)
        }
        // 스크롤 영역의 배치 크기는 위 막대 · 홈 표시줄(안전 영역)을 뺀 보이는 높이다.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            visibleHeight = height
        }
        .background(CarveColor.canvas)
        // 시안은 시스템 막대 없이 종이 위에 떠 있는 버튼 둘을 둔다 — 내용이 그 아래로 지나간다.
        // 막대를 숨기면 UIKit 이 뒤로 쓸기를 막으므로 이 화면에서만 다시 켠다(즐겨찾기처럼 왼쪽 가장자리로 서재에 돌아간다).
        .toolbar(.hidden, for: .navigationBar)
        .edgeSwipeBackEnabled()
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
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

    /// 좌우 여백 — 시안 가로 화면은 80pt, 좁은 창(분할 화면)은 줄인다.
    private var horizontalInset: CGFloat {
        horizontalSizeClass == .compact ? CarveSpacing.large : 80
    }

    /// 위 막대 — 왼쪽 「‹ 서재」(필사 화면으로 돌아가기), 오른쪽 「+ 새 필사책」. 둘 다 종이 위에 떠 있는 버튼(iOS 26 은 유리)이다.
    /// 안쪽 여백은 시안대로 보이는 그림 기준이다 — 꺾쇠 아이콘(24pt 틀 안 x 8 ~ 15)은 틀 안 빈 곳만큼 덜 띄운다.
    private var topBar: some View {
        HStack {
            Button {
                send(.backTapped)
            } label: {
                HStack(spacing: 6) {
                    CarveIcon.chevronLeft.image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                    Text("서재", bundle: .module, comment: "책장 화면 왼쪽 위 돌아가기 버튼 — 필사 화면(서재)으로(2.2 필사책 시안 P1)")
                }
                .foregroundStyle(CarveColor.ink)
            }
            .buttonStyle(NotebookShelfCapsuleButtonStyle(leading: 10))
            .accessibilityIdentifier("notebookShelfBack")

            Spacer(minLength: CarveSpacing.medium)

            Button {
                send(.newNotebookTapped)
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: "plus")
                        .font(.body.weight(.regular))
                        .foregroundStyle(CarveColor.accent)
                        .accessibilityHidden(true)
                    Text("새 필사책", bundle: .module)
                        .fontWeight(.medium)
                        .foregroundStyle(CarveColor.ink)
                }
            }
            .buttonStyle(NotebookShelfCapsuleButtonStyle(leading: 13))
            .disabled(store.isWorking)
            .accessibilityIdentifier("newNotebookButton")
        }
        .padding(.horizontal, CarveSpacing.xLarge)
        .padding(.top, CarveSpacing.xSmall)
        .padding(.bottom, CarveSpacing.xSmall)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
                .padding(.bottom, CarveSpacing.large + CarveSpacing.xxSmall)

            if !store.hasLoaded {
                // 조회 중 — 실패 화면으로 깜빡이지 않도록 자리만 둔다.
                Color.clear.frame(height: 240)
            } else if store.loadFailed {
                loadFailedState
            } else {
                sectionHeader
                    .padding(.bottom, 18)
                grid
            }
        }
    }

    /// 큰 제목 「책장」 과 머리 문장 — 두 기준선 사이 27pt(시안).
    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("책장", bundle: .module, comment: "책장 화면 제목 · 서재 열 아래 책장 버튼 VoiceOver 이름(2.2 필사책)")
                .font(.title.weight(.bold))
                .foregroundStyle(CarveColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text("말씀을 쓰고, 나만의 기록으로 간직해요", bundle: .module, comment: "책장 화면 머리 문장(2.2 필사책 시안 P1)")
                .font(.subheadline)
                .foregroundStyle(CarveColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 「나의 필사책 N」 — 격자 위 묶음 제목과 필사책 수.
    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: CarveSpacing.large) {
            Text("나의 필사책", bundle: .module, comment: "책장 표지 격자 위 묶음 제목 — 옆에 필사책 수(2.2 필사책 시안 P1)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CarveColor.ink)
            Text(verbatim: store.notebooks.count.formatted(.number.locale(locale)))
                .font(.subheadline)
                .foregroundStyle(CarveColor.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// 표지 격자 칸 — 표지는 칸 가운데에 놓인다. 시안 1180pt 가로 화면(좌우 80pt 안쪽 1020pt)에서 세 칸 · 표지 사이 170pt 가 되는
    /// 최소 폭 250 · 칸 사이 54 이고(iPad mini 세로 두 칸 · 13형 가로 네 칸), 좁은 창(분할 화면)은 두 칸이 들어가도록 줄인다.
    private var gridColumns: [GridItem] {
        let isCompact = horizontalSizeClass == .compact
        return [
            GridItem(
                .adaptive(minimum: isCompact ? NotebookCoverView.size.width : 250),
                spacing: isCompact ? CarveSpacing.large : 54,
                alignment: .top
            )
        ]
    }

    /// 필사책 표지 격자 — 필사책마다 표지 하나, 마지막에 점선 「새 필사책」. 줄 사이는 시안의 306pt 줄 간격(완료 배지가 있는 줄)에 맞춘다.
    private var grid: some View {
        LazyVGrid(columns: gridColumns, alignment: .center, spacing: CarveSpacing.medium + CarveSpacing.xxSmall) {
            ForEach(store.notebooks) { notebook in
                NotebookShelfItem(
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
            NewNotebookPlaceholder {
                send(.newNotebookTapped)
            }
            .disabled(store.isWorking)
        }
    }

    /// 맨 아래 옛 기기 안내(결정 14) — 구분선 아래 가운데. 2.2 이전 앱에는 처음부터 있던 필사책만 보인다(설계 §4-2).
    private var compatibilityNotice: some View {
        VStack(spacing: CarveSpacing.small) {
            Rectangle()
                .fill(CarveColor.divider)
                .frame(height: 0.7)
                .accessibilityHidden(true)
            Text("2.2 이전 버전을 쓰는 기기에서는 처음부터 있던 필사책만 보여요", bundle: .module, comment: "책장 아래 · 새 필사책 시트의 옛 기기 안내(2.2 필사책)")
                .font(.caption2)
                .foregroundStyle(CarveColor.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
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

    /// 역할: 표지 아래 기록 한 줄(「2026년 10월 시작 · 128절 필사」 · 「Started October 2026 · 128 verses written」, 시안 P1).
    /// 입력 · 출력: 필사책 · 달력 · 로케일 → 시작 월과 쓴 절 수를 「 · 」 로 이은 문구. 만든 시각을 모르면 쓴 절 수만.
    /// 부작용: 없음.
    static func metadataText(of notebook: NotebookSnapshot, calendar: Calendar = .current, locale: Locale) -> String {
        let verses = writtenVersesText(notebook.writtenVerseCount, locale: locale)
        guard let createdAt = notebook.createdAt else { return verses }
        return startedText(createdAt, calendar: calendar, locale: locale) + " · " + verses
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

// MARK: - 표지 칸

/// 책장 표지 칸 — 표지(「지금 쓰는 중」 배지)와 그 아래 이름 · 더보기 · 시작 월 · 쓴 절 수 · 「완료됨」 배지(시안 P1).
private struct NotebookShelfItem: View {
    let notebook: NotebookSnapshot
    /// 이 기기의 지금 필사책인가 — 표지 위 「지금 쓰는 중」 배지.
    let isCurrent: Bool
    /// 완료 표시 · 지우기를 저장하는 중 — 고르기 · 메뉴를 막는다.
    let isDisabled: Bool
    let onChoose: () -> Void
    let onRename: () -> Void
    let onToggleCompletion: () -> Void
    let onDelete: () -> Void
    /// 화면 언어 — 이름이 없을 때의 기본 표시 · 시작 월 · 쓴 절 수 · 표지 번호를 이 값으로 만든다.
    @Environment(\.locale) private var locale

    /// 이름 줄 오른쪽 더보기 자리 — 이름이 여기까지 오지 않는다.
    private static let moreButtonReserve: CGFloat = 28
    /// 표지와 이름 사이 — 이름 기준선이 표지 아래 24pt(시안).
    private static let coverToNameSpacing: CGFloat = 10
    /// 더보기 점 세 개의 가운데 — 표지 오른쪽 끝에서 1pt 안 · 표지 아래 19pt(시안 more x 187 · y 229, 이름 기준선보다 5pt 위).
    private static let moreDotsCenter = CGPoint(x: NotebookCoverView.size.width - 1, y: NotebookCoverView.size.height + 19)

    private var isCompleted: Bool {
        notebook.status == .completed
    }

    var body: some View {
        Button(action: onChoose) {
            VStack(alignment: .leading, spacing: 0) {
                NotebookCoverView(style: NotebookCoverStyle.make(for: notebook, locale: locale))
                    .overlay(alignment: .topTrailing) {
                        if isCurrent { currentBadge }
                    }
                    .padding(.bottom, Self.coverToNameSpacing)
                // 사용자가 지은 이름은 옮기지 않는다(`NotebookNaming`).
                Text(verbatim: NotebookNaming.displayName(of: notebook, locale: locale))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CarveColor.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .padding(.trailing, Self.moreButtonReserve)
                    .padding(.bottom, 6)
                Text(verbatim: NotebookShelfView.metadataText(of: notebook, locale: locale))
                    .font(.caption2)
                    .foregroundStyle(CarveColor.secondary)
                    .lineLimit(2)
                if isCompleted {
                    completedBadge
                        .padding(.top, CarveSpacing.xSmall)
                }
            }
            .frame(width: NotebookCoverView.size.width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .overlay(alignment: .topLeading) {
            // 44pt 누름 자리의 가운데를 시안의 점 자리에 놓는다.
            moreMenu
                .offset(
                    x: Self.moreDotsCenter.x - CarveSize.minimumHitTarget / 2,
                    y: Self.moreDotsCenter.y - CarveSize.minimumHitTarget / 2
                )
        }
    }

    /// 「● 지금 쓰는 중」 — 표지 오른쪽 위에 걸친다(시안: 표지 오른쪽 끝보다 12pt 밖까지, 글자는 표지 안에서 끝난다).
    private var currentBadge: some View {
        HStack(spacing: 7.5) {
            Circle()
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)
            Text("지금 쓰는 중", bundle: .module, comment: "책장 카드 배지 — 이 기기의 지금 필사책(2.2 필사책)")
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(CarveColor.canvas)
        .padding(.leading, 9.5)
        .padding(.trailing, 26)
        .frame(height: 25)
        .background(CarveColor.accent, in: Capsule())
        .padding(.top, 10)
        .offset(x: 12)
    }

    /// 「✓ 완료됨」 배지.
    private var completedBadge: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(CarveColor.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(CarveColor.canvas)
            }
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
            Text("완료됨", bundle: .module, comment: "책장 카드 배지 — 완료로 표시한 필사책(2.2 필사책)")
                .font(.system(size: 10))
                .foregroundStyle(CarveColor.accent)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, 6)
        .padding(.trailing, 17)
        .frame(height: 21)
        .background(CarveColor.selected, in: Capsule())
    }

    /// 더보기 — 이름 바꾸기 · 완료로 표시/완료 취소 · 필사책 지우기(기본 필사책에는 없다, 결정 7).
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
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(CarveColor.secondary)
                .frame(width: CarveSize.minimumHitTarget, height: CarveSize.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .accessibilityLabel(Text("더보기", bundle: .module))
        .accessibilityValue(Text(verbatim: NotebookNaming.displayName(of: notebook, locale: locale)))
    }
}

/// 점선 「새 필사책」 — 표지 크기의 빈 자리. 이름 시트를 연다.
private struct NewNotebookPlaceholder: View {
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Button(action: action) {
            VStack(spacing: CarveSpacing.small) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .light))
                    .accessibilityHidden(true)
                Text("새 필사책", bundle: .module, comment: "책장의 새 필사책 카드 · 새 필사책 시트 제목(2.2 필사책)")
                    .font(.subheadline)
            }
            .foregroundStyle(CarveColor.accent)
            .frame(width: NotebookCoverView.size.width, height: NotebookCoverView.size.height)
            .background {
                shape.strokeBorder(CarveColor.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .frame(width: NotebookCoverView.size.width, alignment: .leading)
        .accessibilityIdentifier("newNotebookCard")
    }
}

/// 책장 위 막대의 캡슐 버튼 — 종이 위에 떠 있는 표면(iOS 26 은 유리, 그 밖은 불투명 `surface`)에 높이 44pt.
/// 오른쪽 안쪽 여백은 시안의 18pt, 왼쪽은 아이콘 틀의 빈 곳을 뺀 값을 버튼마다 받는다.
private struct NotebookShelfCapsuleButtonStyle: ButtonStyle {
    let leading: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .lineLimit(1)
            .padding(.leading, leading)
            .padding(.trailing, 18)
            .frame(minHeight: CarveSize.minimumHitTarget)
            .carveSurface(.floatingControl, in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
    }
}
