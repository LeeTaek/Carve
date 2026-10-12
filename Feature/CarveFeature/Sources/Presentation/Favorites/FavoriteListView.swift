//
//  FavoriteListView.swift
//  CarveFeature
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Domain
import SwiftUI
import UIKit

import ComposableArchitecture
import UIComponents

/// 즐겨찾기 목록(시안 N4 · N5). 차트와 같이 앱 스택에 올라가며 뒤로 가기는 시스템 막대를 쓴다.
@ViewAction(for: FavoriteListFeature.self)
public struct FavoriteListView: View {
    @Bindable public var store: StoreOf<FavoriteListFeature>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 카드 폭의 상한(시안 1180pt 화면에서 좌우 64pt 안쪽). 좁은 창에서는 가로 여백만 남긴다.
    private static let contentMaxWidth: CGFloat = 1052

    public init(store: StoreOf<FavoriteListFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            content
                .frame(maxWidth: Self.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, CarveSpacing.xLarge)
                .padding(.top, CarveSpacing.large)
                // 아래 안내가 마지막 카드를 가리지 않게 비운다.
                .padding(.bottom, CarveSpacing.xLarge * 3)
        }
        .background(CarveColor.canvas)
        .navigationTitle(Text("즐겨찾기", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                titleView
            }
        }
        .overlay(alignment: .bottom) {
            noticeView
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: store.notice)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: store.favorites)
        // 위젯에 담긴 말씀을 해제하기 전 확인(시안 N9).
        .alert($store.scope(state: \.removeConfirm, action: \.removeConfirm))
        .task {
            send(.task)
        }
    }

    /// 제목 — 채운 별과 「즐겨찾기」(시안 N4).
    private var titleView: some View {
        HStack(spacing: CarveSpacing.xSmall) {
            CarveIcon.starFill.image
                .foregroundStyle(CarveColor.accent)
                .accessibilityHidden(true)
            Text("즐겨찾기", bundle: .module)
                .font(CarveTypography.title)
                .foregroundStyle(CarveColor.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.medium) {
            Text("마음에 남은 말씀과 필사를 모아봐요", bundle: .module)
                .font(.body)
                .foregroundStyle(CarveColor.ink)

            if !store.hasLoaded {
                // 조회 중 — 빈 상태로 깜빡이지 않도록 자리만 둔다.
                Color.clear.frame(height: 240)
            } else if store.favorites.isEmpty {
                if store.loadFailed {
                    loadFailedState
                } else {
                    emptyState
                }
            } else {
                favoritesList
            }
        }
    }

    private var favoritesList: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.large) {
            HStack(spacing: CarveSpacing.small) {
                Text("\(store.favorites.count)개의 말씀", bundle: .module)
                Spacer(minLength: 0)
                Text("최근 추가순", bundle: .module)
            }
            .font(CarveTypography.body)
            .foregroundStyle(CarveColor.ink)

            LazyVStack(spacing: CarveSpacing.large) {
                ForEach(store.favorites) { favorite in
                    FavoriteVerseCard(
                        favorite: favorite,
                        isOnWidget: store.widgetKeys.contains(favorite.key),
                        onUnfavorite: { send(.unfavoriteTapped(favorite.key)) },
                        onWidget: { send(.widgetTapped(favorite.key)) },
                        onOpen: { send(.openVerseTapped(favorite.key)) }
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    /// 빈 목록(시안 N5) — 롱탭으로 추가한다는 안내와 필사 화면으로 돌아가는 길.
    private var emptyState: some View {
        VStack(spacing: CarveSpacing.medium) {
            CarveIcon.star.image
                .resizable()
                .frame(width: 48, height: 48)
                .foregroundStyle(CarveColor.accent)
                .accessibilityHidden(true)
            CarveEmptyState(
                String(localized: "아직 즐겨찾기한 말씀이 없어요", bundle: .module),
                message: String(localized: "필사 화면에서 절을 길게 눌러 즐겨찾기에 추가해 보세요.", bundle: .module),
                actionTitle: String(localized: "말씀 보러 가기", bundle: .module)
            ) {
                send(.backToWritingTapped)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    private var loadFailedState: some View {
        CarveEmptyState(
            String(localized: "즐겨찾기를 불러오지 못했어요", bundle: .module),
            message: String(localized: "잠시 후 다시 시도해 주세요.", bundle: .module),
            actionTitle: String(localized: "다시 시도", bundle: .module)
        ) {
            send(.retryLoadTapped)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    @ViewBuilder
    private var noticeView: some View {
        if let notice = store.notice {
            Group {
                switch notice {
                case .removed:
                    CarveStatusMessage(.success, message: Self.message(for: notice), retryTitle: String(localized: "실행 취소", bundle: .module)) {
                        send(.noticeActionTapped)
                    }
                case .removeFailed, .restoreFailed, .widgetFailed:
                    CarveStatusMessage(.failure, message: Self.message(for: notice)) {
                        send(.noticeActionTapped)
                    }
                case .widgetLimitReached, .blocked:
                    // 다시 눌러도 같은 결과다 — 버튼 없이 알리기만 한다.
                    CarveStatusMessage(.failure, message: Self.message(for: notice))
                case .widgetAdded, .widgetRemoved:
                    // 되돌릴 것이 없다 — 버튼 없이 알리기만 한다.
                    CarveStatusMessage(.success, message: Self.message(for: notice))
                }
            }
            .padding(.horizontal, CarveSpacing.large)
            .padding(.bottom, CarveSpacing.large)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            .onChange(of: notice, initial: true) { _, notice in
                AccessibilityNotification.Announcement(Self.message(for: notice)).post()
            }
        }
    }

    static func message(for notice: FavoriteListFeature.Notice) -> String {
        switch notice {
        case .removed: String(localized: "즐겨찾기에서 해제했어요", bundle: .module)
        case .removeFailed: String(localized: "즐겨찾기를 해제하지 못했어요", bundle: .module)
        case .restoreFailed: String(localized: "즐겨찾기를 되돌리지 못했어요", bundle: .module)
        case .widgetAdded: String(localized: "위젯에 담았어요", bundle: .module)
        case .widgetRemoved: String(localized: "위젯에서 뺐어요", bundle: .module)
        case .widgetLimitReached: String(localized: "위젯에는 \(WidgetVerseLimit.maximum)개까지 담을 수 있어요", bundle: .module)
        case .widgetFailed: String(localized: "위젯을 바꾸지 못했어요", bundle: .module)
        case .blocked(let block): String(localized: "즐겨찾기를 바꾸지 않았어요. \(block.reasonText)", bundle: .module)
        }
    }

    /// 역할: 카드 제목의 참조(「시편 23장 1절」 · 「Psalm 23:1」)를 `BibleReference` 로 짓는다.
    ///   권 이름 · 장절 표기는 앱 언어를 따르고, 번역본 약칭은 붙이지 않는다 — 카드가 그 아래 줄에 따로 적는다(`translationText`).
    /// 입력 · 출력: 즐겨찾기 키 · 로케일(nil 이면 앱 언어) → 참조 문자열.
    /// 부작용: 없음.
    static func referenceText(_ key: FavoriteVerseKey, locale: Locale? = nil) -> String {
        BibleReference(chapter: key.chapter, verse: key.verse).text(locale: locale)
    }

    /// 역할: 카드의 번역본 약칭(「개역개정」 · 「KJV」). 같은 절이라도 번역본이 다르면 다른 카드다(영어 현지화 결정 1 · 11).
    /// 입력 · 출력: 즐겨찾기 키 · 로케일(nil 이면 앱 언어) → 키의 번역본(장의 번역본) 약칭.
    /// 부작용: 없음.
    static func translationText(_ key: FavoriteVerseKey, locale: Locale? = nil) -> String {
        key.translation.displayName(locale: locale)
    }

    /// 역할: 카드의 추가 날짜(「9월 15일 추가」 · 「Added September 15」). 올해가 아니면 연도를 붙인다.
    ///   날짜 표기는 고정 형식이 아니라 기기 로케일의 날짜 서식(`Date.FormatStyle`)을 따른다(영어 현지화 결정 5).
    /// 입력 · 출력: 추가 시각 · 지금 · 달력(시간대 포함) · 로케일(nil 이면 앱 · 기기 로케일) → 문구.
    /// 부작용: 없음.
    static func addedDateText(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale? = nil) -> String {
        var style = Date.FormatStyle(locale: locale ?? .autoupdatingCurrent, calendar: calendar, timeZone: calendar.timeZone)
            .month(.wide)
            .day()
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) {
            style = style.year()
        }
        return CarveFeatureCatalog.string("\(date.formatted(style)) 추가", locale: locale)
    }
}

// MARK: - 카드

/// 즐겨찾기 카드(시안 N4) — 권 · 장 · 절과 번역본, 추가할 때의 본문과 필기, 추가 날짜.
private struct FavoriteVerseCard: View {
    let favorite: FavoriteVerseSnapshot
    /// 지금 위젯에 담긴 말씀인가(시안 N4 배지).
    let isOnWidget: Bool
    let onUnfavorite: () -> Void
    let onWidget: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.medium) {
            HStack(alignment: .top, spacing: CarveSpacing.small) {
                VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
                    Text(FavoriteListView.referenceText(favorite.key))
                        .font(.title3)
                        .foregroundStyle(CarveColor.ink)
                    Text(FavoriteListView.translationText(favorite.key))
                        .font(CarveTypography.label)
                        .foregroundStyle(CarveColor.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)

                if isOnWidget {
                    widgetBadge
                }

                // 채운 별이 곧 44pt 해제 버튼이다(시안 N4). 터치 영역 여백만큼 카드 모서리 쪽으로 붙인다.
                Button(action: onUnfavorite) {
                    CarveIcon.starFill.image
                        .foregroundStyle(CarveColor.accent)
                        .frame(width: CarveSize.minimumHitTarget, height: CarveSize.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, -CarveSpacing.xSmall)
                .accessibilityLabel(Text("즐겨찾기 해제", bundle: .module))

                moreMenu
            }

            // 가로가 넉넉하면 본문 | 필기 두 열(시안), 좁은 창에서는 위아래로 둔다.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: CarveSpacing.xLarge) {
                    sentence
                        .frame(maxWidth: .infinity, alignment: .leading)
                    FavoriteHandwritingPreview(lineData: favorite.lineData)
                        .frame(maxWidth: .infinity)
                }
                .frame(minWidth: 560)

                VStack(alignment: .leading, spacing: CarveSpacing.medium) {
                    sentence
                    FavoriteHandwritingPreview(lineData: favorite.lineData)
                }
            }

            HStack(spacing: CarveSpacing.small) {
                Text(FavoriteListView.addedDateText(favorite.createdDate))
                    .font(CarveTypography.label)
                    .foregroundStyle(CarveColor.secondary)

                Spacer(minLength: 0)

                Button(action: onOpen) {
                    HStack(spacing: CarveSpacing.xxSmall) {
                        Text("말씀으로 이동", bundle: .module)
                        CarveIcon.chevronRight.image
                            .resizable()
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                    }
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.accent)
                    .frame(minHeight: CarveSize.minimumHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("말씀으로 이동", bundle: .module))
            }
        }
        .padding(.horizontal, CarveSpacing.large)
        .padding(.vertical, CarveSpacing.medium)
        .carveSurface(.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 「위젯에 담김」 배지(시안 N4 · N6).
    private var widgetBadge: some View {
        HStack(spacing: CarveSpacing.xxSmall) {
            CarveIcon.widget.image
                .resizable()
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            Text("위젯에 담김", bundle: .module)
                .font(CarveTypography.label)
        }
        .foregroundStyle(CarveColor.accent)
        .padding(.horizontal, CarveSpacing.small)
        .padding(.vertical, CarveSpacing.xxSmall)
        .background(CarveColor.selected, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    /// 카드 더보기(시안 N6) — 위젯에 담기와 즐겨찾기 해제.
    private var moreMenu: some View {
        Menu {
            Button(action: onWidget) {
                Label {
                    isOnWidget ? Text("위젯에서 빼기", bundle: .module) : Text("위젯에 추가", bundle: .module)
                } icon: {
                    CarveIcon.widget.image
                }
            }
            Button(role: .destructive, action: onUnfavorite) {
                Label {
                    Text("즐겨찾기 해제", bundle: .module)
                } icon: {
                    CarveIcon.starFill.image
                }
            }
        } label: {
            CarveIcon.more.image
                .foregroundStyle(CarveColor.secondary)
                .frame(width: CarveSize.minimumHitTarget, height: CarveSize.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .padding(.top, -CarveSpacing.xSmall)
        .padding(.trailing, -CarveSpacing.small)
        .accessibilityLabel(Text("더보기", bundle: .module))
        .accessibilityHint(isOnWidget ? Text("위젯에서 빼기 · 즐겨찾기 해제", bundle: .module) : Text("위젯에 추가 · 즐겨찾기 해제", bundle: .module))
    }

    private var sentence: some View {
        Text(favorite.sentence)
            .font(.title3)
            .foregroundStyle(CarveColor.ink)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 추가할 때 보존한 필기 미리보기.
///
/// 종이 위 필기라 외관과 무관한 종이 바탕에 비율을 지켜 줄인다 — 이전 필사 기록(시안 E2)의 썸네일과 같은 규칙이다.
/// 그림은 카드가 처음 나타날 때 한 번 만든다.
private struct FavoriteHandwritingPreview: View {
    let lineData: Data?

    @State private var rendered: Rendered = .pending

    private enum Rendered {
        case pending
        case image(UIImage)
        case unavailable
    }

    var body: some View {
        Group {
            if lineData == nil {
                Text("아직 필기하지 않은 말씀이에요", bundle: .module)
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 88)
            } else {
                paper
            }
        }
        .task(id: lineData) {
            guard lineData != nil else { return }
            rendered = CarveInkThumbnail.image(of: lineData).map(Rendered.image) ?? .unavailable
        }
    }

    private var paper: some View {
        Group {
            switch rendered {
            case .image(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 160)
                    .accessibilityLabel(Text("추가할 때의 필기", bundle: .module))
            case .unavailable:
                Text("불러올 수 없는 필사 데이터", bundle: .module)
                    .font(CarveTypography.label)
                    .foregroundStyle(CarveColor.Paper.secondary)
                    .frame(maxWidth: .infinity)
            case .pending:
                Color.clear
                    .frame(height: 64)
            }
        }
        .padding(CarveSpacing.small)
        .frame(maxWidth: .infinity, minHeight: 88)
        .background(CarveColor.Paper.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        FavoriteListView(
            store: Store(initialState: FavoriteListFeature.State.initialState) {
                FavoriteListFeature()
            }
        )
    }
}
