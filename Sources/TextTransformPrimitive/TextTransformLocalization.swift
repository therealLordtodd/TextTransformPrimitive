import Foundation

@usableFromInline
enum TextTransformLocalization {
    @usableFromInline
    static var documentEmptyTitle: String {
        string("textTransform.document.emptyTitle", value: "Transform output will appear here")
    }

    @usableFromInline
    static var transformingTitle: String {
        string("textTransform.status.transforming", value: "Transforming…")
    }

    static var completeStatusTitle: String {
        string("textTransform.status.complete", value: "Complete")
    }

    static var errorStatusTitle: String {
        string("textTransform.status.error", value: "Error")
    }

    @usableFromInline
    static var popupTitle: String {
        string("textTransform.popup.title", value: "Transform")
    }

    @usableFromInline
    static var optionLabel: String {
        string("textTransform.option.label", value: "Target")
    }

    @usableFromInline
    static var sourceDisclosureTitle: String {
        string("textTransform.source.disclosureTitle", value: "Original")
    }

    @usableFromInline
    static var copyButtonTitle: String {
        string("textTransform.copyButton.title", value: "Copy Result")
    }

    static func closeButtonAccessibilityLabel(title: String) -> String {
        format("textTransform.closeButton.accessibilityLabel", value: "Close %@", title)
    }

    private static func string(_ key: String, value: String) -> String {
        NSLocalizedString(key, bundle: .module, value: value, comment: "")
    }

    private static func format(_ key: String, value: String, _ arguments: CVarArg...) -> String {
        let localizedFormat = string(key, value: value)
        return String(format: localizedFormat, arguments: arguments)
    }
}
