//
//  PencilPalatteView.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/13/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

public struct PencilPalatteView: View {
    @Bindable private var store: StoreOf<PencilPalatteReducer>
    public init(store: StoreOf<PencilPalatteReducer>) {
        self.store = store
    }
    
    public var body: some View {
        HStack {
            Spacer()
            penTypePalatte
            devider
            penLineWidth
            devider
            colorPalatte
            Spacer()
        }
        .frame(height: 30)
        .padding()
    }
    
    private var colorPalatte: some View {
        HStack {
            ForEach(Array(store.palatteColors.enumerated()), id: \.offset) { index, color in
                Circle()
                    .frame(width: 30, height: 30)
                    .foregroundStyle(Color(uiColor: color))
                    .opacity(0.8)
                    .scaleEffect(index == store.selectedColorIndex ? 0.8 : 1)
                    .overlay {
                        Circle()
                            .stroke(lineWidth: 3)
                            .foregroundStyle(index == store.selectedColorIndex ? .white : .clear)
                    }
                    .padding()
                    .onTapGesture {
                        store.send(.setColor(index))
                    }
                    .gesture(
                        longPressGesture(action: .popoverColor)
                    )
            }
            .frame(height: 40)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = CGPoint(x: value.location.x,
                                    y: value.location.y)
                store.send(.setPopoverPoint(point))
            }
        )
        .popover(
            item: $store.scope(state: \.navigation?.colorPalatte,
                               action : \.navigation.colorPalatte),
            attachmentAnchor: .rect(.rect(CGRect(x: store.popoverPoint.x, y: 40, width: 0, height: 0)))
        ) { store in
            ColorPalatteView(store: store)
        }
    }
    
    private var devider: some View {
        Rectangle()
            .frame(width: 1, height: 30)
            .foregroundStyle(.gray)
            .padding(.horizontal, 20)
    }
    
    private var penLineWidth: some View {
        HStack {
            ForEach(Array(store.lineWidths.enumerated()), id: \.offset) { index, width in
                RoundedRectangle(cornerRadius: 20)
                    .frame(width: 40, height: 40)
                    .foregroundStyle(index == store.selectedWidthIndex ? .gray.opacity(0.3) : .clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .frame(width: 40, height: width)
                            .foregroundStyle(.black)
                            .scaleEffect(index == store.selectedWidthIndex ? 0.8 : 1)
                            .opacity(index == store.selectedWidthIndex ? 1 : 0.6)
                    }
                    .padding()
                    .onTapGesture {
                        store.send(.setLineWidth(index))
                    }
                    .gesture(
                        longPressGesture(action: .popoverLineWidth)
                    )
            }
            .frame(height: 40)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = CGPoint(x: value.location.x,
                                    y: value.location.y)
                store.send(.setPopoverPoint(point))
            }
        )
        .popover(
            item: $store.scope(state: \.navigation?.lineWidthPalatte,
                               action : \.navigation.lineWidthPalatte),
            attachmentAnchor: .rect(.rect(CGRect(x: store.popoverPoint.x, y: 40, width: 0, height: 0)))
        ) { store in
            LineWidthPalatteView(store: store)
        }
    }
    
    private var penTypePalatte: some View {
        HStack {
            RoundedRectangle(cornerRadius: 20)
                .frame(width: 40, height: 40)
                .foregroundStyle(store.pencilConfig.pencilType == .pencil ? .gray.opacity(0.3) : .clear)
                .overlay {
                    FeatureCarveAsset.pencilType.swiftUIImage
                        .resizable()
                        .frame(width: 30, height: 30)
                        .scaleEffect(store.pencilConfig.pencilType == .pencil ? 0.8 : 1)
                        .opacity(store.pencilConfig.pencilType == .pencil ? 1 : 0.6)
                }
                .padding()
                .onTapGesture {
                    store.send(.setPencilType(.pencil))
                }
            
            RoundedRectangle(cornerRadius: 20)
                .frame(width: 40, height: 40)
                .foregroundStyle(store.pencilConfig.pencilType == .pen ? .gray.opacity(0.3) : .clear)
                .overlay {
                    FeatureCarveAsset.penType.swiftUIImage
                        .resizable()
                        .frame(width: 30, height: 30)
                        .scaleEffect(store.pencilConfig.pencilType == .pen ? 0.8 : 1)
                        .opacity(store.pencilConfig.pencilType == .pen ? 1 : 0.6)
                }
                .padding()
                .onTapGesture {
                    store.send(.setPencilType(.pen))
                }
            
            RoundedRectangle(cornerRadius: 20)
                .frame(width: 40, height: 40)
                .foregroundStyle(store.pencilConfig.pencilType == .monoline ? .gray.opacity(0.3) : .clear)
                .overlay {
                    FeatureCarveAsset.eraserType.swiftUIImage
                        .resizable()
                        .frame(width: 30, height: 30)
                        .scaleEffect(store.pencilConfig.pencilType == .monoline ? 0.8 : 1)
                        .opacity(store.pencilConfig.pencilType == .monoline ? 1 : 0.6)
                }
                .padding()
                .onTapGesture {
                    store.send(.setPencilType(.monoline))
                }
        }
    }
    
    private func longPressGesture(action: PencilPalatteReducer.Action) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in
                store.send(action)
            }
    }
}
