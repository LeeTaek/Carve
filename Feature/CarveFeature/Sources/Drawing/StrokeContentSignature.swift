//
//  StrokeContentSignature.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics
import CryptoKit
import Foundation
import PencilKit
import UIKit

/// 저장 내용이 변경됐는지 판단하는 키 — **dirty 판정용** (설계 §7-2, §8-2).
///
/// `StrokeIdentityKey` 와 정반대로 `mask` / `path` / `transform` / `ink` 를 **포함**한다.
/// bitmap 지우개는 identity 를 바꾸지 않으므로, dirty 를 identity 로 판정하면
/// "owner 승계는 성공했지만 지우기가 저장되지 않는" D7 이 재발한다.
///
/// - Note: 부동소수는 **비트 패턴 그대로** 인코딩한다. 자릿수를 반올림하면 서로 다른 두 값이 같은
///         digest 로 뭉개져 변경을 **놓칠** 수 있고, 그것이 곧 D7 이다.
///         반대 방향(같은 내용인데 다른 digest)은 불필요한 저장 한 번으로 끝나므로 안전하다.
struct StrokeContentSignature: Hashable, Sendable {
    /// 승계용 키. content signature 는 identity 를 포함한다.
    let identity: StrokeIdentityKey
    /// control point 전체의 digest.
    let pathDigest: String
    /// `mask` 의 digest. **`mask == nil` 일 때만 nil 이다.**
    ///
    /// - Important: `maskedPathRanges.isEmpty` 로 마스크 유무를 판정하지 않는다 (S1-5).
    ///              `mask == nil` 인 stroke 의 `maskedPathRanges` 는 빈 배열이 아니라 path 전체 구간이다.
    ///              또한 `mask` 는 지워진 영역이 아니라 **남은(가시) 영역**을 나타내는 clip 이다.
    let maskDigest: String?
    /// 로컬 → 캔버스 변환.
    let transform: CGAffineTransform
    /// ink 종류와 색의 digest.
    let inkDigest: String

    /// stroke 에서 signature 를 유도한다.
    /// - Parameter stroke: 대상 stroke.
    init(stroke: PKStroke) {
        identity = StrokeIdentityKey(stroke: stroke)
        pathDigest = Self.pathDigest(of: stroke.path)
        // 마스크 유무는 오직 `mask` 자체로 판정한다 (S1-5).
        maskDigest = stroke.mask.map { Self.maskDigest(of: $0, ranges: stroke.maskedPathRanges) }
        transform = stroke.transform
        inkDigest = Self.inkDigest(of: stroke.ink)
    }

    // MARK: - Hashable

    /// `CGAffineTransform` 의 `Hashable` 준수 여부에 기대지 않고 6개 성분을 직접 해싱한다.
    /// - Parameter hasher: 해셔.
    func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
        hasher.combine(pathDigest)
        hasher.combine(maskDigest)
        hasher.combine(inkDigest)
        for component in Self.components(of: transform) {
            hasher.combine(component.bitPattern)
        }
    }

    /// - Parameters:
    ///   - lhs: 왼쪽 값.
    ///   - rhs: 오른쪽 값.
    /// - Returns: 두 signature 가 같은지 여부.
    static func == (lhs: StrokeContentSignature, rhs: StrokeContentSignature) -> Bool {
        lhs.identity == rhs.identity
            && lhs.pathDigest == rhs.pathDigest
            && lhs.maskDigest == rhs.maskDigest
            && lhs.inkDigest == rhs.inkDigest
            && components(of: lhs.transform) == components(of: rhs.transform)
    }

    // MARK: - digest 계산

    private static func components(of transform: CGAffineTransform) -> [Double] {
        [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].map(Double.init)
    }

    private static func pathDigest(of path: PKStrokePath) -> String {
        var parts: [String] = ["pts=\(path.count)"]
        for point in path {
            parts.append(
                [
                    canonical(point.location.x), canonical(point.location.y),
                    canonical(CGFloat(point.timeOffset)),
                    canonical(point.size.width), canonical(point.size.height),
                    canonical(point.opacity), canonical(point.force),
                    canonical(point.azimuth), canonical(point.altitude)
                ].joined(separator: ",")
            )
        }
        return digest(of: parts.joined(separator: ";"))
    }

    private static func maskDigest(of mask: UIBezierPath, ranges: [ClosedRange<CGFloat>]) -> String {
        var parts: [String] = []
        mask.cgPath.applyWithBlock { element in
            let type = element.pointee.type
            parts.append("t\(type.rawValue)")
            for index in 0..<Self.pointCount(of: type) {
                let point = element.pointee.points[index]
                parts.append("\(canonical(point.x)),\(canonical(point.y))")
            }
        }
        // 마스크가 실제로 가리는 구간까지 포함해 "무엇이 보이는가"를 digest 에 반영한다.
        for range in ranges {
            parts.append("r\(canonical(range.lowerBound))-\(canonical(range.upperBound))")
        }
        return digest(of: parts.joined(separator: ";"))
    }

    private static func pointCount(of type: CGPathElementType) -> Int {
        switch type {
        case .moveToPoint, .addLineToPoint: return 1
        case .addQuadCurveToPoint: return 2
        case .addCurveToPoint: return 3
        case .closeSubpath: return 0
        @unknown default: return 0
        }
    }

    private static func inkDigest(of ink: PKInk) -> String {
        let color = ink.color.cgColor
        let components = (color.components ?? []).map(canonical).joined(separator: ",")
        let space = (color.colorSpace?.name as String?) ?? "unknown"
        return digest(of: "\(ink.inkType.rawValue)|\(space)|\(components)")
    }

    /// 부동소수를 손실 없이, 로케일과 무관하게 인코딩한다.
    private static func canonical(_ value: CGFloat) -> String {
        // -0.0 과 0.0 은 값으로 같으므로 같은 문자열이 되도록 정규화한다.
        let normalized = value == 0 ? Double(0) : Double(value)
        return String(normalized.bitPattern, radix: 16)
    }

    private static func digest(of canonical: String) -> String {
        SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
