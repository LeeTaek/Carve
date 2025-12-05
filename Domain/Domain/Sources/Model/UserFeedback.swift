//
//  UserFeedback.swift
//  Domain
//
//  Created by 이택성 on 7/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

/// SettingsFeature에서 사용자의 문의/피드백 정보를 전달하기 위한 모델.
public struct UserFeedback: Equatable, Hashable {
    /// 피드백의 유형: 일반 문의, 개선/제안, 기타
    public var feedbackType: FeedbackType = .inquiry
    /// 회신을 받을 사용자의 이메일 주소.
    public var email: String
    /// 피드백의 제목(요약 내용).
    public var title: String
    /// 피드백 상세 내용.
    public var body: String
    /// 스크린샷 등 첨부 파일의 데이터 배열.
    public var attachment: [Data]
    /// 실제로 피드백을 수신할 이메일 주소.
    /// Info.plist의 `FeedbackAddress` 키에서 값을 읽어오며, 없을 경우 빈 문자열을 사용: 내 이메일 주소.
    public let feedbackAddress: String = Bundle.main.object(forInfoDictionaryKey: "FeedbackAddress") as? String ?? ""
    /// 사용자의 기기/OS 정보 등 추가 환경 정보를 문자열로 담는 필드.
    public var deviceInfo: String?
    
    public static var initialState = Self(
        email: "",
        title: "",
        body: "- 문의 내용:"
    )
    
    public init(
        email: String,
        title: String,
        body: String,
        attachment: [Data] = []
    ) {
        self.email = email
        self.title = title
        self.body = body
        self.attachment = attachment
    }
    
    public enum FeedbackType: String, CaseIterable {
        /// 일반적인 문의/질문.
        case inquiry = "일반 문의"
        /// 기능 개선이나 새로운 아이디어 제안 피드백.
        case proposal =  "개선 및 제안"
        /// 기타 피드백.
        case etc = "기타"
    }
}
