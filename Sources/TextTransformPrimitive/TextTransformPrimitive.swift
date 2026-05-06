import Foundation
import SwiftUI
import ReaderChromeThemePrimitive

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public struct TextTransformOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

public struct TextTransformContext: Sendable, Equatable {
    public var operationID: String
    public var optionID: String?
    public var prompt: String?
    public var parameters: [String: String]

    public init(
        operationID: String,
        optionID: String? = nil,
        prompt: String? = nil,
        parameters: [String: String] = [:]
    ) {
        self.operationID = operationID
        self.optionID = optionID
        self.prompt = prompt
        self.parameters = parameters
    }
}

public struct TextTransformChunk: Sendable, Equatable {
    public var text: String
    public var isReplacement: Bool

    public init(
        text: String,
        isReplacement: Bool = false
    ) {
        self.text = text
        self.isReplacement = isReplacement
    }
}

public protocol TextTransformService: Sendable {
    func transform(
        text: String,
        context: TextTransformContext
    ) -> AsyncThrowingStream<TextTransformChunk, Error>
}

public struct TextTransformPresentationState: Sendable, Equatable {
    public var isTransforming: Bool
    public var transformedText: String
    public var errorDescription: String?

    public init(
        isTransforming: Bool = false,
        transformedText: String = "",
        errorDescription: String? = nil
    ) {
        self.isTransforming = isTransforming
        self.transformedText = transformedText
        self.errorDescription = errorDescription
    }
}

public struct TextTransformProgress: Sendable, Equatable {
    public var completedUnitCount: Int
    public var totalUnitCount: Int

    public var label: String {
        "\(completedUnitCount)/\(totalUnitCount)"
    }

    public init(
        completedUnitCount: Int,
        totalUnitCount: Int
    ) {
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
    }
}

public enum TextTransformDocumentPhase: Sendable, Equatable {
    case idle
    case transforming(TextTransformProgress?)
    case complete(TextTransformProgress?)
    case failed(String)
}

public struct TextTransformDocumentPresentationState: Sendable, Equatable {
    public var phase: TextTransformDocumentPhase
    public var showsContent: Bool

    public init(
        phase: TextTransformDocumentPhase = .idle,
        showsContent: Bool = false
    ) {
        self.phase = phase
        self.showsContent = showsContent
    }
}

@MainActor
public final class TextTransformController: ObservableObject {
    @Published public private(set) var presentationState = TextTransformPresentationState()

    private let service: any TextTransformService
    private var transformTask: Task<Void, Never>?

    public init(service: any TextTransformService) {
        self.service = service
    }

    deinit {
        transformTask?.cancel()
    }

    public func transform(text: String, context: TextTransformContext) {
        transformTask?.cancel()
        presentationState = TextTransformPresentationState(
            isTransforming: true,
            transformedText: "",
            errorDescription: nil
        )

        transformTask = Task { [weak self] in
            guard let self else { return }

            do {
                let stream = service.transform(text: text, context: context)
                var transformedText = ""

                for try await chunk in stream {
                    if Task.isCancelled {
                        return
                    }

                    if chunk.isReplacement {
                        transformedText = chunk.text
                    } else {
                        transformedText += chunk.text
                    }

                    await MainActor.run {
                        self.presentationState = TextTransformPresentationState(
                            isTransforming: true,
                            transformedText: transformedText,
                            errorDescription: nil
                        )
                    }
                }

                await MainActor.run {
                    self.presentationState = TextTransformPresentationState(
                        isTransforming: false,
                        transformedText: transformedText,
                        errorDescription: nil
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.presentationState.isTransforming = false
                }
            } catch {
                await MainActor.run {
                    self.presentationState = TextTransformPresentationState(
                        isTransforming: false,
                        transformedText: "",
                        errorDescription: error.localizedDescription
                    )
                }
            }
        }
    }

    public func cancel() {
        transformTask?.cancel()
        presentationState.isTransforming = false
    }
}

public struct TextTransformDocumentPanel<Content: View>: View {
    public let title: String
    public let metadata: String?
    public let systemImage: String
    public let emptyTitle: String
    public let emptySystemImage: String
    public let loadingTitle: String
    public let backgroundColor: Color
    public let horizontalPadding: CGFloat?
    public let presentationState: TextTransformDocumentPresentationState

