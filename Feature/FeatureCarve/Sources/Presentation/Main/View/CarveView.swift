//
//  CarveView.swift
//  AppManifests
//
//  Created by 이택성 on 1/22/24.
//

import CommonUI
import SwiftUI

import ComposableArchitecture

public struct CarveView: View {
    @Perception.Bindable private var store: StoreOf<CarveReducer>
    
    public init(store: StoreOf<CarveReducer>) {
        self.store = store
    }
    
    public var body: some View {
        WithPerceptionTracking {
            NavigationSplitView(columnVisibility: $store.columnVisibility) {
                Text("list")
            } content: {
                Text("content")
            } detail: {
                VStack {
                    title
                        .isHidden(store.isScrollDown, duration: 3)
                    
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
                .toolbar(.hidden, for: .navigationBar)
                .onAppear {
                    store.send(.view(.onAppear))
                }
            }
            .navigationSplitViewStyle(.automatic)
        }
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
