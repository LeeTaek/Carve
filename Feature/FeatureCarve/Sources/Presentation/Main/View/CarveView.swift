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
                        .isHidden(store.isScrollDown, duration: 3)
                    detailScroll
                        .background {
                            CustomGesture { gesture in
                                handleTabState(gesture)
                            }
                        }
                }
                .toolbar(.hidden, for: .navigationBar)
                .onAppear {
                    store.send(.view(.onAppear))
                }
            }
            .onChange(of: selectedTitle) { newValue in
                guard let newValue else { return }
                store.send(.view(.selectTitle(newValue)))
            }
            .onChange(of: selectedChapter) { newValue in
                guard let newValue else { return }
                store.send(.view(.selectChapter(newValue)))
            }
            .navigationSplitViewStyle(.automatic)
        }
    }
    
    private var sideBar: some View {
        List(BibleTitle.allCases, selection: $selectedTitle) { title in
            NavigationLink(title.koreanTitle(), value: title)
        }
        .navigationTitle("성경")
    }
    
    private var contentList: some View {
        List(1..<store.currentTitle.title.lastChapter,
             id: \.self ,
             selection: $selectedChapter) { chapter in
            NavigationLink(chapter.description, value: chapter)
        }
             .navigationTitle("장")
    }
    
    private var title: some View {
        let titleName = store.currentTitle.title.koreanTitle()
        return HStack {
            Button(action: { store.send(.view(.titleDidTapped)) }) {
                Text("\(titleName) \(store.state.currentTitle.chapter)장")
                    .font(.system(size: 30))
                    .padding()
            }
            Spacer()
        }
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
