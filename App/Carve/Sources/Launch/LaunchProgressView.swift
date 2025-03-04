//
//  LaunchProgressView.swift
//  Carve
//
//  Created by 이택성 on 1/31/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI
import Domain

import ComposableArchitecture

struct LaunchProgressView: View {
    @Bindable var store: StoreOf<LaunchProgressReducer>
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white.ignoresSafeArea()
                VStack(spacing: 20) {
                    Image("LaunchScreen")
                        .resizable()
                        .frame(width: 150, height: 150)
                        .position(
                            x: geometry.size.width / 2,
                            y: (geometry.size.height) / 2 * 0.8
                        )
                    
                    switch store.launchState {
                    case .caching:
                        cachingProgressView
                    case .cloudSync:
                        cloudProgressView
                    case .completed:
                        completedLaunchView
                    }
                    
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            store.send(.startSync)
        }
    }
    
    var cachingProgressView: some View {
        VStack {
            ProgressView(value: store.cacheProgress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(.gray)
                .frame(width: 150)
            
            Text("데이터 캐싱 중... \(Int(store.cacheProgress * 100))%")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
    
    var cloudProgressView: some View {
        VStack {
            ProgressView(value: store.cloudProgress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(.gray)
                .frame(width: 150)
            
            Text("iCloud에서 필사 데이터 가져오는 중... \(Int(store.cloudProgress * 100))%")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
    
    
    var completedLaunchView: some View {
        Text("데이터 동기화 중...")
            .font(.subheadline)
            .foregroundColor(.gray)
    }
}
