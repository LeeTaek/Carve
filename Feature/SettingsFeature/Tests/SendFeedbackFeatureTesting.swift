//
//  SendFeedbackFeatureTesting.swift
//  SettingsFeatureTest
//
//  Created by Codex on 6/9/26.
//

@testable import SettingsFeature
import Testing

import ComposableArchitecture

@MainActor
struct SendFeedbackFeatureTesting {
    // MARK: - 필수 항목 — 다 채울 때까지 보내기 버튼을 흐리게 막는다 (2026-09-29)

    /// 필수 항목을 모두 채운 상태.
    private static var completeState: SendFeedbackFeature.State {
        var state = SendFeedbackFeature.State.initialState
        state.feedbackInfo.title = "오류 제보"
        state.feedbackInfo.body = "- 문의 내용:필사 화면에서 앱이 종료됩니다."
        state.agreeToDefaultNotice = true
        state.agreeToGetDeviceInfo = true
        return state
    }

    @Test("문의 제목이 비어 있으면 보낼 수 없고 제목을 적으라고 안내한다")
    func sendButtonValidationRequiresTitle() {
        var state = Self.completeState
        state.feedbackInfo.title = ""

        #expect(state.missingRequirement == .title)
        #expect(!state.isFormComplete)
        #expect(state.missingRequirement?.hint == "보내려면 제목을 적어 주세요.")
    }

    @Test("기본 문의 본문 템플릿에 내용이 없으면 보낼 수 없고 내용을 적으라고 안내한다")
    func sendButtonValidationRequiresBodyAfterDefaultTemplate() {
        var state = Self.completeState
        state.feedbackInfo.body = "- 문의 내용:"

        #expect(state.missingRequirement == .body)
        #expect(!state.isFormComplete)
    }

    @Test("필수 동의가 하나라도 빠지면 보낼 수 없고 동의를 안내한다")
    func sendButtonValidationRequiresAllAgreements() {
        var state = Self.completeState
        state.agreeToGetDeviceInfo = false

        #expect(state.missingRequirement == .agreements)
        #expect(!state.isFormComplete)
    }

    @Test("처음 연 화면은 제목부터 차례로 안내한다 — 제목 · 내용 · 동의")
    func initialStateAsksForTitleFirst() {
        var state = SendFeedbackFeature.State.initialState
        #expect(state.missingRequirement == .title)

        state.feedbackInfo.title = "개선 제안"
        #expect(state.missingRequirement == .body)

        state.feedbackInfo.body = "- 문의 내용:여백 조정이 필요합니다."
        #expect(state.missingRequirement == .agreements)

        state.agreeToDefaultNotice = true
        state.agreeToGetDeviceInfo = true
        #expect(state.missingRequirement == nil)
        #expect(state.isFormComplete)
    }

    @Test("공백만 적은 제목 · 내용은 채운 것으로 보지 않는다")
    func whitespaceOnlyIsNotFilled() {
        var state = Self.completeState
        state.feedbackInfo.title = "   "
        #expect(state.missingRequirement == .title)

        state = Self.completeState
        state.feedbackInfo.body = "- 문의 내용:  \n "
        #expect(state.missingRequirement == .body)

        state = Self.completeState
        state.feedbackInfo.body = "\n"
        #expect(state.missingRequirement == .body)
    }

    @Test("기본 머리를 지우고 적은 내용도 센다")
    func bodyWithoutTemplateCounts() {
        var state = Self.completeState
        state.feedbackInfo.body = "앱이 종료됩니다."

        #expect(state.isFormComplete)
    }

    @Test("필수 항목이 빠진 채 들어온 누름은 아무것도 보내지 않는다")
    func incompleteTapDoesNothing() async {
        var state = Self.completeState
        state.agreeToDefaultNotice = false
        let store = TestStore(initialState: state) {
            SendFeedbackFeature()
        } withDependencies: {
            $0.mailComposeAvailability = MailComposeAvailabilityClient(canSendMail: { true })
        }

        // 받은 액션이 있으면 TestStore 가 실패한다 — 메일 작성 화면도, 안내도 뜨지 않는다.
        await store.send(.view(.isEnableSendButton))
    }

    @Test("필수 항목을 다 채우고 누르면 보내기로 넘어간다 — 메일 계정이 없으면 안내를 띄운다")
    func completeTapSendsFeedback() async {
        let store = TestStore(initialState: Self.completeState) {
            SendFeedbackFeature()
        } withDependencies: {
            $0.mailComposeAvailability = MailComposeAvailabilityClient(canSendMail: { false })
        }

        await store.send(.view(.isEnableSendButton))
        await store.receive(\.sendFeedback) {
            $0.canSendMail = false
            $0.path = .popup(SendFeedbackFeature.mailUnavailablePopup)
        }
    }

    // MARK: - 메일 계정이 없는 기기 (2026-09-29)

    private static func reduce(
        _ state: inout SendFeedbackFeature.State,
        _ action: SendFeedbackFeature.Action,
        canSendMail: Bool
    ) {
        withDependencies {
            $0.mailComposeAvailability = MailComposeAvailabilityClient(canSendMail: { canSendMail })
        } operation: {
            _ = SendFeedbackFeature().reduce(into: &state, action: action)
        }
    }

    @Test("메일 계정이 없으면 조용히 넘어가지 않고 보낼 수 없다는 안내를 띄운다 — 메일 작성 화면은 열지 않는다")
    func unavailableMailShowsGuidance() {
        var state = SendFeedbackFeature.State.initialState

        Self.reduce(&state, .sendFeedback, canSendMail: false)

        #expect(state.canSendMail == false)
        #expect(state.path?.popup == SendFeedbackFeature.mailUnavailablePopup)
        #expect(state.path?.popup?.title == "메일을 보낼 수 없어요")
        #expect(state.path?.email == nil)
    }

    @Test("메일을 보낼 수 있으면 적은 내용으로 메일 작성 화면을 연다")
    func availableMailOpensComposer() {
        var state = SendFeedbackFeature.State.initialState
        state.feedbackInfo.title = "오류 제보"

        Self.reduce(&state, .sendFeedback, canSendMail: true)

        #expect(state.canSendMail == true)
        #expect(state.path?.email?.mailInfo.title == "오류 제보")
        #expect(state.path?.popup == nil)
    }

    @Test("화면이 뜰 때 메일을 보낼 수 있는지 본다 — 없으면 다 적기 전에 알린다")
    func appearChecksMailAvailability() {
        var state = SendFeedbackFeature.State.initialState
        #expect(state.canSendMail == nil)

        Self.reduce(&state, .view(.onAppear), canSendMail: false)

        #expect(state.canSendMail == false)
    }

    @Test("안내의 확인을 누르면 닫힌다")
    func guidanceClosesOnConfirm() {
        var state = SendFeedbackFeature.State.initialState
        Self.reduce(&state, .sendFeedback, canSendMail: false)

        Self.reduce(&state, .path(.presented(.popup(.view(.confirm)))), canSendMail: false)

        #expect(state.path == nil)
    }
}
