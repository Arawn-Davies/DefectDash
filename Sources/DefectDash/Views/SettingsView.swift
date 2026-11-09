import AppKit
import SwiftUI
import DefectDashCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var pat = ""
    @State private var hasStoredToken = false
    @State private var tokenStatus: String?
    @State private var testing = false
    @State private var projectGid = ""
    @State private var sectionGid = ""
    @State private var worktreesRoot = ""
    @State private var matchSystems = ""
    @State private var ourSide = ""
    @State private var theirSide = ""
    @State private var refreshMinutes = Settings.defaultRefreshMinutes
    @State private var bugPrefix = ""
    @State private var statusField = ""
    @State private var awaitingField = ""
    @State private var classificationField = ""
    @State private var sprintField = ""
    @State private var closedFromStatus = BoardConfig.default.closedFromStatus
    @State private var retestStatus = BoardConfig.default.retestStatus
    @State private var relayPattern = ""
    @State private var terminalBundleID = Settings.defaultTerminalBundleID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Asana") {
                    SecureField("Personal access token", text: $pat, prompt: Text(hasStoredToken ? "stored in Keychain (leave blank to keep)" : "paste your token"))
                    HStack {
                        Button(testing ? "Testing…" : "Test") { Task { await test() } }
                            .disabled(testing || (pat.isEmpty && !hasStoredToken))
                        if hasStoredToken {
                            Button("Remove token", role: .destructive) { removeToken() }
                        }
                        if let tokenStatus { Text(tokenStatus).font(.callout).foregroundStyle(.secondary) }
                    }
                    TextField("Section gid (the defects list)", text: $sectionGid)
                    TextField("Project gid (optional)", text: $projectGid)
                }
                Section("Board vocabulary") {
                    TextField("Ticket prefix", text: $bugPrefix, prompt: Text("BUG"))
                    TextField("Status field (options start with a number)", text: $statusField, prompt: Text("Status"))
                    Stepper("Retest status number: \(retestStatus)", value: $retestStatus, in: 0...20)
                    Stepper("Closed from status number: \(closedFromStatus)", value: $closedFromStatus, in: 0...20)
                    TextField("Awaiting field", text: $awaitingField, prompt: Text("Awaiting"))
                    TextField("Awaiting label for your side", text: $ourSide, prompt: Text("e.g. Vendor"))
                    TextField("Awaiting label for the other side", text: $theirSide, prompt: Text("e.g. Client"))
                    TextField("Classification field", text: $classificationField, prompt: Text("Classification"))
                    TextField("Sprint field (suffix match)", text: $sprintField, prompt: Text("Sprint"))
                    TextField("Relayed comment regex (group 1 = author)", text: $relayPattern,
                              prompt: Text("optional, e.g. ^Client comment - (.+?), [^\\n]*\\n"))
                        .font(.system(.body, design: .monospaced))
                }
                Section("Worktrees") {
                    HStack {
                        TextField("Root folder", text: $worktreesRoot)
                        Button("Choose…") { chooseFolder() }
                    }
                    TextField("Systems to match (comma-separated, empty = all)", text: $matchSystems)
                    Picker("Open in Terminal uses", selection: $terminalBundleID) {
                        ForEach(TerminalApp.installed) { app in
                            Text(app.name).tag(app.bundleID)
                        }
                    }
                }
                Section("Refresh") {
                    Stepper("Every \(refreshMinutes) min", value: $refreshMinutes, in: Settings.refreshRange)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 720)
        .onAppear(perform: load)
    }

    private func load() {
        let s = model.settings
        projectGid = s.projectGid
        sectionGid = s.sectionGid
        worktreesRoot = s.worktreesRoot.path
        matchSystems = s.matchSystems.joined(separator: ", ")
        ourSide = s.ourSideLabel
        theirSide = s.theirSideLabel
        refreshMinutes = s.refreshMinutes
        let b = s.board
        bugPrefix = b.bugPrefix
        statusField = b.statusField
        awaitingField = b.awaitingField
        classificationField = b.classificationField
        sprintField = b.sprintField
        closedFromStatus = b.closedFromStatus
        retestStatus = b.retestStatus
        relayPattern = b.relayPattern
        terminalBundleID = TerminalApp.installed.contains { $0.bundleID == s.terminalBundleID }
            ? s.terminalBundleID : Settings.defaultTerminalBundleID
        hasStoredToken = ((try? model.keychain.load()) ?? nil).map { !$0.isEmpty } ?? false
    }

    private func save() {
        let s = model.settings
        s.projectGid = projectGid
        s.sectionGid = sectionGid
        s.worktreesRoot = URL(fileURLWithPath: (worktreesRoot as NSString).expandingTildeInPath, isDirectory: true)
        s.matchSystems = matchSystems.split(separator: ",").map { String($0) }
        s.refreshMinutes = refreshMinutes
        s.terminalBundleID = terminalBundleID
        s.board = BoardConfig(
            bugPrefix: bugPrefix.isEmpty ? BoardConfig.default.bugPrefix : bugPrefix,
            statusField: statusField.isEmpty ? BoardConfig.default.statusField : statusField,
            awaitingField: awaitingField.isEmpty ? BoardConfig.default.awaitingField : awaitingField,
            classificationField: classificationField.isEmpty ? BoardConfig.default.classificationField : classificationField,
            sprintField: sprintField.isEmpty ? BoardConfig.default.sprintField : sprintField,
            awaitingLabels: AwaitingLabels(ours: ourSide, theirs: theirSide),
            closedFromStatus: closedFromStatus,
            retestStatus: retestStatus,
            relayPattern: relayPattern
        )
        let token = pat.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            do {
                try model.keychain.save(token)
            } catch {
                tokenStatus = "\(error)"
                return
            }
        }
        pat = ""
        dismiss()
        model.start()   // first refresh now, timer restarted with the new interval
    }

    private func removeToken() {
        do {
            try model.keychain.delete()
            hasStoredToken = false
            tokenStatus = "Token removed."
        } catch {
            tokenStatus = "\(error)"
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        let token = pat.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = token.isEmpty ? ((try? model.keychain.load()) ?? nil) : token
        guard let candidate, !candidate.isEmpty else {
            tokenStatus = "No token to test."
            return
        }
        do {
            let me = try await AsanaClient(pat: candidate).me()
            tokenStatus = "OK: \(me.name ?? me.gid)"
        } catch AsanaError.unauthorized {
            tokenStatus = "Rejected (401)."
        } catch {
            tokenStatus = "\(error)"
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: (worktreesRoot as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            worktreesRoot = url.path
        }
    }
}
