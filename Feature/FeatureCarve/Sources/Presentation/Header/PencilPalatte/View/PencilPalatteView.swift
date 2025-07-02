//
//  PencilPalatteView.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/13/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import SwiftUI

import ComposableArchitecture

@ViewAction(for: PencilPalatteReducer.self)
public struct PencilPalatteView: View {
    @Bindable public var store: StoreOf<PencilPalatteReducer>
    private let iconSize: CGFloat = 20
    public init(store: StoreOf<PencilPalatteReducer>) {
        self.store = store
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            Spacer()
            penTypePalatte
                .frame(maxWidth: .infinity)

            divider
            penLineWidth
                .frame(maxWidth: .infinity)

            divider
            colorPalatte
                .frame(maxWidth: .infinity)

            divider
            doButtons
                .frame(maxWidth: .infinity)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 20)
        .padding(.bottom, 10)
    }
    
    private var colorPalatte: some View {
        HStack {
            ForEach(Array(store.palatteColors.enumerated()), id: \.offset) { index, color in
                Circle()
                    .frame(width: iconSize, height: iconSize)
                    .foregroundStyle(Color(uiColor: color.color))
                    .opacity(0.8)
                    .scaleEffect(index == store.selectedColorIndex ? 0.8 : 1)
                    .overlay {
                        Circle()
                            .stroke(lineWidth: 3)
                            .foregroundStyle(index == store.selectedColorIndex ? .gray.opacity(0.3) : .clear)
                    }
                    .padding()
                    .onTapGesture {
                        send(.setColor(index))
                    }
                    .gesture(
                        longPressGesture(action: .popoverColor(index))
                    )
            }
            .frame(height: iconSize + 10)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = CGPoint(x: value.location.x,
                                    y: value.location.y)
                send(.setPopoverPoint(point))
            }
        )
        .popover(
            item: $store.scope(state: \.navigation?.colorPalatte,
                               action : \.navigation.colorPalatte),
            attachmentAnchor: .rect(.rect(CGRect(x: store.popoverPoint.x, y: iconSize + 10, width: 0, height: 0)))
        ) { store in
            ColorPalatteView(store: store)
        }
    }
    
    private var divider: some View {
        Rectangle()
            .frame(width: 1, height: iconSize)
            .foregroundStyle(.gray)
            .padding(.horizontal)
    }
    
    private var penLineWidth: some View {
        HStack {
            ForEach(Array(store.lineWidths.enumerated()), id: \.offset) { index, width in
                RoundedRectangle(cornerRadius: 20)
                    .frame(width: iconSize + 10, height: iconSize + 10)
                    .foregroundStyle(index == store.selectedWidthIndex ? .gray.opacity(0.3) : .clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .frame(width: iconSize + 10, height: width)
                            .foregroundStyle(.black)
                            .scaleEffect(index == store.selectedWidthIndex ? 0.8 : 1)
                            .opacity(index == store.selectedWidthIndex ? 1 : 0.6)
                    }
                    .padding()
                    .onTapGesture {
                        send(.setLineWidth(index))
                    }
                    .gesture(
                        longPressGesture(action: .popoverLineWidth(index))
                    )
            }
            .frame(height: iconSize + 10)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = CGPoint(x: value.location.x,
                                    y: value.location.y)
                send(.setPopoverPoint(point))
            }
        )
        .popover(
            item: $store.scope(state: \.navigation?.lineWidthPalatte,
                               action : \.navigation.lineWidthPalatte),
            attachmentAnchor: .rect(.rect(CGRect(x: store.popoverPoint.x, y: iconSize + 10, width: 0, height: 0)))
        ) { store in
            LineWidthPalatteView(store: store)
        }
    }
    
    private var penTypePalatte: some View {
        HStack {
            RoundedRectangle(cornerRadius: 20)
                .frame(width: iconSize + 10, height: iconSize + 10)
                .foregroundStyle(store.pencilConfig.pencilType == .pencil ? .gray.opacity(0.3) : .clear)
                .overlay {
                    FeatureCarveAsset.pencilType.swiftUIImage
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                        .scaleEffect(store.pencilConfig.pencilType == .pencil ? 0.8 : 1)
                        .opacity(store.pencilConfig.pencilType == .pencil ? 1 : 0.6)
                }
                .padding()
                .onTapGesture {
                    send(.setPencilType(.pencil))
                }
            
            RoundedRectangle(cornerRadius: 20)
                .frame(width: iconSize + 10, height: iconSize + 10)
                .foregroundStyle(store.pencilConfig.pencilType == .pen ? .gray.opacity(0.3) : .clear)
                .overlay {
                    FeatureCarveAsset.penType.swiftUIImage
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                        .scaleEffect(store.pencilConfig.pencilType == .pen ? 0.8 : 1)
                        .opacity(store.pencilConfig.pencilType == .pen ? 1 : 0.6)
                }
                .padding()
                .onTapGesture {
                    send(.setPencilType(.pen))
                }
            
            RoundedRectangle(cornerRadius: 20)
                .frame(width: iconSize + 10, height: iconSize + 10)
                .foregroundStyle(store.pencilConfig.pencilType == .marker ? .gray.opacity(0.3) : .clear)
                .overlay {
                    FeatureCarveAsset.pencilHighlighter.swiftUIImage
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                        .scaleEffect(store.pencilConfig.pencilType == .marker ? 0.8 : 1)
                        .opacity(store.pencilConfig.pencilType == .marker ? 1 : 0.6)
                }
                .padding()
                .onTapGesture {
                    send(.setPencilType(.marker))
                    Log.debug("marker")
                }
            
            RoundedRectangle(cornerRadius: 20)
                .frame(width: iconSize + 10, height: iconSize + 10)
                .foregroundStyle(store.pencilConfig.pencilType == .monoline ? .gray.opacity(0.3) : .clear)
                .overlay {
                    FeatureCarveAsset.eraserType.swiftUIImage
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                        .scaleEffect(store.pencilConfig.pencilType == .monoline ? 0.8 : 1)
                        .opacity(store.pencilConfig.pencilType == .monoline ? 1 : 0.6)
                }
                .padding()
                .onTapGesture {
                    send(.setPencilType(.monoline))
                }
        }
    }
    
    private var doButtons: some View {
        HStack {
            Button {
                send(.undo)
            } label: {
                FeatureCarveAsset.undo.swiftUIImage
                    .resizable()
                    .frame(width: iconSize + 10, height: iconSize + 10)
                    .opacity(store.canUndo ? 1 : 0.3)
                    .padding()
            }
            .disabled(!store.canUndo)
            
            Button {
                send(.redo)
            } label: {
                FeatureCarveAsset.redo.swiftUIImage
                    .resizable()
                    .frame(width: iconSize + 10, height: iconSize + 10)
                    .opacity(store.canRedo ? 1 : 0.3)
                    .padding()
            }
            .disabled(!store.canRedo)
        }
    }
    
    private func longPressGesture(action: PencilPalatteReducer.Action) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in
                store.send(action)
            }
    }
}
