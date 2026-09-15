//
//  CarveNavigationView.swift
//  AppManifests
//
//  Created by 이택성 on 1/22/24.
//

import CarveToolkit
import Domain
import SwiftUI
import Resources

import ComposableArchitecture
import UIComponents

/// Carve 디테일 화면의 네비게이션 담당
@ViewAction(for: CarveNavigationFeature.self)
public struct CarveNavigationView: View {
    @Bindable public var store: StoreOf<CarveNavigationFeature>
    @Environment(\.scenePhase) private var scenePhase
    @State private var searchText = ""
    @State private var testament: Testament
    
    public init(store: StoreOf<CarveNavigationFeature>) {
        self.store = store
        self.testament = store.currentTitle.title.isOldtestment ? .old : .new
    }
    
    public var body: some View {
        NavigationSplitView(columnVisibility: $store.columnVisibility) {
            sideBar
                .navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 320)
        } content: {
            contentList
                .navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 320)
        } detail: {
            detailView()
                .overlay {
                    if store.columnVisibility != .detailOnly {
                        // 본문을 딤 처리하고 탭하면 탐색을 닫는다. scrim 토큰의 기본 alpha(0.18)에
                        // 0.55를 곱해 가로 시안의 약 10% 가림막으로 맞춘다.
                        CarveColor.scrim
                            .opacity(0.55)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                send(.closeNavigationBar)
                            }
                    }
                }
        }
        // 가로 탐색은 필사 화면을 유지한 채 leading 두 열을 본문 위에 겹친다.
        .navigationSplitViewStyle(.prominentDetail)
        .onChange(of: scenePhase) { _, phase in
            // 앱이 비활성/백그라운드로 가면 단일 Canvas 의 미저장분을 저장한다 (§8-5, best-effort).
            // CarveDetailView가 열림 상태와 관계없이 유지되므로, 이 뷰에서 저장을 건다.
            if phase != .active {
                send(.appWillResignActive)
            }
        }
        .onAppear {
            send(.presentFirstRunGuide)
        }
        .allowsHitTesting(store.firstRunGuide == nil)
        .accessibilityHidden(store.firstRunGuide != nil)
        .overlay {
            if let guideStore = store.scope(state: \.firstRunGuide, action: \.firstRunGuide.presented) {
                FirstRunGuideView(store: guideStore)
            }
        }
    }
    
    /// 성경 선택 열. 탐색을 열어도 detail을 대체하지 않으므로 필사 화면은 계속 유지된다.
    private var sideBar: some View {
        VStack(spacing: CarveSpacing.small) {
            Text("새기다")
                .font(CarveTypography.scripture(ResourcesFontFamily.NanumMyeongjo.regular.font(size: 22)))
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("성경 · 장 검색", text: $searchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, CarveSpacing.medium)
                .frame(height: CarveSize.minimumHitTarget)
                .background(CarveColor.fill, in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous))

            Picker("성경 구분", selection: $testament) {
                Text("구약").tag(Testament.old)
                Text("신약").tag(Testament.new)
            }
            .pickerStyle(.segmented)

            ScrollView {
                LazyVStack(spacing: 0) {
                    Text("성경")
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, CarveSpacing.small)

                    ForEach(filteredTitles) { title in
                        bibleTitleButton(title)
                    }
                }
            }
        }
        .padding(.horizontal, CarveSpacing.medium)
        .padding(.top, CarveSpacing.large)
        .safeAreaInset(edge: .bottom) {
            // 광고를 차트 · 설정 버튼과 성경 목록에서 떨어뜨린다 — 버튼 · 목록을 누르다 광고를 누르지 않게 한다(AdMob 오클릭 가이드).
            VStack(spacing: CarveSpacing.large) {
                if store.sidebarAdSlot.occupiesSpace {
                    // 성경 목록 아래 네이티브 광고(시안 K3). 오버레이 열이라 필사 폭에 영향이 없다.
                    // VoiceOver 는 목록 · 버튼 뒤에 읽는다.
                    AdSlotView(store: store.scope(state: \.sidebarAdSlot, action: \.scope.sidebarAdSlotAction))
                        .frame(height: NativeAdMetrics.sidebarHeight)
                        .padding(.top, CarveSpacing.xSmall)
                        .accessibilitySortPriority(-1)
                }
                HStack(spacing: CarveSpacing.xSmall) {
                    Spacer(minLength: 0)
                    // 차트 바로 왼쪽(시안 N3). 목록은 차트와 같이 앱 스택에 올린다.
                    CarveIconButton(.star, accessibilityLabel: "즐겨찾기") {
                        send(.moveToFavorites)
                    }
                    CarveIconButton(.chart, accessibilityLabel: "필사 차트") {
                        send(.moveToChart)
                    }
                    CarveIconButton(.settings, accessibilityLabel: "앱 설정") {
                        send(.moveToSetting)
                    }
                }
            }
            .padding(.horizontal, CarveSpacing.medium)
            .padding(.vertical, CarveSpacing.xSmall)
            .background(CarveColor.surface)
        }
        .background(CarveColor.surface)
        .onAppear {
            send(.sidebarAppeared)
        }
    }
    
    /// 선택한 성경의 장 목록. 44pt 버튼을 5열 그리드로 두어 긴 성경도 빠르게 훑는다.
    private var contentList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(CarveSize.minimumHitTarget), spacing: CarveSpacing.xSmall), count: 5),
                    spacing: CarveSpacing.xSmall
                ) {
                    ForEach(1...browsingTitle.lastChapter, id: \.self) { chapter in
                        chapterButton(chapter)
                            .id(chapter)
                    }
                }
                .padding(CarveSpacing.large)
            }
            .onAppear {
                if let chapter = store.selectedChapter {
                    proxy.scrollTo(chapter, anchor: .center)
                }
            }
            .onChange(of: store.selectedChapter) { _, chapter in
                // 성경을 고르면 필사 기록을 받은 뒤 정해진 기본 장으로 옮긴다.
                guard let chapter else { return }
                proxy.scrollTo(chapter, anchor: .center)
            }
        }
        // 성경을 고른 직후 필사 기록을 읽는 동안은 선택한 장이 없어 성경 이름만 보인다.
        .navigationTitle(store.selectedChapter.map { "\(browsingTitle.koreanTitle()) \($0)장" } ?? browsingTitle.koreanTitle())
        .background(CarveColor.surface)
    }
    
    /// detail화면의 content와 sheet popup 등 네비게이션 관리.
    @ViewBuilder
    private func detailView() -> some View {
        CarveDetailView(store: store.scope(state: \.carveDetailState,
                                           action: \.scope.carveDetailAction))
        .fullScreenCover(
            item: $store.scope(
                state: \.detailNavigation?.drewLog,
                action: \.view.detailNavigation.drewLog)
        ) { store in
            DrewLogView(store: store)
                .toolbar(.visible, for: .navigationBar)
        }
    }

    private var filteredTitles: [BibleTitle] {
        let titles = testament == .old ? Array(BibleTitle.allCases[0..<39]) : Array(BibleTitle.allCases[39..<66])
        guard !searchText.isEmpty else { return titles }
        return titles.filter { $0.koreanTitle().localizedCaseInsensitiveContains(searchText) }
    }

    /// 장 목록이 보여 줄 성경. 성경 열에서 고른 성경이 없으면 현재 성경이다.
    private var browsingTitle: BibleTitle {
        store.selectedTitle ?? store.currentTitle.title
    }

    private func bibleTitleButton(_ title: BibleTitle) -> some View {
        let isSelected = browsingTitle == title
        return Button {
            send(.bibleTitleTapped(title))
        } label: {
            HStack(spacing: CarveSpacing.small) {
                Text(title.koreanTitle())
                    .font(CarveTypography.body)
                Spacer(minLength: 0)
                if isSelected {
                    // 선택한 성경의 마지막 장을 보여준다. 선택한 장은 장 목록에서 강조한다.
                    Text("\(title.lastChapter)장")
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.accent)
                }
            }
            .padding(.horizontal, CarveSpacing.small)
            .frame(height: CarveSize.minimumHitTarget)
            .foregroundStyle(CarveColor.ink)
            .background(isSelected ? CarveColor.selected : .clear, in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "\(title.koreanTitle()), 총 \(title.lastChapter)장" : title.koreanTitle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func chapterButton(_ chapter: Int) -> some View {
        let isSelected = store.selectedChapter == chapter
        let isDrawn = store.drawnChapters[browsingTitle]?.contains(chapter) == true
        // 필사 기록이 있는 장은 선택 배경에 강조 글자로 칠한다. 선택한 장(강조 배경)과 구분되고,
        // accent 글자 / selected 배경 대비가 라이트 5.32:1 · 다크 4.58:1 이다(ui-design-direction 3-1).
        let foreground = isSelected ? CarveColor.canvas : (isDrawn ? CarveColor.accent : CarveColor.ink)
        let background = isSelected ? CarveColor.accent : (isDrawn ? CarveColor.selected : CarveColor.fill)
        return Button {
            // selectedChapter 는 목록의 강조만 나타낸다. 도메인 이동 액션으로 보내야
            // 장 상태·detail 전환·본문 로딩이 한 흐름으로 처리된다.
            send(.chapterTapped(BibleChapter(title: browsingTitle, chapter: chapter)))
        } label: {
            Text(chapter.description)
                .font(CarveTypography.body)
                .frame(width: CarveSize.minimumHitTarget, height: CarveSize.minimumHitTarget)
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chapter)장")
        .accessibilityValue(isDrawn ? "필사 기록 있음" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private enum Testament: Hashable {
    case old
    case new
}

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        CarveNavigationFeature()
    }
    
    CarveNavigationView(store: store)
}
