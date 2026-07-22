import AppKit

enum PasteboardWritePrivacy: Equatable {
    case currentHostOnly
}

@MainActor
protocol PasteboardAccessing: AnyObject {
    func readStringAfterExplicitAction() -> String?

    func writeLocalStringAfterExplicitAction(
        _ value: String,
        privacy: PasteboardWritePrivacy
    ) -> Bool
}

@MainActor
final class ClipboardPolicy {
    private let pasteboard: PasteboardAccessing

    init(pasteboard: PasteboardAccessing) {
        self.pasteboard = pasteboard
    }

    func ordinaryPreviewDidAppear() {}

    func cancel() {}

    func secureInputWasRejected() {}

    func readFromClipboardAfterExplicitAction() -> String? {
        pasteboard.readStringAfterExplicitAction()
    }

    func copyResultAfterExplicitAction(_ result: TransformedText) {
        _ = pasteboard.writeLocalStringAfterExplicitAction(
            result.value,
            privacy: .currentHostOnly
        )
    }

    func copyOriginalAfterExplicitAction(_ source: SourceText) {
        _ = pasteboard.writeLocalStringAfterExplicitAction(
            source.value,
            privacy: .currentHostOnly
        )
    }
}

@MainActor
final class SystemPasteboardClient: PasteboardAccessing {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func readStringAfterExplicitAction() -> String? {
        pasteboard.string(forType: .string)
    }

    func writeLocalStringAfterExplicitAction(
        _ value: String,
        privacy: PasteboardWritePrivacy
    ) -> Bool {
        guard privacy == .currentHostOnly else {
            return false
        }

        pasteboard.prepareForNewContents(with: .currentHostOnly)
        return pasteboard.setString(value, forType: .string)
    }
}
