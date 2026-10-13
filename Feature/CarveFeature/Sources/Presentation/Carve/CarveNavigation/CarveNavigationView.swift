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
    /// 구약 · 신약이 각자 기억하는 목록의 첫 행. 두 구분의 스크롤을 분리한다.
    @State private var listAnchors: [Testament: BibleTitle] = [:]
    /// 장 목록 ScrollView 의 높이. 선택한 장으로 옮길 때 목록 끝을 넘지 않는 위치를 고르는 데 쓴다.
    @State private var chapterListHeight: CGFloat = 0
    
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
            // 앱 안 로고 — 앱 이름(ko 「새기다」 · en 「Carve」, 영어 현지화 결정 8).
            Text("새기다", bundle: .module)
                .font(CarveTypography.scripture(ResourcesFontFamily.NanumMyeongjo.regular.font(size: 22)))
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField(String(localized: "성경 · 장 검색", bundle: .module), text: $searchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, CarveSpacing.medium)
                .frame(height: CarveSize.minimumHitTarget)
                .background(CarveColor.fill, in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous))

            Picker(selection: $testament) {
                Text("구약", bundle: .module).tag(Testament.old)
                Text("신약", bundle: .module).tag(Testament.new)
            } label: {
                Text("성경 구분", bundle: .module)
            }
            .pickerStyle(.segmented)

            ScrollView {
                LazyVStack(spacing: 0) {
                    Text("성경", bundle: .module)
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, CarveSpacing.small)

                    ForEach(filteredTitles) { title in
                        bibleTitleButton(title)
                    }
                }
                .scrollTargetLayout()
            }
            // 구약 · 신약이 한 ScrollView 를 같이 쓰면 스크롤 위치가 그대로 남아 신약이 구약에서 보던 자리에서 시작한다.
            // 구분마다 목록을 새로 두고(`id`), 그 구분이 기억한 첫 행으로 돌아간다.
            .scrollPosition(id: scrollAnchor)
            .id(testament)
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
                    // 번역본 고르기는 헤더 제목 메뉴로 옮겼다(영어 현지화 결정 19).
                    Spacer(minLength: 0)
                    // 차트 바로 왼쪽(시안 N3). 목록은 차트와 같이 앱 스택에 올린다.
                    CarveIconButton(.star, accessibilityLabel: String(localized: "즐겨찾기", bundle: .module)) {
                        send(.moveToFavorites)
                    }
                    CarveIconButton(.chart, accessibilityLabel: String(localized: "필사 차트", bundle: .module)) {
                        send(.moveToChart)
                    }
                    CarveIconButton(.settings, accessibilityLabel: String(localized: "앱 설정", bundle: .module)) {
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
                    columns: Array(
                        repeating: GridItem(.fixed(CarveSize.minimumHitTarget), spacing: CarveSpacing.xSmall),
                        count: Self.chapterColumnCount
                    ),
                    spacing: CarveSpacing.xSmall
                ) {
                    ForEach(1...browsingTitle.lastChapter, id: \.self) { chapter in
                        chapterButton(chapter)
                            .id(chapter)
                    }
                }
                .padding(CarveSpacing.large)
                .id(Self.chapterGridID)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                // 높이를 알아야 끝을 넘지 않는 위치를 고를 수 있으므로, 처음 높이를 받을 때 선택한 장으로 옮긴다.
                let isFirstLayout = chapterListHeight == 0
                chapterListHeight = height
                if isFirstLayout {
                    scrollToSelectedChapter(proxy)
                }
            }
            .onAppear {
                scrollToSelectedChapter(proxy)
            }
            .onChange(of: store.selectedChapter) { _, _ in
                // 성경을 고르면 필사 기록을 받은 뒤 정해진 기본 장으로 옮긴다.
                scrollToSelectedChapter(proxy)
            }
        }
        // 성경을 고른 직후 필사 기록을 읽는 동안은 선택한 장이 없어 성경 이름만 보인다.
        .navigationTitle(Self.chapterListTitle(browsingTitle, chapter: store.selectedChapter))
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

    /// 선택한 장이 보이도록 장 목록을 옮긴다.
    private func scrollToSelectedChapter(_ proxy: ScrollViewProxy) {
        guard let chapter = store.selectedChapter, chapterListHeight > 0 else { return }
        switch Self.chapterListScroll(to: chapter, lastChapter: browsingTitle.lastChapter, viewportHeight: chapterListHeight) {
        case .top:
            proxy.scrollTo(Self.chapterGridID, anchor: .top)
        case .bottom:
            proxy.scrollTo(Self.chapterGridID, anchor: .bottom)
        case .center(let chapter):
            proxy.scrollTo(chapter, anchor: .center)
        }
    }

    /// 지금 보고 있는 구분의 스크롤 위치. 구분을 바꾸면 그 구분이 기억한 자리로 돌아간다.
    private var scrollAnchor: Binding<BibleTitle?> {
        Binding(
            get: { listAnchors[testament] },
            set: { newValue in
                // 목록이 바뀌는 순간 오는 nil 로 기억을 지우지 않는다.
                guard let newValue else { return }
                listAnchors[testament] = newValue
            }
        )
    }

    private var filteredTitles: [BibleTitle] {
        let titles = testament == .old ? Array(BibleTitle.allCases[0..<39]) : Array(BibleTitle.allCases[39..<66])
        guard !searchText.isEmpty else { return titles }
        return titles.filter { Self.titleMatches($0, searchText: searchText) }
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
                Text(verbatim: title.localizedName)
                    .font(CarveTypography.body)
                Spacer(minLength: 0)
                if isSelected {
                    // 선택한 성경의 마지막 장을 보여준다. 선택한 장은 장 목록에서 강조한다.
                    Text("\(title.lastChapter)장", bundle: .module)
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
        .accessibilityLabel(Self.titleAccessibilityLabel(title, isSelected: isSelected))
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
            // 장 목록은 지금 번역본의 장을 연다 — 번역본은 헤더 제목 메뉴에서 따로 바꾼다.
            send(.chapterTapped(BibleChapter(title: browsingTitle, chapter: chapter, translation: store.currentTitle.translation)))
        } label: {
            Text(chapter.description)
                .font(CarveTypography.body)
                .frame(width: CarveSize.minimumHitTarget, height: CarveSize.minimumHitTarget)
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        // 장 번호만 적힌 버튼이라 권 이름을 함께 읽는다(「창세기 1장」 · 「Genesis 1」).
        .accessibilityLabel(BibleReference(title: browsingTitle, chapter: chapter).text)
        .accessibilityValue(isDrawn ? Text("필사 기록 있음", bundle: .module) : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 장 목록을 선택한 장으로 옮기는 방법.
enum ChapterListScroll: Equatable {
    /// 목록 맨 위. 장이 첫 화면 안에 있거나 목록이 한 화면에 들어온다.
    case top
    /// 목록 맨 아래. 장이 마지막 화면 안에 있다.
    case bottom
    /// 장을 가운데로.
    case center(Int)
}

extension CarveNavigationView {
    /// 역할: 장 목록 열의 제목(「창세기 1장」 · 「Genesis 1」). 성경을 고른 직후 장을 정하기 전에는 권 이름만 적는다.
    /// 입력 · 출력: 보고 있는 권 · 선택한 장(nil 이면 권 이름만) · 로케일(nil 이면 앱 언어) → 제목 문자열.
    /// 부작용: 없음.
    static func chapterListTitle(_ title: BibleTitle, chapter: Int?, locale: Locale? = nil) -> String {
        guard let chapter else { return title.localizedName(locale: locale) }
        return BibleReference(title: title, chapter: chapter).text(locale: locale)
    }

    /// 역할: 권 검색어가 이 권에 맞는가. 앱 언어 이름 · 한국어 이름 · 고정 영문 이름(`englishName`) 중 하나라도 맞으면 맞다 —
    ///   앱 언어와 상관없이 한국어 · 영어 어느 쪽으로 찾아도 나온다.
    /// 입력 · 출력: 권 · 검색어 → 맞으면 true.
    /// 부작용: 없음.
    static func titleMatches(_ title: BibleTitle, searchText: String) -> Bool {
        [title.localizedName, title.localizedName(locale: Locale(identifier: "ko")), title.englishName]
            .contains { $0.localizedCaseInsensitiveContains(searchText) }
    }

    /// 역할: 성경 목록 행의 VoiceOver 이름. 고른 권은 장 수를 함께 읽는다(「창세기, 총 50장」 · 「Genesis, 50 chapters」).
    /// 입력 · 출력: 권 · 고른 권인가 · 로케일(nil 이면 앱 언어) → 이름.
    /// 부작용: 없음.
    static func titleAccessibilityLabel(_ title: BibleTitle, isSelected: Bool, locale: Locale? = nil) -> String {
        let name = title.localizedName(locale: locale)
        guard isSelected else { return name }
        return "\(name), \(CarveFeatureCatalog.string("총 \(title.lastChapter)장", locale: locale))"
    }

    static let chapterColumnCount = 5
    /// 장 그리드 전체의 스크롤 id. 목록 맨 위 · 맨 아래로 옮길 때 쓴다.
    static let chapterGridID = "chapterGrid"

    /// 선택한 장을 가운데로 맞추되, 그러려면 목록 끝을 넘어야 하는 장은 그 끝에 붙인다.
    ///
    /// iPadOS 27.2 는 `scrollTo(_:anchor: .center)` 를 목록 끝에서 멈추지 않는다. 맨 위 장(창세기 1장 등)을 가운데로 맞추면
    /// 목록이 위로 당겨진 채 남아 큰 제목과 장 목록이 함께 아래로 내려앉고, 한 번 스크롤해야 제자리로 돌아온다(26.x 는 끝에서 멈춘다).
    /// 레이아웃 차이(큰 제목 높이 등)를 감안해 끝에서 한 행 안쪽까지는 끝에 붙인다.
    static func chapterListScroll(to chapter: Int, lastChapter: Int, viewportHeight: CGFloat) -> ChapterListScroll {
        let rowPitch = CarveSize.minimumHitTarget + CarveSpacing.xSmall
        let row = CGFloat((chapter - 1) / chapterColumnCount)
        let rowCount = CGFloat((lastChapter + chapterColumnCount - 1) / chapterColumnCount)
        let contentHeight = CarveSpacing.large * 2 + rowCount * rowPitch - CarveSpacing.xSmall
        guard contentHeight > viewportHeight else { return .top }

        let rowCenter = CarveSpacing.large + row * rowPitch + CarveSize.minimumHitTarget / 2
        let centeredOffset = rowCenter - viewportHeight / 2
        if centeredOffset <= rowPitch { return .top }
        if centeredOffset >= contentHeight - viewportHeight - rowPitch { return .bottom }
        return .center(chapter)
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
