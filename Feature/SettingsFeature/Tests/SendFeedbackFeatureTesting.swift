//
//  SendFeedbackFeatureTesting.swift
//  SettingsFeatureTest
//
//  Created by Codex on 6/9/26.
//

@testable import SettingsFeature
import Testing

struct SendFeedbackFeatureTesting {
    @Test("문의 제목이 비어 있으면 제목 입력 안내 메시지를 설정한다")
    func sendButtonValidationRequiresTitle() {
        var state = SendFeedbackFeature.State.initialState
        state.feedbackInfo.body = "앱이 종료됩니다."
        state.agreeToDefaultNotice = true
        state.agreeToGetDeviceInfo = true

        _ = SendFeedbackFeature().reduce(into: &state, action: .view(.isEnableSendButton))

        #expect(state.popupMessage == "문의 제목을 입력해주세요.")
    }

    @Test("기본 문의 본문 템플릿에 내용이 없으면 본문 입력 안내 메시지를 설정한다")
    func sendButtonValidationRequiresBodyAfterDefaultTemplate() {
        var state = SendFeedbackFeature.State.initialState
        state.feedbackInfo.title = "오류 제보"
        state.feedbackInfo.body = "- 문의 내용:"
        state.agreeToDefaultNotice = true
        state.agreeToGetDeviceInfo = true

        _ = SendFeedbackFeature().reduce(into: &state, action: .view(.isEnableSendButton))

        #expect(state.popupMessage == "문의 내용을 입력해주세요.")
    }

    @Test("필수 동의가 하나라도 빠지면 동의 안내 메시지를 설정한다")
    func sendButtonValidationRequiresAllAgreements() {
        var state = SendFeedbackFeature.State.initialState
        state.feedbackInfo.title = "개선 제안"
        state.feedbackInfo.body = "- 문의 내용:필사 화면 여백 조정이 필요합니다."
        state.agreeToDefaultNotice = true
        state.agreeToGetDeviceInfo = false

        _ = SendFeedbackFeature().reduce(into: &state, action: .view(.isEnableSendButton))

        #expect(state.popupMessage == "필수 동의 항목을 체크해주세요.")
    }
}
