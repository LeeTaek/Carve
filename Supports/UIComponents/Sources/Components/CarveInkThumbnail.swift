//
//  CarveInkThumbnail.swift
//  UIComponents
//
//  Created by Claude on 9/21/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import PencilKit
import UIKit

/// 저장된 필기 바이트(`PKDrawing`)의 썸네일 — 필기 범위를 비율을 지켜 줄인다(시안 E2).
///
/// **라이트 외관으로 그린다.** 종이 위 필기이고, 다크 외관으로 그리면 PencilKit 이 잉크 색을 바꿔 저장된 색과 달라진다.
/// 바이트를 풀지 못하거나 획이 없으면 nil 이다 — 부르는 쪽이 "미리보기를 만들지 못했어요" 를 대신 보인다.
public enum CarveInkThumbnail {
    public static func image(of data: Data?) -> UIImage? {
        guard let data, let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds.insetBy(dx: -4, dy: -4)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: bounds, scale: 2)
        }
        return image
    }
}
