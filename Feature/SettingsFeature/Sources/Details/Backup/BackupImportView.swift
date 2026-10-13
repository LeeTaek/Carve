//
//  BackupImportView.swift
//  SettingsFeature
//
//  설정 → 필사 백업 → 「백업 불러오기」 시트 — 멈춘 작업 · 파일 고르기 · 암호 · 검사 · 미리보기 · 적용 진행 · 결과
//  (설계 docs/backup-import-design.md §4-1 · §6-3).
//

import CarveToolkit
import Domain
import SwiftUI
import UniformTypeIdentifiers

import ComposableArchitecture
import UIComponents

@ViewAction(for: BackupImportFeature.self)
public struct BackupImportView: View {
    @Bindable public var store: StoreOf<BackupImportFeature>
    /// 화면 언어 — 앱 안에서 언어를 고르면 시트의 미리 만드는 문구(단계 · 결과 · 버튼)도 바로 따라온다(즉시 전환 단계 3).
    @Environment(\.locale) private var locale

    public init(store: StoreOf<BackupImportFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CarveSpacing.large) {
                    content
                }
                .padding(CarveSpacing.large)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(CarveColor.surface)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(BackupCopy.importTitle(locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 검사 · 적용 중이면 멈추고 닫는다 — 넣은 장은 그대로이고, 멈춘 적용은 다음에 이어서 불러올 수 있다.
                    Button(store.isBusy ? BackupCopy.cancelAction(locale: locale) : BackupCopy.closeAction(locale: locale)) {
                        send(.closeTapped)
                    }
                }
            }
        }
        // 검사 결과를 들고 있거나 기다리는 일이 있으면 쓸어서 닫지 않는다 — 닫기 버튼이 정리하고 내린다.
        .interactiveDismissDisabled(store.blocksInteractiveDismiss)
        .fileImporter(
            isPresented: $store.isFileImporterPresented.sending(\.view.fileImporterPresentationChanged),
            allowedContentTypes: [.carveBackup]
        ) { result in
            switch result {
            case .success(let url):
                send(.fileChosen(url))
            case .failure(let error):
                Log.error("필사 불러오기 — 파일 고르기 창이 파일을 내주지 못했다", "\(error)")
                send(.fileChoiceFailed)
            }
        }
        .onAppear { send(.onAppear) }
    }

    @ViewBuilder
    private var content: some View {
        switch store.step {
        case .loading:
            progressLine(BackupCopy.importLoading(locale: locale))
        case .pendingJob(let job):
            pendingJob(job.value)
        case .chooseFile:
            chooseFile
        case .password(let source):
            passwordForm(source)
        case .inspecting:
            progressLine(BackupCopy.inspecting(locale: locale))
        case .inspectFailed(let failure, let source):
            inspectFailed(failure, source: source)
        case .preview(let inspection):
            preview(inspection.value)
        case .applying(_, let progress):
            applying(progress)
        case .finished(let result):
            finished(result)
        }
    }

    // MARK: - 멈춘 작업 · 파일 · 암호

    /// 끝나지 않은 불러오기 — 같은 계정이면 이어 하기 · 버리기, 아니면 처음부터 · 버리기(설계 §6-3).
    private func pendingJob(_ job: BackupImportJob) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.medium) {
            headline(BackupCopy.pendingJobTitle(job, locale: locale))
            paragraph(BackupCopy.pendingJobProgress(job, locale: locale))
            paragraph(BackupCopy.pendingJobGuidance(job, locale: locale))
            if job.canResume {
                Button(BackupCopy.resumeAction(locale: locale)) {
                    send(.resumeTapped)
                }
                .buttonStyle(.carve(.primary, fillsWidth: true))
            } else {
                Button(BackupCopy.restartAction(locale: locale)) {
                    send(.restartTapped)
                }
                .buttonStyle(.carve(.primary, fillsWidth: true))
            }
            Button(BackupCopy.discardJobAction(locale: locale)) {
                send(.discardJobTapped)
            }
            .buttonStyle(.carve(.destructive))
            note(BackupCopy.discardJobNote(locale: locale))
        }
    }

    private var chooseFile: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.medium) {
            paragraph(BackupCopy.chooseFilePrompt(locale: locale))
            Button(BackupCopy.chooseFileAction(locale: locale)) {
                send(.chooseFileTapped)
            }
            .buttonStyle(.carve(.primary, fillsWidth: true))
        }
    }

    /// 암호 한 칸 — 백업을 만들 때 정한 암호. 시스템 암호 자동 완성은 막지 않는다.
    private func passwordForm(_ source: BackupImportFeature.Source) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.medium) {
            if case .file(let url) = source {
                note(BackupCopy.chosenFile(url.lastPathComponent, locale: locale))
            }
            paragraph(BackupCopy.importPasswordPrompt(source, locale: locale))
            SecureField(BackupCopy.importPasswordPlaceholder(locale: locale), text: $store.password.sending(\.view.passwordChanged))
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { send(.inspectTapped) }
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
                .padding(.horizontal, CarveSpacing.small)
                .frame(minHeight: CarveSize.minimumHitTarget)
                .background(CarveColor.fill, in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous))
            Button(BackupCopy.inspectAction(locale: locale)) {
                send(.inspectTapped)
            }
            .buttonStyle(.carve(.primary, fillsWidth: true))
            .disabled(store.password.isEmpty)
            if case .file = source {
                Button(BackupCopy.chooseOtherFileAction(locale: locale)) {
                    send(.chooseFileTapped)
                }
                .buttonStyle(.carve(.secondary))
            }
        }
    }

    /// 검사하지 못했다 — 저장소를 바꾸기 전의 안내와, 다시 해 볼 길.
    private func inspectFailed(_ failure: BackupImportFeature.ImportFailure, source: BackupImportFeature.Source?) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.medium) {
            CarveStatusMessage(.failure, message: BackupCopy.inspectFailed(failure, locale: locale))
            note(BackupCopy.inspectFailedNote(locale: locale))
            if failure.allowsRetry, source != nil {
                Button(BackupCopy.retryTitle(failure, locale: locale)) {
                    send(.retryTapped)
                }
                .buttonStyle(.carve(.primary))
            }
            if source?.isJob == true {
                Button(BackupCopy.backAction(locale: locale)) {
                    send(.backToPendingJobTapped)
                }
                .buttonStyle(.carve(.secondary))
            } else {
                Button(BackupCopy.chooseOtherFileAction(locale: locale)) {
                    send(.chooseFileTapped)
                }
                .buttonStyle(.carve(.secondary))
            }
        }
    }

    // MARK: - 미리보기

    /// 결정별 수 · 불러오기 안내(원문) · 「불러오기」 또는 미리보기만 하는 까닭(설계 §4-1 6 · 7단계).
    private func preview(_ inspection: BackupInspection) -> some View {
        let preview = inspection.preview
        return VStack(alignment: .leading, spacing: CarveSpacing.medium) {
            if let manifest = inspection.manifest {
                note(BackupCopy.backupSummary(manifest, locale: locale))
            }
            VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
                countRow(BackupCopy.previewNew(locale: locale), preview.new)
                countRow(BackupCopy.previewSame(locale: locale), preview.same)
                countRow(BackupCopy.previewArchived(locale: locale), preview.archived)
                countRow(BackupCopy.previewProtectedCleared(locale: locale), preview.protectedCleared)
                countRow(
                    BackupCopy.previewUnsupported(locale: locale),
                    preview.unsupportedCount,
                    detail: preview.unsupportedCount > 0 ? BackupCopy.unsupportedDetail(preview.unsupported, locale: locale) : nil
                )
            }
            .padding(CarveSpacing.medium)
            .background(CarveColor.fill, in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous))
            if !inspection.doneChapters.isEmpty {
                note(BackupCopy.resumedChapters(inspection.doneChapters.count, locale: locale))
            }
            paragraph(BackupCopy.importGuidance(locale: locale))
            note(BackupCopy.previewNote(locale: locale))
            if inspection.canApply {
                Button(BackupCopy.applyAction(locale: locale)) {
                    send(.applyTapped)
                }
                .buttonStyle(.carve(.primary, fillsWidth: true))
            } else {
                CarveStatusMessage(.failure, message: BackupCopy.previewOnly(inspection.writeBlock, locale: locale))
            }
        }
    }

    /// 결정 하나의 수 — 이름과 수를 한 줄로 읽는다.
    private func countRow(_ title: String, _ value: Int, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: CarveSpacing.small) {
                Text(title)
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: CarveSpacing.small)
                Text(BackupCopy.count(value, locale: locale))
                    .font(CarveTypography.body.monospacedDigit())
                    .foregroundStyle(CarveColor.ink)
            }
            if let detail {
                note(detail)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 적용 · 결과

    private func applying(_ progress: BackupImportFeature.ApplyProgress?) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            if let progress, progress.total > 0 {
                ProgressView(value: Double(min(progress.done, progress.total)), total: Double(progress.total))
                    .tint(CarveColor.accent)
            }
            progressLine(BackupCopy.applying(progress, locale: locale))
        }
    }

    /// 넣은 수 · 건너뛴 수 · 넣지 못한 수와 멈춘 까닭. 넣은 것이 있으면 이 기기 반영과 iCloud 전송이 다르다는 것을 함께 말한다.
    private func finished(_ result: BackupImportFeature.ImportResult) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            CarveStatusMessage(result.isCompleted ? .success : .failure, message: BackupCopy.resultTitle(result, locale: locale))
            if let tally = result.tally {
                paragraph(BackupCopy.insertedLine(tally, locale: locale))
                if tally.skipped > 0 {
                    note(BackupCopy.skippedLine(tally, locale: locale))
                }
                if tally.unsupported > 0 {
                    note(BackupCopy.notInsertedLine(tally.unsupported, locale: locale))
                }
                if tally.inserted > 0 {
                    note(BackupCopy.savedLocally(locale: locale))
                }
            }
            Button(BackupCopy.closeAction(locale: locale)) {
                send(.closeTapped)
            }
            .buttonStyle(.carve(.secondary))
        }
    }

    // MARK: - 글 모양

    private func headline(_ text: String) -> some View {
        Text(text)
            .font(CarveTypography.title)
            .foregroundStyle(CarveColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(CarveTypography.body)
            .foregroundStyle(CarveColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(CarveTypography.caption)
            .foregroundStyle(CarveColor.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
}

#Preview {
    @Previewable @State var store = Store(initialState: BackupImportFeature.State()) {
        BackupImportFeature()
    }
    BackupImportView(store: store)
}
