//
//  BackupExportView.swift
//  SettingsFeature
//
//  설정 → 필사 백업 → 「백업 만들기」 줄과 그 흐름 시트 — 암호 · 마지막 필기 저장 · 진행 · 저장할 곳 고르기 · 결과
//  (설계 docs/backup-import-design.md §3-1).
//

import CarveToolkit
import ClientInterfaces
import CoreTransferable
import Domain
import SwiftUI
import UniformTypeIdentifiers

import ComposableArchitecture
import UIComponents

@ViewAction(for: BackupExportFeature.self)
public struct BackupExportView: View {
    @Bindable public var store: StoreOf<BackupExportFeature>
    /// 광고 제거를 샀는지 — 줄의 모양만 정한다. 만들기를 시작해도 되는지는 리듀서가 같은 값으로 다시 판정한다.
    @SharedReader(.isAdFree) private var isAdFree: Bool

    public init(store: StoreOf<BackupExportFeature>) {
        self.store = store
    }

    public var body: some View {
        row
            .sheet(isPresented: $store.isFlowPresented.sending(\.view.flowPresentationChanged)) {
                flowSheet
            }
    }

    /// 화면의 「백업 만들기」 줄. 사지 않았으면 만들기 대신 광고 제거 안내다(설계 §3-1 1단계).
    @ViewBuilder
    private var row: some View {
        if isAdFree {
            BackupActionRow(
                title: BackupCopy.exportTitle,
                description: BackupCopy.exportDescription,
                actionTitle: BackupCopy.exportAction,
                role: .primary
            ) {
                send(.createTapped)
            }
        } else {
            BackupActionRow(
                title: BackupCopy.exportTitle,
                description: BackupCopy.purchaseRequired,
                actionTitle: BackupCopy.purchaseAction,
                role: .secondary
            ) {
                send(.removeAdsTapped)
            }
        }
    }

    // MARK: - 흐름 시트

