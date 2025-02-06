//
//  LaunchProgressView.swift
//  Carve
//
//  Created by 이택성 on 1/31/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI
import Domain

struct LaunchProgressView: View {
    @ObservedObject private var cloudKitContainer = PersistentCloudKitContainer.shared
    
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
                    ProgressView(value: cloudKitContainer.progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.gray)
                        .frame(width: 150)
                    if cloudKitContainer.progress < 1.0 {
                        Text("데이터 가져오는 중... \(Int(cloudKitContainer.progress * 100))%")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    } else {
                        Text("데이터 동기화 중...")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
    }
}
