# TextTransformPrimitive

`TextTransformPrimitive` is the shared text-transform surface for the portfolio. It owns the service protocol, presentation state, and UI model for operations like translate / summarize / simplify / define — any transformation that takes a text selection and produces transformed text, optionally streaming.

Use it when a host surfaces "take this selected text and do X" in a reader or document workflow. Do not build a parallel transform panel.

## What The Package Gives You

- `TextTransformOption` — a selectable transform (id, title, optional subtitle)
- `TextTransformContext` — the input passed to the service (operation ID, option ID, prompt, parameters)
- `TextTransformChunk` — a streaming output unit (text, replacement flag)
- `TextTransformService` — the service protocol the host implements, returning `AsyncThrowingStream<TextTransformChunk, Error>`
- `TextTransformPresentationState` / `TextTransformProgress` / `TextTransformDocumentPhase` — shared state for transform UI
- shared SwiftUI views for transform panels and popovers

## When To Use It

- You are using `ReaderView` from `ReaderKit` and want translate / summarize / etc. available to users
- You are building a custom host that surfaces text transforms against a selection
- You are a cross-app feature needing a consistent transform UX

## When Not To Use It

- You want a freeform AI chat surface (use `ConversationKit`; transforms are single-shot selection operations)
- You want to rewrite the document in place (this primitive presents transforms; committing them to the document is a host concern)
- You want to transform non-text content (audio transcription, image description, etc. — those need their own primitives)

## Install

```swift
dependencies: [
    .package(path: "../TextTransformPrimitive"),
],
targets: [
    .target(
        name: "MyReaderHost",
        dependencies: ["TextTransformPrimitive"]
    )
]
```

This package depends on `ReaderChromeThemePrimitive` for theming.

## Basic Usage

### Implementing the service

The host implements `TextTransformService` and wires it into `ReaderKit` via `ReaderTextTransformConfiguration`. The service returns a streaming async sequence — short transforms like translation emit one chunk and finish; long transforms like LLM summarization emit incrementally.

```swift
import TextTransformPrimitive
import Foundation

struct OpenAITransformService: TextTransformService {
    let client: OpenAIClient

    func transform(
        text: String,
        context: TextTransformContext
    ) -> AsyncThrowingStream<TextTransformChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prompt = buildPrompt(for: context, selection: text)
                    for try await token in try await client.completionStream(prompt: prompt) {
                        continuation.yield(
                            TextTransformChunk(text: token, isReplacement: false)
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

### Wiring into `ReaderKit`

See the reader-stack integration guide for the full `ReaderTextTransformConfiguration` wiring, but the shape is:

```swift
let transform = ReaderTextTransformConfiguration(
    options: [
        TextTransformOption(id: "translate", title: "Translate"),
        TextTransformOption(id: "summarize", title: "Summarize"),
        TextTransformOption(id: "simplify", title: "Simplify")
    ],
    initialOptionID: "translate",
    service: OpenAITransformService(client: openAIClient),
    buildContext: { optionID in
        TextTransformContext(
            operationID: "host-transform",
            optionID: optionID
        )
    }
)

ReaderView(
    standardFile: fileURL,
    textTransformConfiguration: transform
)
```

## The Streaming Contract

`TextTransformService.transform(text:context:)` returns an `AsyncThrowingStream<TextTransformChunk, Error>`. This is deliberate:

- **Short transforms** emit one `TextTransformChunk` and terminate.
- **Streaming transforms** (LLMs) emit partial results and finish when the response is complete.
- **Cancellation** happens via stream termination — hosts do not need a separate cancellation protocol.
- **Errors** terminate the stream with a thrown error.
- **Replacement semantics** — `isReplacement: true` means "replace previously-emitted text"; `false` means "append." Use `true` for corrections (e.g., translation provider revising earlier tokens) and `false` for additive streaming (common for LLMs).

Non-streaming services should emit one chunk with `isReplacement: true` and terminate. That is three lines of code and gives the consumer a consistent shape.

## Integration Guide

This package is one of the shared reader primitives. For how text transform integrates with `ReaderKit`, selection flows, and reader chrome, see:

- `Packages/ReaderKit/docs/reader-stack-integration-guide.md`

## Design Notes

Services are `Sendable` and can cross actor boundaries freely. The primitive runs transform requests on the main actor for UI, but the service itself can compute off the main actor — hop back only when yielding to the continuation.

Transform options are presentation-layer metadata. The service decides what an option means by dispatching on `TextTransformContext.optionID`. This keeps the option list flexible (hosts can ship different option sets per context) without forcing the service to know about UI state.

Prompt text and parameters in `TextTransformContext` are host-defined passthrough fields. The primitive does not inspect them; the service owns their meaning.
