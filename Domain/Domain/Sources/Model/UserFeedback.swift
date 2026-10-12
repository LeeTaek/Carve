//
//  UserFeedback.swift
//  Domain
//
//  Created by 이택성 on 7/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

/// SettingsFeature에서 사용자의 문의/피드백 정보를 전달하기 위한 모델.
public struct UserFeedback: Equatable, Hashable, Sendable {
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
    
    /// 처음 값. 본문은 「- 문의 내용:」 머리(앱 언어)로 시작한다 — 의견 보내기 화면이 이 머리 뒤에 적은 것만 내용으로 센다.
    public static let initialState = Self(
        email: "",
        title: "",
        body: DomainCatalog.string("- 문의 내용:", locale: nil)
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
    
    /// 의견 종류. `rawValue` 는 메일 제목(「[일반 문의] …」)에 쓰는 한국어 그대로다 — 받는 쪽이 이 말로 분류한다.
    /// 화면에는 `localizedName`(앱 언어)을 적는다.
    public enum FeedbackType: String, CaseIterable, Sendable {
        /// 일반적인 문의/질문.
        case inquiry = "일반 문의"
        /// 기능 개선이나 새로운 아이디어 제안 피드백.
        case proposal =  "개선 및 제안"
        /// 기타 피드백.
        case etc = "기타"

        /// 화면에 적는 종류 이름(앱 언어) — ko 「일반 문의」 · en 「General Inquiry」.
        public var localizedName: String { localizedName(locale: nil) }

        /// 종류 이름을 한 언어로 꺼낸다.
        /// - Parameter locale: 언어를 정할 로케일. nil 이면 앱(기기) 언어다.
        public func localizedName(locale: Locale?) -> String {
            switch self {
            case .inquiry: DomainCatalog.string("일반 문의", locale: locale)
            case .proposal: DomainCatalog.string("개선 및 제안", locale: locale)
            case .etc: DomainCatalog.string("기타", locale: locale)
            }
        }
    }
}
