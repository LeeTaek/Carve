//
//  DraftRecoveryView.swift
//  SettingsFeature
//
//  설정 → 「남은 필기」 (정책 §12-6 구현 순서 ④, 읽기 전용 단계).
//

import Domain
import SwiftUI

import ComposableArchitecture
import UIComponents

@ViewAction(for: DraftRecoveryFeature.self)
public struct DraftRecoveryView: View {
    @Bindable public var store: StoreOf<DraftRecoveryFeature>

    public init(store: StoreOf<DraftRecoveryFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CarveSpacing.large) {
                Text("남은 필기")
                    .font(CarveTypography.sectionTitle)
                    .foregroundStyle(CarveColor.secondary)

                summary

                CarveDivider()

                content
            }
            .padding(CarveSpacing.large)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CarveColor.surface)
        .onAppear { send(.onAppear) }
    }

    // MARK: - 요약

    /// 이 기기에 무엇이 얼마나 남았는가. **아직 되살릴 수 없다는 것을 먼저 말한다.**
    @ViewBuilder
    private var summary: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            Text("이 기기에 남아 있는 필사 초안이에요. 그중 **화면에 보이지 않는 것**을 여기서 찾아볼 수 있어요.")
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !store.buckets.isEmpty {
                // 전체 개수와 "보이지 않는 것" 을 따로 적는다 — 같은 수로 뭉뚱그리면 보이는 초안까지 사라진 것처럼 읽힌다.
                Text("초안 \(store.totalDraftCount)개 · \(DraftRecoveryCopy.bytesText(store.totalDraftBytes))"
                     + " · 화면에 보이지 않는 것 \(store.hiddenCount)개")
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.totalUnreadableCount > 0 {
                Text("읽지 못해 보관만 하는 파일 \(store.totalUnreadableCount)개 · \(DraftRecoveryCopy.bytesText(store.totalUnreadableBytes))")
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)
            }
            if let result = store.removalResult {
                Text(result)
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.ink)
            }
            if store.needsAttentionCount > 0 {
                Text("그중 \(store.needsAttentionCount)개는 확인이 필요해요.")
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.ink)
            }
            // 할 수 없는 것을 분명히 말한다 — 이 화면은 아직 보기만 한다(③ 과 같은 시기에 되살리기가 붙는다).
            Text("지금은 **보기만** 할 수 있어요. 되살리기는 준비 중이고, 그동안에도 이 파일들은 지워지지 않아요.")
                .font(CarveTypography.caption)
                .foregroundStyle(CarveColor.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 본문

    @ViewBuilder
    private var content: some View {
        if let failure = store.failure {
            CarveStatusMessage(.failure, message: failure) { send(.reload) }
        } else if store.isLoading, store.buckets.isEmpty {
            HStack {
                ProgressView()
                Text("남은 필기를 세는 중이에요")
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.secondary)
            }
        } else if store.buckets.isEmpty {
            CarveEmptyState("이 기기에 남은 필기가 없어요", message: "쓰던 필기가 화면에 다 보이고 있다는 뜻이에요.")
        } else {
            VStack(alignment: .leading, spacing: CarveSpacing.small) {
                ForEach(store.buckets) { bucket in
                    bucketCard(bucket)
                }
                Button("다시 읽기") { send(.reload) }
                    .buttonStyle(.carve(.secondary))
                    .disabled(store.isLoading)
            }
        }
    }

    // MARK: - 묶음

    private func bucketCard(_ bucket: DraftRecoveryFeature.Bucket) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            Button {
                send(.open(bucket.scope))
            } label: {
                HStack(spacing: CarveSpacing.small) {
                    VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
                        Text(bucket.title)
                            .font(CarveTypography.body)
                            .foregroundStyle(CarveColor.ink)
                        Text(bucketDetail(bucket))
                            .font(CarveTypography.caption)
                            .foregroundStyle(CarveColor.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: store.opened == bucket.scope ? "chevron.up" : "chevron.down")
                        .foregroundStyle(CarveColor.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if store.opened == bucket.scope {
                bucketBody(bucket)
            }
        }
        .padding(CarveSpacing.medium)
        .background(CarveColor.Paper.background, in: RoundedRectangle(cornerRadius: CarveRadius.card, style: .continuous))
    }

    private func bucketDetail(_ bucket: DraftRecoveryFeature.Bucket) -> String {
        if bucket.readFailed { return "읽지 못했어요 · 파일은 그대로 있어요" }
        var parts = ["초안 \(bucket.draftCount)개 · \(DraftRecoveryCopy.bytesText(bucket.draftBytes))"]
        if bucket.unreadableCount > 0 { parts.append("읽지 못한 파일 \(bucket.unreadableCount)개") }
        parts.append(bucket.items.isEmpty ? "보이지 않게 남은 것 없음" : "보이지 않게 남은 것 \(bucket.items.count)개")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func bucketBody(_ bucket: DraftRecoveryFeature.Bucket) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            CarveDivider()

            if bucket.readFailed {
                note("이 묶음을 읽지 못했어요. 파일은 그대로 두고 다시 읽어 볼 수 있어요.", emphasized: true)
            } else if !bucket.comparedWithStore {
                // 다른 계정 묶음은 지금 저장소와 견주지 않는다 — 지금 저장소는 그 계정의 내용이 아니다.
                note("이 필기들은 지금 보고 있는 필사와 견주지 않았어요. 그 계정으로 돌아오면 자세히 볼 수 있어요.", emphasized: false)
            }

            if bucket.unreadableCount > 0 {
                unreadableSection(bucket)
            }

            if !bucket.unreadChapters.isEmpty {
                note("이 장들은 대조하지 못했어요 — \(bucket.unreadChapters.joined(separator: ", ")). 파일은 그대로 있어요.", emphasized: true)
            }

            if bucket.items.isEmpty, !bucket.readFailed {
                note(bucket.draftCount == 0
                     ? "남은 초안이 없어요."
                     : "남은 초안은 모두 화면에 보이거나 이미 저장된 것이에요.", emphasized: false)
            } else {
                ForEach(bucket.items) { item in
                    itemCard(item, comparedWithStore: bucket.comparedWithStore)
                }
            }
        }
    }

}

