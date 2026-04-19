# TextTransformPrimitive

> Claude Code loads this file automatically at the start of every session.

## Package Purpose

`TextTransformPrimitive` owns the shared text-transform surface for the portfolio. It defines `TextTransformService` (the host-implemented streaming service protocol), the option / context / chunk value types, presentation state, and the transform UI primitives. `ReaderKit` composes this package to surface translate / summarize / simplify / define / other host-defined transforms against a selected range.

**Tech stack:** Swift 6.0 / SwiftUI / Foundation.

## Key Types

- `TextTransformOption` — selectable option (id, title, optional subtitle)
- `TextTransformContext` — input passed to the service (operationID, optionID, prompt, parameters)
- `TextTransformChunk` — streaming output unit (text, isReplacement flag)
- `TextTransformService` — the `Sendable` protocol the host implements
- `TextTransformPresentationState`, `TextTransformProgress`, `TextTransformDocumentPhase` — shared state
- SwiftUI views for panels and popovers

## Dependencies

- `ReaderChromeThemePrimitive` — theme tokens via environment

## Architecture Rules

- **Streaming from day one.** The service protocol returns `AsyncThrowingStream<TextTransformChunk, Error>`. Non-streaming services emit one chunk and terminate. This keeps the primitive LLM-ready without special-casing.
- **Host provides the service.** The primitive ships zero transform implementations. Hosts bring their translation providers, LLM clients, and business-specific transform logic via `TextTransformService` conformance.
- **Options are presentation metadata.** The service dispatches on `TextTransformContext.optionID` — the primitive does not inspect option semantics.
- **Replacement semantics:** `isReplacement: true` means "replace previously emitted text"; `false` means "append."
- **Cancellation via stream termination.** No separate cancellation protocol.

## Primary Documentation

- Host-facing usage + API reference: `/Users/todd/Programming/Packages/TextTransformPrimitive/README.md`
- Portfolio integration guide: `/Users/todd/Programming/Packages/ReaderKit/docs/reader-stack-integration-guide.md`

When answering transform questions, prefer the README first. For the `ReaderTextTransformConfiguration` wiring into `ReaderKit`, go to the integration guide.

## Primitives-First Development

This primitive is the transform surface. Questions before extending:

1. Is the proposed addition a host concern (provider, business logic, custom UX) that should stay in the host?
2. Is it a transform-kind that belongs as a new `TextTransformOption` — or does it need new primitive surface?
3. Does the streaming contract cover it, or is a different protocol shape genuinely needed? Strong bias toward the existing streaming contract.

## GitHub Repository Visibility

- This repository is **private**. Do not change visibility without Todd's explicit request.
