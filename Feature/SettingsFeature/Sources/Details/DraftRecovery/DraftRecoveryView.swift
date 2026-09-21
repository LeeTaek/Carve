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
                note("읽지 못해 옆으로 옮겨 둔 파일이 \(bucket.unreadableCount)개 있어요 · "
                     + "\(DraftRecoveryCopy.bytesText(bucket.unreadableBytes)). 되살릴 수는 없고 보관만 해요.", emphasized: false)
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

    private func note(_ text: String, emphasized: Bool) -> some View {
        Text(text)
            .font(CarveTypography.caption)
            .foregroundStyle(emphasized ? CarveColor.ink : CarveColor.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 초안 한 줄

    private func itemCard(_ item: DraftRecoveryFeature.Item, comparedWithStore: Bool) -> some View {
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
            }
            Spacer(minLength: 0)
        }
        .padding(CarveSpacing.small)
        .background(CarveColor.surface, in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous))
    }

    /// 지금 그 절이 어떤 상태인지 — 비교 화면이 붙기 전에도 견줄 실마리는 준다.
    private func currentText(of item: DraftRecoveryFeature.Item) -> String? {
        guard let isEmpty = item.currentIsEmpty else { return nil }
        if isEmpty { return "지금 그 절: 필기 없음" }
        guard let updatedAt = item.currentUpdatedAt else { return "지금 그 절: 다른 필기가 있음" }
        return "지금 그 절: 다른 필기가 있음 · \(DraftRecoveryCopy.dateText(updatedAt))"
    }

    @ViewBuilder
    private func preview(of item: DraftRecoveryFeature.Item) -> some View {
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

    private func badge(_ text: String) -> some View {
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
