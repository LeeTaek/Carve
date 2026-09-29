//
//  DraftRecoveryView.swift
//  SettingsFeature
//
//  설정 → 「확인이 필요한 필기」 (정책 §12-6 구현 순서 ④, 가져오기 2026-09-29).
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
                Text(DraftRecoveryCopy.title)
                    .font(CarveTypography.sectionTitle)
                    .foregroundStyle(CarveColor.secondary)

                summary

                CarveDivider()

                content

                CarveDivider()

                // 보관의 뜻 — iCloud 백업이 아니다.
                note(DraftRecoveryCopy.storageNote, emphasized: false)
            }
            .padding(CarveSpacing.large)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CarveColor.surface)
        .onAppear { send(.onAppear) }
        .onDisappear { send(.onDisappear) }
    }

    // MARK: - 요약

    /// 무엇이 왜 여기 있고, 무엇을 하면 되는가. 지금 넣을 수 없으면 그 까닭을 먼저 말한다.
    @ViewBuilder
    private var summary: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            Text(DraftRecoveryCopy.introduction)
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(DraftRecoveryCopy.guidance)
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let block = store.importBlock, store.pendingCount > 0 {
                note(DraftRecoveryCopy.importBlocked(block), emphasized: true)
            }
            if !store.buckets.isEmpty {
                // 남겨 둔 필기 전체와 확인이 필요한 것을 따로 적는다 — 같은 수로 뭉뚱그리면 자동으로 표시되는 필기까지 확인할 것처럼 읽힌다.
                note(DraftRecoveryCopy.totalLine(draftCount: store.totalDraftCount, draftBytes: store.totalDraftBytes), emphasized: false)
                note(DraftRecoveryCopy.pendingLine(store.pendingCount), emphasized: store.pendingCount > 0)
            }
            if store.archivedCount > 0 {
                note(DraftRecoveryCopy.archivedLine(store.archivedCount), emphasized: false)
            }
            if store.unopenedCount > 0 {
                // 분류하지 않은 수는 "확인이 필요한 필기" 에 섞지 않고 따로 말한다(P0-1).
                note(DraftRecoveryCopy.unopenedLine(store.unopenedCount), emphasized: false)
            }
            if store.totalUnreadableCount > 0 {
                note("읽지 못해 보관만 하는 파일 \(store.totalUnreadableCount)개 · \(DraftRecoveryCopy.bytesText(store.totalUnreadableBytes))",
                     emphasized: false)
            }
            if let message = store.importMessage {
                note(message.text, emphasized: message.needsAttention)
                    .accessibilityIdentifier("draftRecovery.importMessage")
            }
            if let result = store.removalResult {
                note(result, emphasized: true)
            }
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
                Text("남겨 둔 필기를 확인하는 중이에요")
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.secondary)
            }
        } else if store.buckets.isEmpty {
            CarveEmptyState("이 iPad에 남겨 둔 필기가 없어요", message: "쓰던 필기가 모두 현재 필사에 반영돼 있어요.")
        } else {
            VStack(alignment: .leading, spacing: CarveSpacing.small) {
                ForEach(store.buckets) { bucket in
                    bucketCard(bucket)
                }
                Button("다시 읽기") { send(.reload) }
                    .buttonStyle(.carve(.secondary))
                    .disabled(store.isLoading || store.importingItemID != nil)
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
                        Text(DraftRecoveryCopy.bucketDetail(bucket))
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

    @ViewBuilder
    private func bucketBody(_ bucket: DraftRecoveryFeature.Bucket) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            CarveDivider()

            if bucket.readFailed {
                note("이 묶음을 읽지 못했어요. 파일은 그대로 두고 다시 읽어 볼 수 있어요.", emphasized: true)
            } else if !bucket.comparedWithStore {
                // 다른 계정 묶음은 지금 저장소와 견주지 않고 상세도 만들지 않는다 — 수 · 용량만 보인다(P0-1).
                note(DraftRecoveryCopy.notOpenedBucket, emphasized: false)
            } else if bucket.inaccessibleCount > 0 {
                note(DraftRecoveryCopy.otherHintNote(bucket.inaccessibleCount), emphasized: false)
            }

            // 읽지 못한 파일의 내보내기 · 지우기도 대조한 묶음에서만 — 다른 계정의 파일을 이 계정에서 꺼내거나 지우지 않는다(P0-1).
            if bucket.unreadableCount > 0, bucket.comparedWithStore {
                unreadableSection(bucket)
            }

            if !bucket.unreadChapters.isEmpty {
                note("이 장들은 대조하지 못했어요 — \(bucket.unreadChapters.joined(separator: ", ")). 파일은 그대로 있어요.", emphasized: true)
            }

            if bucket.comparedWithStore {
                if bucket.pendingItems.isEmpty {
                    note(bucket.draftCount == 0 ? "남겨 둔 필기가 없어요." : DraftRecoveryCopy.nothingPending, emphasized: false)
                } else {
                    ForEach(bucket.pendingItems) { item in
                        itemCard(item)
                    }
                }
                if !bucket.archivedItems.isEmpty {
                    archivedSection(bucket)
                }
            }
        }
    }

    /// 보관만 하는 예전 필기 — 확인할 필요가 없어 접어 둔다. 펼치면 견주고 넣을 수 있다(사용자 결정 2026-09-29).
    @ViewBuilder
    private func archivedSection(_ bucket: DraftRecoveryFeature.Bucket) -> some View {
        let isOpen = store.archivedOpened.contains(bucket.scope)
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            Button {
                send(.toggleArchived(bucket.scope))
            } label: {
                HStack(spacing: CarveSpacing.xSmall) {
                    Text(DraftRecoveryCopy.archivedLine(bucket.archivedItems.count))
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.secondary)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.secondary)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                ForEach(bucket.archivedItems) { item in
                    itemCard(item)
                }
            }
        }
    }
}