    @Environment(\.readerChromeTheme) private var theme

    private let content: Content

    public init(
        title: String,
        metadata: String? = nil,
        systemImage: String = "wand.and.stars",
        emptyTitle: String = TextTransformLocalization.documentEmptyTitle,
        emptySystemImage: String = "wand.and.stars",
        loadingTitle: String = TextTransformLocalization.transformingTitle,
        backgroundColor: Color = .clear,
        horizontalPadding: CGFloat? = nil,
        presentationState: TextTransformDocumentPresentationState,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.metadata = metadata
        self.systemImage = systemImage
        self.emptyTitle = emptyTitle
        self.emptySystemImage = emptySystemImage
        self.loadingTitle = loadingTitle
        self.backgroundColor = backgroundColor
        self.horizontalPadding = horizontalPadding
        self.presentationState = presentationState
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            bodyContent
                .background(backgroundColor)
        }
    }

    private var header: some View {
        HStack(spacing: theme.spacing.small) {
            Image(systemName: systemImage)
                .font(theme.typography.callout)
                .foregroundStyle(theme.colors.secondaryText)

            Text(verbatim: title)
                .font(theme.typography.callout)
                .foregroundStyle(theme.colors.secondaryText)

            if let metadata {
                Text(verbatim: metadata)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.tertiaryText)
            }

            Spacer()

            statusView
        }
        .padding(.horizontal, resolvedHorizontalPadding)
        .padding(.vertical, theme.spacing.control)
        .background(backgroundColor)
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch presentationState.phase {
        case .failed(let message):
            errorState(message)
        case .transforming where !presentationState.showsContent:
            loadingState
        default:
            if presentationState.showsContent {
                content
            } else {
                emptyState
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch presentationState.phase {
        case .idle:
            EmptyView()
        case .transforming(let progress):
            HStack(spacing: theme.spacing.compact) {
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.colors.infoTint)

                if let progress {
                    Text(verbatim: progress.label)
                        .font(theme.typography.callout)
                        .monospacedDigit()
                        .foregroundStyle(theme.colors.infoTint)
                } else {
                    Text(verbatim: loadingTitle)
                        .font(theme.typography.callout)
                        .foregroundStyle(theme.colors.infoTint)
                }
            }
        case .complete:
            HStack(spacing: theme.spacing.xSmall) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.colors.infoTint)
                    .font(theme.typography.callout)

                Text(verbatim: TextTransformLocalization.completeStatusTitle)
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.colors.infoTint)
            }
        case .failed:
            HStack(spacing: theme.spacing.xSmall) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.colors.warningTint)
                    .font(theme.typography.callout)

                Text(verbatim: TextTransformLocalization.errorStatusTitle)
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.colors.secondaryText)
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: theme.spacing.medium) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.colors.infoTint)

            Text(verbatim: loadingTitle)
                .font(theme.typography.callout)
                .foregroundStyle(theme.colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, emptyStateTopPadding)
    }

    private var emptyState: some View {
        VStack(spacing: theme.spacing.medium) {
            Image(systemName: emptySystemImage)
                .font(theme.typography.title3)
                .foregroundStyle(theme.colors.tertiaryText)

            Text(verbatim: emptyTitle)
                .font(theme.typography.callout)
                .foregroundStyle(theme.colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, emptyStateTopPadding)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: theme.spacing.medium) {
            Image(systemName: "exclamationmark.triangle")
                .font(theme.typography.title3)
                .foregroundStyle(theme.colors.warningTint)

            Text(verbatim: message)
                .font(theme.typography.callout)
                .foregroundStyle(theme.colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, theme.spacing.xLarge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, emptyStateTopPadding)
    }

    private var resolvedHorizontalPadding: CGFloat {
        horizontalPadding ?? theme.spacing.large
    }

    private var emptyStateTopPadding: CGFloat {
        theme.spacing.xLarge * theme.metrics.emptyStateTopPaddingMultiplier
    }
}

