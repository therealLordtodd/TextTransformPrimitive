import Testing
@testable import TextTransformPrimitive
import SwiftUI

private struct StubTextTransformService: TextTransformService {
    let chunks: [TextTransformChunk]

    func transform(
        text: String,
        context: TextTransformContext
    ) -> AsyncThrowingStream<TextTransformChunk, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

@Test func textTransformControllerAccumulatesStreamedChunks() async {
    let controller = await MainActor.run {
        TextTransformController(
            service: StubTextTransformService(
                chunks: [
                    TextTransformChunk(text: "Hola", isReplacement: true),
                    TextTransformChunk(text: " mundo")
                ]
            )
        )
    }

    await MainActor.run {
        controller.transform(
            text: "Hello world",
            context: TextTransformContext(operationID: "translate", optionID: "es")
        )
    }

    try? await Task.sleep(for: .milliseconds(50))

    let state = await MainActor.run { controller.presentationState }
    #expect(state.isTransforming == false)
    #expect(state.transformedText == "Hola mundo")
    #expect(state.errorDescription == nil)
}

@Test func textTransformDocumentPresentationStateDefaultsToIdle() {
    let state = TextTransformDocumentPresentationState()
    let progress = TextTransformProgress(completedUnitCount: 2, totalUnitCount: 5)

    #expect(state.phase == .idle)
    #expect(state.showsContent == false)
    #expect(progress.label == "2/5")
}

@MainActor
@Test func textTransformViewsPublicSurfaceLoads() {
    let options = [
        TextTransformOption(id: "es", title: "Spanish"),
        TextTransformOption(id: "fr", title: "French"),
    ]

    _ = TextTransformPopupView(
        sourceText: "Hello",
        title: "Translate",
        optionLabel: "Language",
        options: options,
        initialOptionID: "es",
        service: StubTextTransformService(chunks: [
            TextTransformChunk(text: "Hola", isReplacement: true)
        ]),
        buildContext: { optionID in
            TextTransformContext(operationID: "translate", optionID: optionID)
        }
    )

    _ = TextTransformModePopoverButton(
        label: "Translation",
        activeLabel: "Exit Translation",
        isActive: false,
        optionLabel: "Language",
        options: options,
        selectedOptionID: .constant("es"),
        onToggleRequested: {}
    )

    _ = TextTransformDocumentPanel(
        title: "Translated to Spanish",
        presentationState: TextTransformDocumentPresentationState(
            phase: .transforming(
                TextTransformProgress(completedUnitCount: 1, totalUnitCount: 3)
            ),
            showsContent: true
        )
    ) {
        EmptyView()
    }
}
