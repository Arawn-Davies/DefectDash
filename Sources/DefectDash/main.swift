import Foundation
import DefectDashCore

/// `DefectDash --import-pat <path>`: read the token file and store it in the Keychain.
/// The token itself is never printed, in success or failure.
func importPAT(from path: String) -> Int32 {
    let expanded = (path as NSString).expandingTildeInPath
    let contents: String
    do {
        contents = try String(contentsOfFile: expanded, encoding: .utf8)
    } catch {
        FileHandle.standardError.write(Data("error: cannot read \(expanded): \(error.localizedDescription)\n".utf8))
        return 1
    }
    let token = contents.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else {
        FileHandle.standardError.write(Data("error: \(expanded) is empty\n".utf8))
        return 1
    }
    do {
        try KeychainStore().save(token)
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        return 1
    }
    print("Stored Asana PAT in Keychain.")
    return 0
}

let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--import-pat") {
    guard flag + 1 < arguments.count else {
        FileHandle.standardError.write(Data("usage: DefectDash --import-pat <path>\n".utf8))
        exit(2)
    }
    exit(importPAT(from: arguments[flag + 1]))
}

/// `DefectDash --once`: one headless refresh, group counts on stdout, exit 0 (1 if the refresh raised a banner).
if arguments.contains("--once") {
    Task { @MainActor in
        let model = AppModel()
        await model.refresh()
        if let banner = model.banner { print("banner: \(banner)") }
        print("me: \(model.me?.name ?? "-")")
        for group in Tier.allCases {
            let items = model.items.filter { $0.group == group }
            print("\(group.rawValue). \(group.title): \(items.count)")
            for item in items {
                let bug = item.defect.bugNumber.map { "BUG-\($0)" } ?? "(no bug)"
                let wts = item.worktrees.map(\.relativePath).joined(separator: ", ")
                let tags = (item.flags.labels + (item.needsYou ? ["NEEDS YOU"] : [])).joined(separator: " ")
                print("   \(bug) \(item.defect.title) [\(wts)] \(tags)")
            }
        }
        print("other worktrees: \(model.otherWorktrees.count)")
        for (phase, seconds) in model.lastTimings {
            print(String(format: "timing %@: %.1fs", phase, seconds))
        }
        exit(model.banner == nil ? 0 : 1)
    }
    RunLoop.main.run()
}

DefectDashApp.main()