public struct TextTransformPopupView: View {
    public let sourceText: String
    public let title: String
    public let optionLabel: String
    public let sourceDisclosureTitle: String
    public let systemImage: String
    public let copyButtonTitle: String
    public let options: [TextTransformOption]
    public let buildContext: (String) -> TextTransformContext

    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerChromeTheme) private var theme

    @StateObject private var controller: TextTransformController
    @State private var selectedOptionID: String

    public init(
        sourceText: String,
        title: String = TextTransformLocalization.popupTitle,
        optionLabel: String = TextTransformLocalization.optionLabel,
        sourceDisclosureTitle: String = TextTransformLocalization.sourceDisclosureTitle,
        systemImage: String = "wand.and.stars",
        copyButtonTitle: String = TextTransformLocalization.copyButtonTitle,
        options: [TextTransformOption],
        initialOptionID: String? = nil,
        service: any TextTransformService,
        buildContext: @escaping (String) -> TextTransformContext
    ) {
        self.sourceText = sourceText
        self.title = title
        self.optionLabel = optionLabel
        self.sourceDisclosureTitle = sourceDisclosureTitle
        self.systemImage = systemImage
        self.copyButtonTitle = copyButtonTitle
        self.options = options
        self.buildContext = buildContext
        self._selectedOptionID = State(
            initialValue: initialOptionID ?? options.first?.id ?? ""
        )
        self._controller = StateObject(
            wrappedValue: TextTransformController(service: service)
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            header

            Divider()

            DisclosureGroup {
                Text(verbatim: sourceText)
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text(verbatim: sourceDisclosureTitle)
            }
            .font(theme.typography.caption)
            .foregroundStyle(theme.colors.secondaryText)

            Divider()

            resultContent

            Spacer(minLength: 0)

            if !controller.presentationState.transformedText.isEmpty {
                HStack {
                    Spacer()

                    Button {
                        copyToPasteboard(controller.presentationState.transformedText)
                    } label: {
                        Label {
                            Text(verbatim: copyButtonTitle)
                        } icon: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(theme.spacing.large)
        .frame(
            width: theme.metrics.transformPopupWidth,
            height: theme.metrics.transformPopupHeight
        )
        .task(id: selectedOptionID) {
            guard !selectedOptionID.isEmpty else { return }
            controller.transform(
                text: sourceText,
                context: buildContext(selectedOptionID)
            )
        }
        .onDisappear {
            controller.cancel()
        }
    }

    private var header: some View {
        HStack(spacing: theme.spacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(theme.colors.secondaryText)

            Text(verbatim: title)
                .font(theme.typography.title3)
                .foregroundStyle(theme.colors.primaryText)

            if !options.isEmpty {
                Picker(selection: $selectedOptionID) {
                    ForEach(options) { option in
                        Text(verbatim: option.title).tag(option.id)
                    }
                } label: {
                    Text(verbatim: optionLabel)
                }
                .labelsHidden()
                .frame(maxWidth: theme.metrics.transformOptionPickerMaxWidth)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: Self.closeButtonAccessibilityLabel(title: title)))
        }
    }

    nonisolated static func closeButtonAccessibilityLabel(title: String) -> String {
        TextTransformLocalization.closeButtonAccessibilityLabel(title: title)
    }

    @ViewBuilder
    private var resultContent: some View {
        if controller.presentationState.isTransforming {
            HStack(spacing: theme.spacing.small) {
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.colors.infoTint)
                Text(verbatim: TextTransformLocalization.transformingTitle)
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, theme.spacing.xLarge)
        } else if let errorDescription = controller.presentationState.errorDescription {
            Text(verbatim: errorDescription)
                .font(theme.typography.callout)
                .foregroundStyle(theme.colors.errorTint)
                .textSelection(.enabled)
        } else {
            ScrollView {
                Text(verbatim: controller.presentationState.transformedText)
                    .font(theme.typography.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
}

public struct TextTransformModePopoverButton<AdditionalContent: View>: View {
    public let label: String
    public let activeLabel: String
    public let systemImage: String
    public let activeSystemImage: String
    public let isActive: Bool
    public let optionLabel: String
    public let options: [TextTransformOption]
    @Binding public var selectedOptionID: String
    public let onToggleRequested: () -> Void
    public let onOptionChanged: ((String) -> Void)?

    @Environment(\.readerChromeTheme) private var theme
    @State private var showingPopover = false

    private let showsAdditionalContent: Bool
    private let additionalContent: AnyView

    public init(
        label: String,
        activeLabel: String,
        systemImage: String = "wand.and.stars",
        activeSystemImage: String = "wand.and.stars.inverse",
        isActive: Bool,
        optionLabel: String,
        options: [TextTransformOption],
        selectedOptionID: Binding<String>,
        onToggleRequested: @escaping () -> Void,
        onOptionChanged: ((String) -> Void)? = nil,
        @ViewBuilder additionalContent: @escaping () -> AdditionalContent
    ) {
        self.label = label
        self.activeLabel = activeLabel
        self.systemImage = systemImage
        self.activeSystemImage = activeSystemImage
        self.isActive = isActive
        self.optionLabel = optionLabel
        self.options = options
        self._selectedOptionID = selectedOptionID
        self.onToggleRequested = onToggleRequested
        self.onOptionChanged = onOptionChanged
        self.showsAdditionalContent = true
        self.additionalContent = AnyView(additionalContent())
    }

    public init(
        label: String,
        activeLabel: String,
        systemImage: String = "wand.and.stars",
        activeSystemImage: String = "wand.and.stars.inverse",
        isActive: Bool,
        optionLabel: String,
        options: [TextTransformOption],
        selectedOptionID: Binding<String>,
        onToggleRequested: @escaping () -> Void,
        onOptionChanged: ((String) -> Void)? = nil
    ) where AdditionalContent == EmptyView {
        self.label = label
        self.activeLabel = activeLabel
        self.systemImage = systemImage
        self.activeSystemImage = activeSystemImage
        self.isActive = isActive
        self.optionLabel = optionLabel
        self.options = options
        self._selectedOptionID = selectedOptionID
        self.onToggleRequested = onToggleRequested
        self.onOptionChanged = onOptionChanged
        self.showsAdditionalContent = false
        self.additionalContent = AnyView(EmptyView())
    }

    public var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            Label {
                Text(verbatim: isActive ? activeLabel : label)
            } icon: {
                Image(systemName: isActive ? activeSystemImage : systemImage)
            }
        }
        .foregroundStyle(
            isActive
                ? theme.colors.infoTint
                : theme.colors.primaryText
        )
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: theme.spacing.large) {
                Button {
                    onToggleRequested()
                    showingPopover = false
                } label: {
                    HStack {
                        Image(systemName: isActive ? "xmark" : systemImage)
                        Text(verbatim: isActive ? activeLabel : label)
                    }
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                if !options.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: theme.spacing.xSmall) {
                        Text(verbatim: optionLabel)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.primaryText)

                        Picker(selection: selectedOptionBinding) {
                            ForEach(options) { option in
                                Text(verbatim: option.title).tag(option.id)
                            }
                        } label: {
                            Text(verbatim: optionLabel)
                        }
                        .labelsHidden()
                    }
                }

                if showsAdditionalContent {
                    Divider()
                    additionalContent
                }
            }
            .padding(theme.spacing.large)
            .frame(width: theme.metrics.transformModePopoverWidth)
        }
    }

    private var selectedOptionBinding: Binding<String> {
        Binding(
            get: { selectedOptionID },
            set: { newValue in
                selectedOptionID = newValue
                onOptionChanged?(newValue)
            }
        )
    }
}