// 읽지 못한 파일 · 초안 한 줄 · 견주기는 확장으로 나눈다 — 한 타입의 몸통이 길어지면 무엇이 무엇을 부르는지 읽기 어렵다.
private extension DraftRecoveryView {
    // MARK: - 읽지 못한 파일

    /// 되살릴 수 없는 파일 — **내보내기와 지우기가 있는 유일한 자리다.** 초안을 지우는 길은 이 화면에 없다(사용자 결정 2026-09-21).
    @ViewBuilder
    func unreadableSection(_ bucket: DraftRecoveryFeature.Bucket) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            note("읽지 못해 옆으로 옮겨 둔 파일이 \(bucket.unreadableCount)개 있어요 · "
                 + "\(DraftRecoveryCopy.bytesText(bucket.unreadableBytes)). 되살릴 수는 없고 보관만 해요.", emphasized: false)
            HStack(spacing: CarveSpacing.small) {
                if !bucket.unreadableFiles.isEmpty {
                    // 지우기 전에 먼저 꺼내 둘 수 있게 내보내기를 앞에 둔다.
                    ShareLink(items: bucket.unreadableFiles) {
                        Text("내보내기")
                            .font(CarveTypography.label)
                            .foregroundStyle(CarveColor.accent)
                    }
                }
                Button("지우기") { send(.askRemoveUnreadable(bucket.scope)) }
                    .font(CarveTypography.label)
                    .foregroundStyle(CarveColor.danger)
                    .buttonStyle(.plain)
            }
            if store.pendingRemoval == bucket.scope {
                removalConfirmation(bucket)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 지우기 확인 — **무엇이 지워지고 무엇이 그대로인지**를 먼저 말한다(C11 문구 규칙).
    func removalConfirmation(_ bucket: DraftRecoveryFeature.Bucket) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            Text("읽지 못한 파일 \(bucket.unreadableCount)개를 지울까요?")
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
            Text("지금 보고 있는 필사와 남은 초안은 그대로예요. 지우는 것은 **읽지 못해 되살릴 수 없는 파일**이에요.")
                .font(CarveTypography.caption)
                .foregroundStyle(CarveColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("지운 파일은 되돌릴 수 없어요. 먼저 내보내 두면 나중에 살펴볼 수 있어요.")
                .font(CarveTypography.caption)
                .foregroundStyle(CarveColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: CarveSpacing.small) {
                Button("지우기") { send(.removeUnreadableConfirmed(bucket.scope)) }
                    .buttonStyle(.carve(.destructive))
                Button("취소") { send(.askRemoveUnreadable(nil)) }
                    .buttonStyle(.carve(.secondary))
            }
        }
        .padding(CarveSpacing.small)
        .background(CarveColor.selected, in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous))
    }

    func note(_ text: String, emphasized: Bool) -> some View {
        Text(text)
            .font(CarveTypography.caption)
            .foregroundStyle(emphasized ? CarveColor.ink : CarveColor.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 초안 한 줄

    @ViewBuilder
    func itemCard(_ item: DraftRecoveryFeature.Item, comparedWithStore: Bool) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            if comparedWithStore {
                // 견줄 수 있는 묶음만 누를 수 있다 — 다른 계정 묶음은 지금 저장소와 견줄 것이 없다.
                Button { send(.compare(item)) } label: { itemSummary(item, comparedWithStore: true) }
                    .buttonStyle(.plain)
                if store.comparison?.itemID == item.id {
                    comparison(item)
                }
            } else {
                itemSummary(item, comparedWithStore: false)
            }
        }
        .padding(CarveSpacing.small)
        .background(CarveColor.surface, in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous))
    }

    func itemSummary(_ item: DraftRecoveryFeature.Item, comparedWithStore: Bool) -> some View {
        HStack(alignment: .top, spacing: CarveSpacing.small) {
            preview(of: item)
            VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
                // 어디의 필기인지와 언제 쓴 것인지를 먼저, 분류는 그다음 줄에 — 좁은 칸에서 자리 이름이 잘리지 않게 한다.
                HStack(spacing: CarveSpacing.xSmall) {
                    Text(item.place)
                        .font(CarveTypography.body)
                        .foregroundStyle(CarveColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                Text(DraftRecoveryCopy.dateText(item.savedAt))
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)
                HStack(spacing: CarveSpacing.xSmall) {
                    badge(DraftRecoveryCopy.reasonTitle(item.reason))
                    if item.injected {
                        // 시험용 주입은 소유 증명이 아니다 — 화면에서도 구분한다.
                        badge("시험 주입")
                    }
                }
                Text(DraftRecoveryCopy.reasonDetail(item.reason))
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.provenance)
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)
                if comparedWithStore, let currentText = currentText(of: item) {
                    Text(currentText)
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.secondary)
                }
                if comparedWithStore {
                    Text(store.comparison?.itemID == item.id ? "견주기 접기" : "지금 필기와 견주어 보기")
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    // MARK: - 견주기

    /// 지금 필기와 보관된 것을 나란히. **바꾸지 않는다** — 고르기는 ③ 과 같은 시기에 붙는다.
    @ViewBuilder
    func comparison(_ item: DraftRecoveryFeature.Item) -> some View {
        let comparison = store.comparison
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            CarveDivider()
            if comparison?.isLoading == true {
                HStack {
                    ProgressView()
                    Text("지금 필기를 읽는 중이에요")
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.secondary)
                }
            } else if let failure = comparison?.failure {
                note(failure, emphasized: true)
            } else {
                HStack(alignment: .top, spacing: CarveSpacing.small) {
                    side(
                        title: "지금 필기",
                        ink: comparison?.currentInk,
                        emptyText: "필기 없음",
                        detail: comparison?.currentUpdatedAt.map(DraftRecoveryCopy.dateText) ?? "바뀐 때를 모름"
                    )
                    side(
                        title: "보관된 것",
                        ink: item.ink,
                        emptyText: "비운 절",
                        detail: DraftRecoveryCopy.dateText(item.savedAt)
                    )
                }
                note("견주어 보기만 해요. 되살리기는 준비 중이고, 고를 때까지 어느 쪽도 바뀌지 않아요.", emphasized: false)
            }
        }
    }

    func side(title: String, ink: Data?, emptyText: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
            Text(title)
                .font(CarveTypography.caption)
                .foregroundStyle(CarveColor.ink)
            Group {
                if let image = CarveInkThumbnail.image(of: ink) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text(ink == nil ? emptyText : "미리보기 없음")
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72)
            .background(CarveColor.Paper.background, in: RoundedRectangle(cornerRadius: CarveRadius.inner, style: .continuous))
            Text(detail)
                .font(CarveTypography.caption)
                .foregroundStyle(CarveColor.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 지금 그 절이 어떤 상태인지 — 비교 화면이 붙기 전에도 견줄 실마리는 준다.
    func currentText(of item: DraftRecoveryFeature.Item) -> String? {
        guard let isEmpty = item.currentIsEmpty else { return nil }
        if isEmpty { return "지금 그 절: 필기 없음" }
        guard let updatedAt = item.currentUpdatedAt else { return "지금 그 절: 다른 필기가 있음" }
        return "지금 그 절: 다른 필기가 있음 · \(DraftRecoveryCopy.dateText(updatedAt))"
    }

    @ViewBuilder
    func preview(of item: DraftRecoveryFeature.Item) -> some View {
        Group {
            if let image = CarveInkThumbnail.image(of: item.ink) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text(item.ink == nil ? "비운 절" : "미리보기 없음")
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 96, height: 56)
        .background(CarveColor.Paper.background, in: RoundedRectangle(cornerRadius: CarveRadius.inner, style: .continuous))
        .accessibilityHidden(true)
    }

    func badge(_ text: String) -> some View {
        Text(text)
            .font(CarveTypography.caption)
            .foregroundStyle(CarveColor.ink)
            .padding(.horizontal, CarveSpacing.xSmall)
            .padding(.vertical, CarveSpacing.xxSmall)
            .background(CarveColor.selected, in: Capsule())
    }
}

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        DraftRecoveryFeature()
    }
    DraftRecoveryView(store: store)
}
