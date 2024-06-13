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
    private var store: StoreOf<PencilPalatteReducer>
    public init(store: StoreOf<PencilPalatteReducer>) {
        self.store = store
        self.store.send(.setColor(store.palatteColors[self.store.pencilConfig.color.rawValue]))
    }
    
    public var body: some View {
        HStack {
            colorPalatte
            Spacer()
            penTypePalatte
            Spacer()
        }
        .frame(height: 50)
        .padding()
    }
    
    private var colorPalatte: some View {
        let selectedColor = store.palatteColors[store.pencilConfig.color.rawValue]
        return HStack {
            RoundedRectangle(cornerRadius: 20)
                .frame(width: 100, height: 50)
                .foregroundStyle(Color(uiColor: selectedColor))
            
            HStack {
                ForEach(store.palatteColors) { color in
                    Circle()
                        .frame(width: 40, height: 40)
                        .foregroundStyle(Color(uiColor: color))
                        .opacity(0.8)
                        .scaleEffect(selectedColor == color ? 0.8 : 1)
                        .overlay {
                            Circle()
                                .stroke(lineWidth: 3)
                                .foregroundStyle(selectedColor == color ? .white : .clear)
                        }
                        .onTapGesture {
                            store.send(.setColor(color))
                        }
                }
            }
            .frame(height: 100)
        }
        .padding()
    }
    
    private var penTypePalatte: some View {
        HStack {
            RoundedRectangle(cornerRadius: 20)
                .frame(width: 50, height: 50)
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
                .frame(width: 50, height: 50)
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
                .frame(width: 50, height: 50)
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
}
