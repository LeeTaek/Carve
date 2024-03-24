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
    private let store: StoreOf<CarveReducer>
    @ObservedObject private var viewStore: ViewStore<CarveReducer.State, CarveReducer.ViewAction>
    
    public init(store: StoreOf<CarveReducer>) {
        self.store = store
        self.viewStore = ViewStore(self.store, observe: { $0 }, send: { .view($0) })
    }
    
    public var body: some View {
        VStack {
            titleView
                .isHidden(viewStore.isScrollDown)
            
            ScrollView {
                LazyVStack(pinnedViews: .sectionHeaders) {
                    Section {
                        ForEachStore(
                            store.scope(state: \.sentenceWithDrawingState,
                                        action: \.scope.sentenceWithDrawingAction)
                        ) { childStore in
                            return SentencesWithDrawingView(store: childStore)
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
        .onAppear {
            viewStore.send(.onAppear)
        }
    }
    
    private var titleView: some View {
        TitleView(
            store: self.store.scope(
                state: \.titleState,
                action: \.scope.titleAction)
        )
    }
    
    private func handleTabState(_ gesture: UIPanGestureRecognizer) {
        let velocityY = gesture.velocity(in: gesture.view).y
        
        if velocityY < 0 {
            if -(velocityY / 5) > 60 && viewStore.isScrollDown == false {
                viewStore.send(.isScrollDown(true))
            }
        } else {
            if (velocityY / 5) > 40 && viewStore.isScrollDown == true {
                viewStore.send(.isScrollDown(false))
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
