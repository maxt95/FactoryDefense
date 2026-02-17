import Foundation
import GameContent

enum CanonicalBootstrapContent {
    static let bundle: GameContentBundle? = {
        let loader = ContentLoader()
        for directory in candidateDirectories() {
            if let bundle = try? loader.loadBundle(from: directory) {
                return bundle
            }
        }
        return nil
    }()

    private static func candidateDirectories() -> [URL] {
        var candidates: [URL] = []

        func appendCandidate(_ url: URL) {
            let normalized = url.standardizedFileURL
            guard !candidates.contains(normalized) else { return }
            candidates.append(normalized)
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        appendCandidate(currentDirectory.appendingPathComponent("Content/bootstrap"))

        if let executablePath = CommandLine.arguments.first, !executablePath.isEmpty {
            let executableDirectory = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
            appendCandidate(executableDirectory.appendingPathComponent("Content/bootstrap"))
            appendCandidate(executableDirectory.appendingPathComponent("../Resources/Content/bootstrap"))
            appendCandidate(executableDirectory.appendingPathComponent("../../Content/bootstrap"))
        }

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        appendCandidate(sourceRoot.appendingPathComponent("Content/bootstrap"))

        if let resourceDirectory = Bundle.main.resourceURL {
            appendCandidate(resourceDirectory.appendingPathComponent("Content/bootstrap"))
            appendCandidate(resourceDirectory.appendingPathComponent("bootstrap"))
        }

        return candidates
    }
}