    private var flowSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CarveSpacing.large) {
                    flowContent
                }
                .padding(CarveSpacing.large)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(CarveColor.surface)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(BackupCopy.exportTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 기다리는 중이면 멈추고 닫는다 — 만든 파일이 있으면 지운다.
                    Button(store.isBusy ? BackupCopy.cancelAction : BackupCopy.closeAction) {
                        send(.closeTapped)
                    }
                }
            }
        }
        // 마지막 필기 저장 · 파일 만들기 · 저장할 곳 고르기 중에는 쓸어서 닫지 않는다 — 닫기는 버튼으로만.
        .interactiveDismissDisabled(store.isBusy)
        .fileExporter(
            isPresented: $store.isLocationPickerPresented.sending(\.view.locationPickerPresentationChanged),
            item: store.exportedFile.map { BackupFileItem(url: $0.fileURL) },
            contentTypes: [.carveBackup],
            defaultFilename: store.exportedFile?.suggestedName,
            onCompletion: { result in
                switch result {
                case .success(let url):
                    send(.saveFinished(.saved(fileName: url.lastPathComponent)))
                case .failure(let error):
                    Log.error("필사 백업 — 시스템 저장 창이 저장하지 못했다", "\(error)")
                    send(.saveFinished(.failed))
                }
            },
            onCancellation: {
                send(.saveFinished(.cancelled))
            }
        )
    }

    @ViewBuilder
    private var flowContent: some View {
        switch store.step {
        case .idle:
            EmptyView()
        case .password:
            passwordForm
        case .flushing:
            progressLine(BackupCopy.flushing)
        case .flushBlocked:
            CarveStatusMessage(.failure, message: BackupCopy.flushBlocked, retryTitle: BackupCopy.retryAction) {
                send(.retryTapped)
            }
        case .exporting(let progress):
            exporting(progress)
        case .exportFailed(let failure):
            CarveStatusMessage(.failure, message: BackupCopy.exportFailed(failure), retryTitle: BackupCopy.retryAction) {
                send(.retryTapped)
            }
        case .saving:
            choosingLocation
        case .finished(let outcome):
            finished(outcome)
        }
    }

    /// 암호 두 칸. 시스템 암호 자동 완성(새 암호 제안 · 암호 관리자 저장)은 막지 않는다(설계 §3-1 3단계).
    private var passwordForm: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.medium) {
            Text(BackupCopy.exportScope)
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: CarveSpacing.small) {
                passwordField(BackupCopy.passwordPlaceholder, text: $store.password.sending(\.view.passwordChanged))
                passwordField(
                    BackupCopy.passwordConfirmationPlaceholder,
                    text: $store.passwordConfirmation.sending(\.view.passwordConfirmationChanged)
                )
                if let issue = visiblePasswordIssue {
                    Text(BackupCopy.passwordIssue(issue))
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(BackupCopy.passwordWarning)
                .font(CarveTypography.caption)
                .foregroundStyle(CarveColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            Button(BackupCopy.startAction) {
                send(.startTapped)
            }
            .buttonStyle(.carve(.primary, fillsWidth: true))
            .disabled(store.passwordIssue != nil)
        }
    }

    /// 입력을 시작한 칸의 문제만 보인다 — 처음 열었을 때부터 빨간 글씨를 띄우지 않는다.
    private var visiblePasswordIssue: BackupExportFeature.PasswordIssue? {
        switch store.passwordIssue {
        case .tooShort: store.password.isEmpty ? nil : .tooShort
        case .mismatch: store.passwordConfirmation.isEmpty ? nil : .mismatch
        case nil: nil
        }
    }

    private func passwordField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .textContentType(.newPassword)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(CarveTypography.body)
            .foregroundStyle(CarveColor.ink)
            .padding(.horizontal, CarveSpacing.small)
            .frame(minHeight: CarveSize.minimumHitTarget)
            .background(CarveColor.fill, in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous))
    }

    private func exporting(_ progress: BackupExportFeature.ExportProgress?) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            if let progress, progress.total > 0 {
                ProgressView(value: Double(min(progress.done, progress.total)), total: Double(progress.total))
                    .tint(CarveColor.accent)
            }
            progressLine(BackupCopy.exporting(progress))
        }
    }

    private func progressLine(_ text: String) -> some View {
        HStack(spacing: CarveSpacing.small) {
            ProgressView()
            Text(text)
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// 파일을 다 만들었다 — 시스템 저장 창이 뜬다. 창이 닫혀 있으면 다시 띄울 수 있다.
    private var choosingLocation: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.medium) {
            Text(BackupCopy.chooseLocation)
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button(BackupCopy.chooseLocationAction) {
                send(.chooseLocationTapped)
            }
            .buttonStyle(.carve(.primary))
            .disabled(store.isLocationPickerPresented)
        }
    }

    /// 저장 · 취소 · 실패를 따로 보인다(설계 §3-1 8단계).
    @ViewBuilder
    private func finished(_ outcome: BackupExportFeature.SaveOutcome) -> some View {
        switch outcome {
        case .saved(let fileName, let rows, let drafts):
            VStack(alignment: .leading, spacing: CarveSpacing.small) {
                CarveStatusMessage(.success, message: BackupCopy.saved(rows: rows, drafts: drafts))
                note(BackupCopy.savedFileName(fileName))
                note(BackupCopy.savedProviderNote)
                Button(BackupCopy.closeAction) {
                    send(.closeTapped)
                }
                .buttonStyle(.carve(.secondary))
            }
        case .cancelled:
            VStack(alignment: .leading, spacing: CarveSpacing.small) {
                Text(BackupCopy.saveCancelled)
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                remakeButton
            }
        case .failed:
            VStack(alignment: .leading, spacing: CarveSpacing.small) {
                CarveStatusMessage(.failure, message: BackupCopy.saveFailed)
                remakeButton
            }
        }
    }

    private var remakeButton: some View {
        Button(BackupCopy.remakeAction) {
            send(.remakeTapped)
        }
        .buttonStyle(.carve(.primary))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(CarveTypography.caption)
            .foregroundStyle(CarveColor.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 시스템 저장 창에 넘기는 백업 파일 — 앱 작업 폴더의 파일을 그대로 보낸다(고른 곳으로의 복사는 시스템이 한다).
struct BackupFileItem: Transferable {
    /// 작업 폴더 안의 암호화한 파일.
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .carveBackup) { item in
            SentTransferredFile(item.url)
        }
        // 저장 창이 쓰는 파일 이름. 없으면 SwiftUI 가 NSFileWrapper 의 preferredFilename 에 nil 을 넣어 앱이 죽는다
        // (`fileExporter` 의 `defaultFilename` 은 이 단계에서 쓰이지 않는다 — 2026-10-06 iPadOS 26.2 시뮬레이터 확인).
        .suggestedFileName { $0.url.lastPathComponent }
    }
}

#Preview {
    @Previewable @State var store = Store(initialState: BackupExportFeature.State()) {
        BackupExportFeature()
    }
    BackupExportView(store: store)
        .padding()
}