// 읽지 못한 파일 · 필기 한 줄 · 견주기는 확장으로 나눈다 — 한 타입의 몸통이 길어지면 무엇이 무엇을 부르는지 읽기 어렵다.
private extension DraftRecoveryView {
    // MARK: - 읽지 못한 파일

    /// 넣을 수 없는 파일 — **내보내기와 지우기가 있는 유일한 자리다.** 필기를 지우는 길은 이 화면에 없다(사용자 결정 2026-09-21).
    @ViewBuilder
    func unreadableSection(_ bucket: DraftRecoveryFeature.Bucket) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            note("읽지 못해 옆으로 옮겨 둔 파일이 \(bucket.unreadableCount)개 있어요 · "
                 + "\(DraftRecoveryCopy.bytesText(bucket.unreadableBytes)). 넣을 수는 없고 보관만 해요.", emphasized: false)
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
            Text("현재 필사와 남겨 둔 필기는 그대로예요. 지우는 것은 **읽지 못해 넣을 수 없는 파일**이에요.")
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

    // MARK: - 필기 한 줄

    @ViewBuilder
    func itemCard(_ item: DraftRecoveryFeature.Item) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            Button { send(.compare(item)) } label: { itemSummary(item) }
                .buttonStyle(.plain)
                .disabled(store.importingItemID != nil)
            if store.comparison?.itemID == item.id {
                comparison(item)
            }
        }
        .padding(CarveSpacing.small)
        .background(CarveColor.surface, in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous))
    }

    /// 어디의 필기인지 · 언제 쓴 것인지 · **이 필기에 해당하는 까닭만** 보인다(2026-09-29).
    func itemSummary(_ item: DraftRecoveryFeature.Item) -> some View {
        HStack(alignment: .top, spacing: CarveSpacing.small) {
            preview(of: item)
            VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
                // 어디의 필기인지와 언제 쓴 것인지를 먼저, 까닭은 그다음 줄에 — 좁은 칸에서 자리 이름이 잘리지 않게 한다.
                Text(item.place)
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("쓴 때 \(DraftRecoveryCopy.dateText(item.savedAt))")
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
                if let currentText = currentText(of: item) {
                    Text(currentText)
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.secondary)
                }
                Text(store.comparison?.itemID == item.id ? "비교 접기" : "현재 필사와 비교하기")
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.accent)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    /// 지금 그 절이 어떤 상태인지 — 펼치기 전에도 견줄 실마리는 준다.
    func currentText(of item: DraftRecoveryFeature.Item) -> String? {
        guard let isEmpty = item.currentIsEmpty else { return nil }
        if isEmpty { return "현재 그 절: 필기 없음" }
        guard let updatedAt = item.currentUpdatedAt else { return "현재 그 절: 다른 필기가 있음" }
        return "현재 그 절: 다른 필기가 있음 · \(DraftRecoveryCopy.dateText(updatedAt))"
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

// MARK: - 견주기와 넣기

private extension DraftRecoveryView {
    /// 현재 필사와 남겨 둔 필기를 나란히, 그리고 넣으면 무엇이 되는가. **고를 때까지 어느 쪽도 바뀌지 않는다.**
    @ViewBuilder
    func comparison(_ item: DraftRecoveryFeature.Item) -> some View {
        let comparison = store.comparison
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            CarveDivider()
            if comparison?.isLoading == true {
                HStack {
                    ProgressView()
                    Text("현재 필사를 읽는 중이에요")
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.secondary)
                }
            } else if let failure = comparison?.failure {
                decisionArea {
                    note(failure, emphasized: true)
                    laterButton
                }
            } else {
                HStack(alignment: .top, spacing: CarveSpacing.small) {
                    side(
                        title: "현재 필사",
                        ink: comparison?.currentInk,
                        emptyText: "필기 없음",
                        detail: comparison?.currentUpdatedAt.map { "바뀐 때 \(DraftRecoveryCopy.dateText($0))" } ?? "바뀐 때를 모름"
                    )
                    side(
                        title: "남겨 둔 필기",
                        ink: item.ink,
                        emptyText: "비운 절",
                        detail: "쓴 때 \(DraftRecoveryCopy.dateText(item.savedAt))"
                    )
                }
                if let check = comparison?.check {
                    decisionArea { actionContent(item, check: check) }
                } else {
                    decisionArea { laterButton }
                }
            }
        }
    }

    /// 결정하는 자리 — 옅은 바탕으로 묶는다. 버튼 바탕이 항목 카드와 같은 색이라 묶지 않으면 버튼이 드러나지 않는다.
    func decisionArea<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            content()
        }
        .padding(CarveSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CarveColor.selected, in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous))
    }

    /// 판정에 따른 할 일 — 넣기 · 바꾸기 · 이미 반영됨 · 넣을 수 없음. 지웠던 내용이 다시 들어갈 수 있으면 먼저 묻는다.
    @ViewBuilder
    func actionContent(_ item: DraftRecoveryFeature.Item, check: VerseDraftImportCheck) -> some View {
        switch check.action {
        case .alreadyApplied:
            note(DraftRecoveryCopy.alreadyAppliedNote, emphasized: true)
            laterButton
        case .unavailable:
            note(DraftRecoveryCopy.unavailableNote, emphasized: true)
            laterButton
        case .insert, .replace:
            if check.action == .replace {
                note(DraftRecoveryCopy.replaceNote, emphasized: false)
            }
            if let block = store.importBlock {
                note(DraftRecoveryCopy.importBlocked(block), emphasized: true)
                laterButton
            } else if store.importingItemID == item.id {
                HStack {
                    ProgressView()
                    Text("넣는 중이에요")
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.secondary)
                }
            } else if let caution = store.pendingCaution {
                cautionContent(caution, action: check.action)
            } else {
                HStack(spacing: CarveSpacing.small) {
                    if let title = DraftRecoveryCopy.actionTitle(check.action) {
                        Button(title) { send(.importTapped) }
                            .buttonStyle(.carve(.primary))
                            .accessibilityIdentifier("draftRecovery.import")
                    }
                    laterButton
                }
            }
        }
    }

    /// 지웠던 내용이 다시 들어갈 수 있다 — 무엇이 일어나는지 말하고 한 번 더 받는다.
    @ViewBuilder
    func cautionContent(_ caution: VerseDraftImportCheck.Caution, action: VerseDraftImportCheck.Action) -> some View {
        Text(DraftRecoveryCopy.caution(caution))
            .font(CarveTypography.body)
            .foregroundStyle(CarveColor.ink)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: CarveSpacing.small) {
            Button(DraftRecoveryCopy.cautionConfirmTitle(action)) { send(.cautionConfirmed) }
                .buttonStyle(.carve(.primary))
                .accessibilityIdentifier("draftRecovery.cautionConfirm")
            Button("취소") { send(.cautionCancelled) }
                .buttonStyle(.carve(.secondary))
        }
    }

    /// 「나중에 확인하기」 — 견주기를 접는다. 필기는 그대로 남는다.
    var laterButton: some View {
        Button(DraftRecoveryCopy.laterTitle) { send(.closeComparison) }
            .buttonStyle(.carve(.secondary))
            .disabled(store.importingItemID != nil)
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
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96)
            .background(CarveColor.Paper.background, in: RoundedRectangle(cornerRadius: CarveRadius.inner, style: .continuous))
            Text(detail)
                .font(CarveTypography.caption)
                .foregroundStyle(CarveColor.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        DraftRecoveryFeature()
    }
    DraftRecoveryView(store: store)
}
