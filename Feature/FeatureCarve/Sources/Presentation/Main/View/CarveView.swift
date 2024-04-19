//
//  CarveView.swift
//  AppManifests
//
//  Created by 이택성 on 1/22/24.
//

import CommonUI
import Domain
import SwiftUI

import ComposableArchitecture

public struct CarveView: View {
    @Perception.Bindable private var store: StoreOf<CarveReducer>
    @State var selectedTitle: BibleTitle?
    @State var selectedChapter: Int?
    
    public init(store: StoreOf<CarveReducer>) {
        self.store = store
        self.selectedTitle = store.currentTitle.title
        self.selectedChapter = store.currentTitle.chapter
    }
    
    public var body: some View {
        WithPerceptionTracking {
            NavigationSplitView(columnVisibility: $store.columnVisibility) {
                sideBar
            } content: {
                contentList
            } detail: {
                VStack {
                    title
                    detailScroll
                }
                .toolbar(.hidden, for: .navigationBar)
                .onAppear {
                    store.send(.view(.onAppear))
                }
            }
            .onChange(of: selectedTitle) { _ in
                store.send(.view(.selectTitle))
            }
            .onChange(of: selectedChapter) { newValue in
                guard let selectedTitle, let newValue else { return }
                store.send(.view(.selectChapter(selectedTitle, newValue)))
            }
            .navigationSplitViewStyle(.automatic)
        }
    }
    
    private var sideBar: some View {
        VStack(alignment: .trailing) {
            List(selection: $selectedTitle) {
                Section(header: Text("구약")) {
                    ForEach(BibleTitle.allCases[0..<39]) { title in
                        NavigationLink(title.koreanTitle(), value: title)
                    }
                }
                Section(header: Text("신약")) {
                    ForEach(BibleTitle.allCases[39..<66]) { title in
                        NavigationLink(title.koreanTitle(), value: title)
                    }
                }
            }
            .listStyle(.inset)
            
            Button {
                store.send(.view(.moveToSetting))
            } label: {
                Image(systemName: "gear")
                    .foregroundStyle(.black)
            }
            .frame(width: 30, height: 30)
            .padding(.trailing, 15)
        }
        .navigationTitle("성경")
    }
    
    private var contentList: some View {
        VStack {
            Text(selectedTitle?.koreanTitle() ?? store.currentTitle.title.koreanTitle())
            List(1..<(store.currentTitle.title.lastChapter ?? 2),
                 id: \.self ,
                 selection: $selectedChapter) { chapter in
                NavigationLink(chapter.description, value: chapter)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
    
    private var title: some View {
        let titleName = store.currentTitle.title.koreanTitle() ?? "창세기"
        return HStack {
            Button(action: { store.send(.view(.titleDidTapped)) }) {
                Text("\(titleName) \(store.state.currentTitle.chapter)장")
                    .font(.system(size: 30))
                    .padding()
            }
            Spacer()
        }
        .isHidden(store.isScrollDown, duration: 3)
    }
    
    private var detailScroll: some View {
        ScrollView {
            LazyVStack(pinnedViews: .sectionHeaders) {
                Section {
                    ForEach(
                        store.scope(state: \.sentenceWithDrawingState,
                                    action: \.scope.sentenceWithDrawingAction)
                    ) { childStore in
                        SentencesWithDrawingView(store: childStore)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10)
                    }
                } header: {
                    // TODO: - ChapterTitleView
                }
            }
        }
        .background {
            CustomGesture { gesture in
                handleTabState(gesture)
            }
        }
    }
    
    private func handleTabState(_ gesture: UIPanGestureRecognizer) {
        let velocityY = gesture.velocity(in: gesture.view).y
        
        if velocityY < 0 {
            if -(velocityY / 5) > 60 && store.isScrollDown == false {
                store.send(.view(.isScrollDown(true)))
            }
        } else {
            if (velocityY / 5) > 40 && store.isScrollDown == true {
                store.send(.view(.isScrollDown(false)))
            }
        }
    }
}

private struct CustomGesture: UIViewRepresentable {
    var onChange: (UIPanGestureRecognizer) -> Void
    private let gestureID = UUID().uuidString
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(onChange: onChange)
    }
    
    func makeUIView(context: Context) -> some UIView {
        return UIView()
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {
        DispatchQueue.main.async {
            if let superView = uiView.superview?.superview,
               !(superView.gestureRecognizers?.contains(where: { $0.name == gestureID}) ?? false) {
                let gesture = UIPanGestureRecognizer(target: context.coordinator,
                                                     action: #selector(context.coordinator.gestureChange(gesture: )))
                gesture.name = gestureID
                gesture.delegate = context.coordinator
                superView.addGestureRecognizer(gesture)
            }
        }
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChange: (UIPanGestureRecognizer) -> Void
        init(onChange: @escaping (UIPanGestureRecognizer) -> Void) {
            self.onChange = onChange
        }
        
        @objc func gestureChange(gesture: UIPanGestureRecognizer) {
            onChange(gesture)
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer)
        -> Bool {
            return true
        }
    }
    
}
