//
//  PhotoKitLibraryClient.swift
//  Carve
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import ClientInterfaces
import Foundation
import Photos

/// 사진 보관함에 **추가 전용** 권한(`PHAccessLevel.addOnly`)으로 이미지를 넣는다. 보관함은 읽지 않는다.
///
/// 권한을 물을 때의 문구는 Info.plist `NSPhotoLibraryAddUsageDescription`(`Plugins/ProjectDescriptionHelpers/InfoPlist.swift`)이다.
struct PhotoKitLibraryClient: PhotoLibraryClient {
    func addImage(_ imageData: Data) async throws -> PhotoLibraryAddOutcome {
        // 이미 정해진 권한이면 묻지 않고 곧바로 돌려준다.
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .permissionDenied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: imageData, options: nil)
        }
        return .added
    }
}
