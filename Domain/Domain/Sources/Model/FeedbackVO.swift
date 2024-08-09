//
//  FeedbackVO.swift
//  Domain
//
//  Created by 이택성 on 7/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

public struct FeedbackVO: Equatable, Hashable {
    public var feedbackType: FeedbackType = .inquiry
    public var email: String
    public var title: String
    public var body: String
    public var attachment: [Data]
    public let feedbackAddress: String = Bundle.main.object(forInfoDictionaryKey: "FeedbackAddress") as! String
    public var deviceInfo: String?
    
    public static var initialState = Self(email: "",
                                          title: "",
                                          body: "- 문의 내용:")
    public init(email: String,
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
        case inquiry = "일반 문의"
        case proposal =  "개선 및 제안"
        case etc = "기타"
    }
}

