import Foundation

@main
@MainActor
struct AgentTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        aFolderContainsOnlyWhatResolvesInsideIt()
        readOnlyRefusesEverythingThatChangesAFile()
        askingWaitsUntilTheReaderAllowsForTheChat()
        autoEditAllowsEditsThatStayInTheFolder()
        claudeOffersOnlyTheToolsAModeAllows()
        claudeRequestsReadAsWhatTheyWouldDo()
        decisionsSayWhetherTheyAllow()
        deletingAlwaysAsks()
        claudeLaunchesWithItsSessionAndRules()
        claudeSettingsTurnHooksOffAndAsk()
        claudeCarriesTheChatIntoItsFirstTurnOnly()
        claudeAgentFramesDecode()
        claudeHearsEachDecision()
        codexApprovalsReadAsRequests()
        codexTurnsAreSandboxedByMode()
        lookingInsideTheFolderNeedsNoAnswer()
        threadsContinueOnlyWhereTheyStarted()
        instructionsNameTheReadersLanguage()
        wrappedCommandsReadAsWritten()
        stepsKeepWhatTheyWereGivenAndGaveBack()
        aStepTailAlreadyShowsWork()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static let folder = URL(fileURLWithPath: "/Users/reader/project")

    static func workspace(_ mode: AgentMode) -> AgentWorkspace {
        AgentWorkspace(folder: folder, mode: mode)
    }

    static func command(_ line: String) -> AgentApprovalRequest {
        AgentApprovalRequest(id: "c", action: .command(line))
    }

    static func edit(_ path: String, _ kind: AgentApprovalRequest.FileChange.Kind = .update)
        -> AgentApprovalRequest
    {
        AgentApprovalRequest(
            id: "e", action: .fileChanges([.init(path: path, kind: kind, diff: "")]))
    }

    /// A sibling that merely shares the prefix, or a `..` that climbs out, is outside.
    static func aFolderContainsOnlyWhatResolvesInsideIt() {
        let space = workspace(.ask)
        expect(space.contains("/Users/reader/project/a.txt"), "an absolute path inside is inside")
        expect(space.contains("src/main.swift"), "a relative path resolves against the folder")
        expect(space.contains("/Users/reader/project"), "the folder itself is inside")
        expect(!space.contains("/Users/reader/project-old/a.txt"), "a sibling sharing the prefix is outside")
        expect(!space.contains("../secrets.txt"), "climbing out with .. leaves the folder")
        expect(!space.contains("/Users/reader/.ssh/id_rsa"), "an unrelated absolute path is outside")
        expect(space.contains("/Users/reader/project/./src/../a.txt"), "dot segments are resolved")
    }

    static func readOnlyRefusesEverythingThatChangesAFile() {
        let space = workspace(.readOnly)
        let none = AgentGrants()
        expect(AgentApprovalPolicy.verdict(for: command("ls"), in: space, grants: none) == .deny,
            "read-only refuses a command")
        expect(AgentApprovalPolicy.verdict(for: edit("a.txt"), in: space, grants: none) == .deny,
            "read-only refuses an edit inside the folder")
        let read = AgentApprovalRequest(id: "r", action: .read("/etc/hosts"))
        expect(AgentApprovalPolicy.verdict(for: read, in: space, grants: none) == .ask,
            "a read outside the folder is still the reader's call")
        var granted = AgentGrants()
        granted.record(command("ls"), in: space)
        expect(AgentApprovalPolicy.verdict(for: command("ls"), in: space, grants: granted) == .deny,
            "a chat grant never outranks read-only")
    }

    static func askingWaitsUntilTheReaderAllowsForTheChat() {
        let space = workspace(.ask)
        var grants = AgentGrants()
        expect(AgentApprovalPolicy.verdict(for: command("npm test"), in: space, grants: grants) == .ask,
            "a command asks")
        expect(AgentApprovalPolicy.verdict(for: edit("a.txt"), in: space, grants: grants) == .ask,
            "an edit asks")
        grants.record(command("npm test"), in: space)
        grants.record(edit("a.txt"), in: space)
        expect(AgentApprovalPolicy.verdict(for: command("npm test"), in: space, grants: grants) == .allow,
            "the same command is allowed once granted")
        expect(AgentApprovalPolicy.verdict(for: command("npm publish"), in: space, grants: grants) == .ask,
            "a grant covers the exact command line only")
        expect(AgentApprovalPolicy.verdict(for: edit("b/c.txt"), in: space, grants: grants) == .allow,
            "an edit grant covers every edit inside the folder")
        expect(AgentApprovalPolicy.verdict(for: edit("/tmp/x"), in: space, grants: grants) == .ask,
            "an edit grant stops at the folder")
        var outside = AgentGrants()
        outside.record(edit("/tmp/x"), in: space)
        expect(!outside.covers(edit("a.txt"), in: space), "allowing an edit outside grants nothing")
        let tool = AgentApprovalRequest(id: "t", action: .tool(name: "NotebookEdit", summary: "{}"))
        grants.record(tool, in: space)
        expect(AgentApprovalPolicy.verdict(for: tool, in: space, grants: grants) == .allow,
            "a tool grant is by name")
    }

    static func autoEditAllowsEditsThatStayInTheFolder() {
        let space = workspace(.autoEdit)
        let none = AgentGrants()
        expect(AgentApprovalPolicy.verdict(for: edit("a.txt"), in: space, grants: none) == .allow,
            "an edit inside goes through")
        expect(AgentApprovalPolicy.verdict(for: edit("/tmp/a.txt"), in: space, grants: none) == .ask,
            "an edit outside still asks")
        expect(
            AgentApprovalPolicy.verdict(for: edit("a.txt", .move(to: "/tmp/a.txt")), in: space, grants: none)
                == .ask,
            "a move out of the folder asks")
        expect(AgentApprovalPolicy.verdict(for: command("rm -rf build"), in: space, grants: none) == .ask,
            "a command still asks")
    }

    static func claudeOffersOnlyTheToolsAModeAllows() {
        expect(ClaudeAgentTool.tools(for: .readOnly) == ["Read", "Glob", "Grep"], "read-only offers only reads")
        let full = ClaudeAgentTool.tools(for: .ask)
        expect(full.contains("Bash") && full.contains("Edit") && full.contains("Write"),
            "asking offers edits and commands")
        expect(!full.contains("Task") && !full.contains("WebFetch") && !full.contains("WebSearch"),
            "no subagents and no web tools")
        expect(ClaudeAgentTool.tools(for: .autoEdit) == full, "auto-edit offers the same tools as asking")
    }

    static func claudeRequestsReadAsWhatTheyWouldDo() {
        let bash = ClaudeAgentTool.approval(
            id: "1", name: "Bash",
            input: .object(["command": .string("npm test"), "description": .string("Run tests")]),
            fileExists: { _ in false })
        expect(bash.action == .command("npm test"), "Bash is a command")
        expect(bash.reason == "Run tests", "its description is the reason")

        let edit = ClaudeAgentTool.approval(
            id: "2", name: "Edit",
            input: .object([
                "file_path": .string("/p/a.txt"), "old_string": .string("one\ntwo"),
                "new_string": .string("one\nthree"),
            ]),
            fileExists: { _ in true })
        expect(
            edit.action == .fileChanges([.init(path: "/p/a.txt", kind: .update, diff: "-one\n-two\n+one\n+three")]),
            "Edit is an update whose diff removes the old text and adds the new")

        let created = ClaudeAgentTool.approval(
            id: "3", name: "Write",
            input: .object(["file_path": .string("/p/new.txt"), "content": .string("hi")]),
            fileExists: { _ in false })
        expect(created.action == .fileChanges([.init(path: "/p/new.txt", kind: .add, diff: "+hi")]),
            "Write to a missing file adds it")
        let overwritten = ClaudeAgentTool.approval(
            id: "4", name: "Write",
            input: .object(["file_path": .string("/p/a.txt"), "content": .string("hi")]),
            fileExists: { _ in true })
        if case .fileChanges(let changes) = overwritten.action {
            expect(changes.first?.kind == .update, "Write over an existing file updates it")
        } else {
            expect(false, "Write is a file change")
        }

        let read = ClaudeAgentTool.approval(
            id: "5", name: "Read", input: .object(["file_path": .string("/etc/hosts")]),
            fileExists: { _ in true })
        expect(read.action == .read("/etc/hosts"), "Read names its file")
        let grep = ClaudeAgentTool.approval(
            id: "6", name: "Grep", input: .object(["pattern": .string("x"), "path": .string("/var/log")]),
            fileExists: { _ in true })
        expect(grep.action == .read("/var/log"), "Grep names where it searches")

        let long = String(repeating: "a", count: 1_000)
        let other = ClaudeAgentTool.approval(
            id: "7", name: "NotebookEdit", input: .object(["source": .string(long)]),
            fileExists: { _ in true })
        if case .tool(let name, let summary) = other.action {
            expect(name == "NotebookEdit", "an unknown tool keeps its name")
            expect(summary.count == ClaudeAgentTool.summaryLimit + 1 && summary.hasSuffix("…"),
                "its arguments are cut to the summary limit")
        } else {
            expect(false, "an unknown tool is a tool request")
        }
    }

    static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func object(_ text: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }

    static func wrappedCommandsReadAsWritten() {
        // What Codex 0.162.1 actually sent: a login shell around the script, its quoting mixed.
        let mixed = #"/bin/bash -lc "echo 'it''s'; echo oops 1>&2; echo \"q\" "'$HOME | tr a-z A-Z'"#
        expect(
            ShellWords.script(of: mixed) == #"echo 'it''s'; echo oops 1>&2; echo "q" $HOME | tr a-z A-Z"#,
            "double- and single-quoted runs join into one script, their escapes resolved")
        expect(ShellWords.script(of: "/bin/bash -lc 'ls /definitely/not/here'") == "ls /definitely/not/here",
            "a single-quoted script comes out as written")
        expect(ShellWords.script(of: "/bin/zsh -c 'a\nb'") == "a\nb", "zsh's wrapper is one too")
        expect(ShellWords.script(of: "ls -la") == "ls -la", "a plain command line is left alone")
        expect(ShellWords.script(of: "bash -lc 'a' 'b'") == "bash -lc 'a' 'b'", "more words is not a wrapper")
        expect(ShellWords.script(of: "bash -lc 'open") == "bash -lc 'open", "an unclosed quote stays as sent")
        let excluding = #"/bin/bash -lc "pwd && rg --files -g AGENTS.md -g '"'!node_modules'"' -g '"'!.git'"'""#
        expect(
            ShellWords.script(of: excluding) == "pwd && rg --files -g AGENTS.md -g '!node_modules' -g '!.git'",
            "a `!` Codex steps out of double quotes for still lands in the one script")
        expect(ShellWords.split(#"a\ b "c\"d" 'e\f'"#) == ["a b", #"c"d"#, #"e\f"#],
            "a backslash escapes outside quotes, some things inside double ones, nothing inside single")
    }

    static func stepsKeepWhatTheyWereGivenAndGaveBack() {
        let wrapped: [String: JSONValue] = [
            "id": .string("c2"), "type": .string("commandExecution"),
            "command": .string("/bin/bash -lc 'ls /definitely/not/here'"),
        ]
        expect(
            CodexAgentTurn.toolCall(for: wrapped)
                == .toolCall(
                    id: "c2", origin: "", title: "ls /definitely/not/here", kind: .command,
                    detail: ChatToolDetail(input: "ls /definitely/not/here")),
            "a Codex row shows the script, not the shell around it")
        var failed = wrapped
        failed["status"] = .string("failed")
        failed["aggregatedOutput"] = .string("ls: /definitely/not/here: No such file or directory\n")
        failed["exitCode"] = .number(1)
        expect(
            CodexAgentTurn.toolResult(for: failed)
                == .toolResult(
                    id: "c2", isError: true, output: "ls: /definitely/not/here: No such file or directory\n",
                    exitCode: 1),
            "a finished command brings back its output and exit code")
        let patch: [String: JSONValue] = [
            "id": .string("p1"), "type": .string("fileChange"),
            "changes": .array([
                .object([
                    "path": .string("/p/a.txt"), "kind": .object(["type": .string("update")]),
                    "diff": .string("@@ -1 +1 @@\n-one\n+two"),
                ])
            ]),
        ]
        guard case .toolCall(_, _, _, _, let detail?) = CodexAgentTurn.toolCall(for: patch) else {
            return expect(false, "a patch is a row with its diff")
        }
        expect(detail.input == "--- /p/a.txt\n+++ /p/a.txt\n@@ -1 +1 @@\n-one\n+two",
            "a patch keeps its diff under the file's header")

        let bash = ClaudeAgentTool.detail(
            name: "Bash", input: .object(["command": .string("ls\npwd"), "description": .string("列出文件")]))
        expect(bash == ChatToolDetail(input: "ls\npwd", explanation: "列出文件"),
            "a Claude command keeps every line and Claude's own sentence for it")
        let edit = ClaudeAgentTool.detail(
            name: "Edit",
            input: .object([
                "file_path": .string("/p/a.txt"), "old_string": .string("one"), "new_string": .string("two"),
            ]))
        expect(edit.input == "--- /p/a.txt\n+++ /p/a.txt\n-one\n+two", "an edit is a diff")
        let renamed = JSONValue.object(["cmd": .string("ls")])
        expect(ClaudeAgentTool.detail(name: "Bash", input: renamed).input == #"{"cmd":"ls"}"#,
            "a field a newer CLI renamed keeps the raw input rather than an empty one")
        expect(ClaudeAgentTool.row(name: "Bash", input: renamed)?.title == "Bash",
            "and its row is named by the tool")
        expect(
            ClaudeAgentTool.detail(name: "NewTool", input: .object(["url": .string("https://a.b/c")])).input
                == #"{"url":"https://a.b/c"}"#,
            "a tool this does not know keeps its raw input")

        let exit = ClaudeAgentTool.result("Exit code 2\nls: x: No such file", isError: true)
        expect(exit.output == "ls: x: No such file" && exit.exitCode == 2,
            "Claude's failed command gives its exit code, and the output under it")
        let plain = ClaudeAgentTool.result("Exit code 2", isError: false)
        expect(plain.output == "Exit code 2" && plain.exitCode == nil, "a success is read as printed")
        let printed = line([
            "type": "user",
            "message": [
                "content": [
                    ["type": "tool_result", "tool_use_id": "t1", "content": "Exit code 1\nboom", "is_error": true]
                ]
            ],
        ])
        expect(
            InstalledAIStreamDecoder.decode(printed, kind: .claude, agent: true).events
                == [.toolResult(id: "t1", isError: true, output: "boom", exitCode: 1)],
            "a result frame carries what the step printed")
        let blocks = line([
            "type": "user",
            "message": [
                "content": [
                    [
                        "type": "tool_result", "tool_use_id": "t3",
                        "content": [["type": "text", "text": "a"], ["type": "image"], ["type": "text", "text": "b"]],
                    ]
                ]
            ],
        ])
        expect(
            InstalledAIStreamDecoder.decode(blocks, kind: .claude, agent: true).events
                == [.toolResult(id: "t3", isError: false, output: "a\nb")],
            "a result's text blocks join, and an image block has no text")
        let server = line([
            "type": "assistant",
            "message": [
                "content": [["type": "tool_use", "id": "t4", "name": "mcp__files__read_file", "input": ["path": "a"]]]
            ],
        ])
        guard
            case .toolCall(_, _, _, _, let arguments?)? = InstalledAIStreamDecoder.decode(
                server, kind: .claude, agent: true
            ).events.first
        else { return expect(false, "an MCP call is a row with its arguments") }
        expect(arguments.input == #"{"path":"a"}"#, "an MCP call keeps its arguments, whatever the tool")

        var long = ChatToolDetail(input: String(repeating: "x", count: ChatToolDetail.inputLimit + 5))
        expect(long.input.count == ChatToolDetail.inputLimit + 1 && long.input.hasSuffix("…"),
            "a long input keeps its start")
        let log = (1...4000).map { "line \($0)" }.joined(separator: "\n")
        long.record(output: log, exitCode: 2)
        let kept = long.output ?? ""
        expect(
            long.isOutputTrimmed && kept.hasPrefix("line ") && kept.hasSuffix("line 4000")
                && kept.count <= ChatToolDetail.outputLimit,
            "a long output keeps its end, from the start of a line")
        long.record(output: "", exitCode: nil)
        expect(long.output == kept && long.exitCode == 2, "an empty report erases nothing")
        let moved = [
            AgentApprovalRequest.FileChange(path: "/p/new.txt", kind: .add, diff: "alpha\nbeta\n"),
            AgentApprovalRequest.FileChange(path: "/p/old.txt", kind: .delete, diff: "bye"),
            AgentApprovalRequest.FileChange(path: "/p/a.txt", kind: .move(to: "/p/b.txt"), diff: ""),
            AgentApprovalRequest.FileChange(path: "/p/c.txt", kind: .update, diff: "@@ -1 +1 @@\n-x\n+y"),
        ].unifiedDiff
        expect(
            moved == "--- /dev/null\n+++ /p/new.txt\n+alpha\n+beta\n--- /p/old.txt\n+++ /dev/null\n-bye\n"
                + "--- /p/a.txt\n+++ /p/b.txt\n\n--- /p/c.txt\n+++ /p/c.txt\n@@ -1 +1 @@\n-x\n+y",
            "a whole added or deleted file is marked line by line, each file under a unified diff's header")
        let counts = ChatToolDetail.diffCounts(in: moved)
        expect(counts.added == 3 && counts.removed == 2, "a diff counts what it adds and removes, not its headers")
        let numbered = (1...30).map(String.init).joined(separator: "\n")
        let head = ChatToolDetail.excerpt(of: numbered, lines: 12, fromEnd: false)
        let tail = ChatToolDetail.excerpt(of: numbered, lines: 12, fromEnd: true)
        expect(head.text.hasPrefix("1\n") && head.text.hasSuffix("\n12") && head.hidden == 18,
            "a long input shows its first lines")
        expect(tail.text.hasPrefix("19\n") && tail.text.hasSuffix("\n30") && tail.hidden == 18,
            "a long output shows its last lines")
        expect(ChatToolDetail.excerpt(of: "a\nb", lines: 12, fromEnd: true) == ("a\nb", 0),
            "a short block shows whole")
    }

    static func aStepTailAlreadyShowsWork() {
        var reply = ChatMessage(role: .assistant, text: "", state: .streaming)
        expect(!reply.tailShowsProgress, "an empty reply shows nothing of its own working")
        reply.toolUses = [
            ChatToolUse(callID: "a", origin: "", title: "ls", state: .running, textOffset: 0, sequence: 0, kind: .command)
        ]
        expect(reply.tailShowsProgress, "a running step shows itself working")
        reply.toolUses[0].state = .completed
        expect(!reply.tailShowsProgress, "a finished one does not")
        reply.text = "Counted."
        reply.reasoning = [
            ChatReasoning(text: "**Counting lines**\n\nThe file is short.", textOffset: 8, duration: nil)
        ]
        expect(reply.tailShowsProgress, "a thought still arriving shows itself")
        expect(reply.reasoning[0].heading == "Counting lines", "a summary's bolded line names the thought")
        expect(ChatReasoning(text: "No heading here", textOffset: 0, duration: nil).heading == nil,
            "plain thinking has no heading")
    }

    static func line(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    /// The `response` a control answer carries, the part Claude acts on.
    static func answer(_ data: Data?) -> [String: Any] {
        let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let response = body?["response"] as? [String: Any]
        return response?["response"] as? [String: Any] ?? [:]
    }

    static func deletingAlwaysAsks() {
        let space = workspace(.autoEdit)
        let delete = edit("old.txt", .delete)
        expect(AgentApprovalPolicy.verdict(for: delete, in: space, grants: AgentGrants()) == .ask,
            "auto-edit still asks before a delete inside the folder")
        var grants = AgentGrants()
        grants.record(edit("a.txt"), in: space)
        expect(AgentApprovalPolicy.verdict(for: delete, in: workspace(.ask), grants: grants) == .ask,
            "an edit grant never covers a delete")
        expect(!AgentGrants.admits(delete, in: space), "a delete is never offered for the whole chat")
        expect(!AgentGrants.admits(edit("/tmp/a.txt"), in: space), "nor is an edit outside the folder")
        expect(AgentGrants.admits(command("ls"), in: space), "a command can be allowed for the chat")
        var refused = AgentGrants()
        refused.record(delete, in: space)
        expect(refused == AgentGrants(), "recording a delete grants nothing")
    }

    static func claudeLaunchesWithItsSessionAndRules() {
        let first = ClaudeAgentLaunch.arguments(
            model: "opus", effort: "high", workspace: workspace(.ask), session: "s-1", resuming: false,
            rounds: 12, instructions: "Be brief.", mcpConfiguration: nil, handles: [],
            managedMCPPolicy: false)
        expect(value(after: "--session-id", in: first) == "s-1", "the first turn names its session")
        expect(!first.contains("--resume"), "and resumes none")
        expect(value(after: "--permission-mode", in: first) == "default", "asking keeps Claude's default mode")
        expect(value(after: "--permission-prompt-tool", in: first) == "stdio", "questions come to Tinycast")
        expect(value(after: "--setting-sources", in: first) == "user", "the folder's own settings stay out")
        expect(value(after: "--tools", in: first) == ClaudeAgentTool.tools(for: .ask).joined(separator: ","),
            "the tools are the mode's")
        expect(value(after: "--max-turns", in: first) == "12", "the round cap is passed")
        expect(value(after: "--effort", in: first) == "high", "so is the effort")
        expect(value(after: "--mcp-config", in: first) == #"{"mcpServers":{}}"#,
            "no servers is an empty config, never the reader's own")
        expect(value(after: "--append-system-prompt", in: first) == "Be brief.", "the instructions ride along")
        expect(!first.contains("--no-session-persistence"), "an agent's session is kept")

        let resumed = ClaudeAgentLaunch.arguments(
            model: "opus", effort: nil, workspace: workspace(.autoEdit), session: "s-1", resuming: true,
            rounds: nil, instructions: "", mcpConfiguration: "/tmp/mcp.json", handles: [],
            managedMCPPolicy: true)
        expect(value(after: "--resume", in: resumed) == "s-1", "a later turn resumes the session")
        expect(!resumed.contains("--session-id"), "and names no new one")
        expect(value(after: "--permission-mode", in: resumed) == "acceptEdits", "auto-edit accepts edits")
        expect(!resumed.contains("--mcp-config") && !resumed.contains("--strict-mcp-config"),
            "an admin's MCP policy decides the servers")
        expect(!resumed.contains("--max-turns") && !resumed.contains("--effort"), "no cap and no effort, no flag")

        let reading = ClaudeAgentLaunch.arguments(
            model: "opus", effort: nil, workspace: workspace(.readOnly), session: "s-2", resuming: false,
            rounds: nil, instructions: "", mcpConfiguration: nil, handles: [], managedMCPPolicy: false)
        expect(value(after: "--tools", in: reading) == "Read,Glob,Grep", "read-only offers reads alone")
    }

    static func claudeSettingsTurnHooksOffAndAsk() {
        let asking = object(ClaudeAgentLaunch.settings(for: .ask, handles: ["files"]))
        expect(asking["disableAllHooks"] as? Bool == true, "hooks are off")
        let rules = { (settings: [String: Any]) in
            Set((settings["permissions"] as? [String: Any])?["ask"] as? [String] ?? [])
        }
        expect(rules(asking) == [ClaudeMCPLaunch.toolPrefix + "files", "Bash", "Edit", "Write"],
            "asking routes every change and every server to Tinycast")
        let editing = object(ClaudeAgentLaunch.settings(for: .autoEdit, handles: []))
        expect(rules(editing) == ["Bash"], "auto-edit still asks before a command")
        let reading = object(ClaudeAgentLaunch.settings(for: .readOnly, handles: []))
        expect(rules(reading).isEmpty && reading["disableAllHooks"] as? Bool == true,
            "read-only has nothing to ask about, and its hooks are off too")
    }

    static func claudeCarriesTheChatIntoItsFirstTurnOnly() {
        let messages = [
            AIMessage(role: .user, text: "hi"), AIMessage(role: .assistant, text: "hello"),
            AIMessage(role: .user, text: "list the files"),
        ]
        let first = ClaudeAgentLaunch.message(for: messages, resuming: false)
        expect(first.contains("User:\nhi") && first.contains("Assistant:\nhello"),
            "a new session hears the chat so far")
        expect(first.hasSuffix("Now:\nlist the files"), "and then the question")
        expect(ClaudeAgentLaunch.message(for: messages, resuming: true) == "list the files",
            "a resumed session already has the rest")
        expect(ClaudeAgentLaunch.message(for: [AIMessage(role: .user, text: "only")], resuming: false) == "only",
            "a first message goes as it is")
    }

    static func claudeAgentFramesDecode() {
        let start = line(["type": "system", "subtype": "init", "session_id": "abc"])
        expect(InstalledAIStreamDecoder.decode(start, kind: .claude, agent: true).sessionID == "abc",
            "an agent turn reports its session")
        expect(InstalledAIStreamDecoder.decode(start, kind: .claude).sessionID == nil,
            "a plain chat keeps no session")

        let use = line([
            "type": "assistant",
            "message": ["content": [["type": "tool_use", "id": "t1", "name": "Bash", "input": ["command": "ls -la"]]]],
        ])
        expect(
            InstalledAIStreamDecoder.decode(use, kind: .claude, agent: true).events
                == [
                    .toolCall(
                        id: "t1", origin: "", title: "ls -la", kind: .command,
                        detail: ChatToolDetail(input: "ls -la"))
                ],
            "a built-in tool is a row of its kind")
        expect(InstalledAIStreamDecoder.decode(use, kind: .claude).events.isEmpty,
            "a plain chat shows no built-in rows")
        let notes = line([
            "type": "assistant",
            "message": ["content": [["type": "tool_use", "id": "t2", "name": "TodoWrite", "input": [:]]]],
        ])
        expect(InstalledAIStreamDecoder.decode(notes, kind: .claude, agent: true).events.isEmpty,
            "the agent's own notes are not a step")
        let result = line([
            "type": "user",
            "message": ["content": [["type": "tool_result", "tool_use_id": "t1", "is_error": true]]],
        ])
        expect(
            InstalledAIStreamDecoder.decode(result, kind: .claude, agent: true).events
                == [.toolResult(id: "t1", isError: true)],
            "a refused or failed step ends its row as failed")

        let question = line([
            "type": "control_request", "request_id": "r1",
            "request": ["subtype": "can_use_tool", "tool_name": "Bash", "input": ["command": "rm x"]],
        ])
        let asked = InstalledAIStreamDecoder.decode(question, kind: .claude, agent: true)
        expect(
            asked.agentRequest
                == ClaudeControlProtocol.AgentRequest(
                    id: "r1", toolName: "Bash", input: .object(["command": .string("rm x")])),
            "a question about a built-in tool is the agent's")
        expect(asked.controlRequest == nil && asked.unsupportedRequestID == nil,
            "and is neither an MCP consent nor refused as unknown")
        let server = line([
            "type": "control_request", "request_id": "r2",
            "request": ["subtype": "can_use_tool", "tool_name": "mcp__files__read", "input": [:]],
        ])
        expect(InstalledAIStreamDecoder.decode(server, kind: .claude, agent: true).agentRequest == nil,
            "a server's tool keeps the MCP consent path")
        let named = line([
            "type": "control_request", "request_id": "r3",
            "request": [
                "subtype": "can_use_tool", "tool_name": "Bash", "input": ["command": "ls"], "tool_use_id": "toolu_1",
            ],
        ])
        expect(InstalledAIStreamDecoder.decode(named, kind: .claude, agent: true).agentRequest?.toolUseID == "toolu_1",
            "the question names the call its transcript row shows")

        let lost = line([
            "type": "result", "subtype": "error_during_execution", "is_error": true,
            "errors": ["No conversation found with session ID: s"],
        ])
        expect(
            InstalledAIStreamDecoder.decode(lost, kind: .claude, agent: true).error
                == "No conversation found with session ID: s",
            "a lost session says why in the result itself, not only on stderr")
        let stopped = line(["type": "result", "subtype": "error_during_execution", "is_error": true])
        let interrupted = InstalledAIStreamDecoder.decode(stopped, kind: .claude, agent: true)
        expect(interrupted.error == nil && interrupted.failedKind == .claude,
            "an interrupted turn ends in an error with nothing to say")
    }

    static func claudeHearsEachDecision() {
        let request = ClaudeControlProtocol.AgentRequest(
            id: "r1", toolName: "Bash", input: .object(["command": .string("ls")]))
        let allowed = answer(ClaudeControlProtocol.response(to: request, decision: .allow))
        expect(allowed["behavior"] as? String == "allow", "allowing allows")
        expect((allowed["updatedInput"] as? [String: Any])?["command"] as? String == "ls",
            "the input goes back as it came")
        let forChat = answer(ClaudeControlProtocol.response(to: request, decision: .allowForChat))
        expect(forChat["behavior"] as? String == "allow" && forChat["updatedPermissions"] == nil,
            "a chat grant is Tinycast's own, never written into Claude's settings")
        let denied = answer(ClaudeControlProtocol.response(to: request, decision: .deny))
        expect(denied["behavior"] as? String == "deny" && denied["interrupt"] == nil,
            "a refusal lets the turn go on")
        let redirected = answer(ClaudeControlProtocol.response(to: request, decision: .redirect("do y")))
        expect(redirected["behavior"] as? String == "deny" && redirected["interrupt"] as? Bool == true,
            "a redirect ends the turn so the new instruction goes next")
    }

    static func codexApprovalsReadAsRequests() {
        let command = CodexApproval(
            method: CodexApproval.commandMethod,
            params: [
                "threadId": .string("th"), "itemId": .string("i1"), "command": .string("npm test"),
                "reason": .string("Runs the tests"),
            ])
        expect(
            command?.request(changes: [])
                == AgentApprovalRequest(id: "i1", action: .command("npm test"), reason: "Runs the tests"),
            "a command approval names its command and reason")
        expect(
            CodexApproval(method: "item/other", params: ["threadId": .string("t"), "itemId": .string("i")]) == nil,
            "another method is no approval")
        expect(CodexApproval(method: CodexApproval.commandMethod, params: ["itemId": .string("i")]) == nil,
            "an approval without its thread is ignored")

        let change = { (path: String, kind: JSONValue, diff: String) -> JSONValue in
            .object(["path": .string(path), "kind": kind, "diff": .string(diff)])
        }
        let item: [String: JSONValue] = [
            "id": .string("i2"), "type": .string("fileChange"),
            "changes": .array([
                change("/p/a.txt", .object(["type": .string("update"), "move_path": .null]), "@@ -1 +1 @@"),
                change("/p/b.txt", .object(["type": .string("add")]), "hi"),
                change("/p/c.txt", .object(["type": .string("delete")]), ""),
                change("/p/d.txt", .object(["type": .string("update"), "move_path": .string("/p/e.txt")]), ""),
            ]),
        ]
        let changes = CodexApproval.changes(in: item)
        expect(changes.map(\.kind) == [.update, .add, .delete, .move(to: "/p/e.txt")],
            "each file keeps its kind, a rename its destination")
        expect(changes.first?.diff == "@@ -1 +1 @@", "and its diff")
        let patch = CodexApproval(
            method: CodexApproval.fileChangeMethod, params: ["threadId": .string("th"), "itemId": .string("i2")])
        expect(patch?.request(changes: changes).action == .fileChanges(changes),
            "a patch approval carries the changes its item announced")
        expect(CodexApproval.result(for: .allowForChat)["decision"] as? String == "accept",
            "a chat grant is a plain accept, never one for the session")
        expect(CodexApproval.result(for: .redirect("x"))["decision"] as? String == "decline",
            "a redirect declines")
    }

    static func codexTurnsAreSandboxedByMode() {
        expect(CodexAgentTurn.approvalPolicy(for: .readOnly, armed: false) == "never", "read-only never asks")
        expect(CodexAgentTurn.approvalPolicy(for: .readOnly, armed: true) == "untrusted",
            "unless a server is armed, whose calls must still be asked about")
        expect(
            CodexAgentTurn.approvalPolicy(for: .ask, armed: false) == "untrusted"
                && CodexAgentTurn.approvalPolicy(for: .autoEdit, armed: false) == "untrusted",
            "the other modes ask before anything untrusted")
        expect(CodexAgentTurn.threadSandbox(for: .readOnly) == "read-only", "read-only is its own sandbox")
        expect(CodexAgentTurn.threadSandbox(for: .ask) == "workspace-write", "asking may write the folder")
        let writing = CodexAgentTurn.sandboxPolicy(for: workspace(.ask)).objectValue ?? [:]
        expect(writing["type"] == .string("workspaceWrite"), "asking writes inside the workspace")
        expect(writing["writableRoots"] == .array([.string("/Users/reader/project")]), "only the folder is writable")
        expect(writing["networkAccess"] == .bool(false), "and the network stays off")
        let reading = CodexAgentTurn.sandboxPolicy(for: workspace(.readOnly)).objectValue ?? [:]
        expect(reading["type"] == .string("readOnly") && reading["networkAccess"] == .bool(false),
            "read-only reads, offline")

        let run: [String: JSONValue] = ["id": .string("c1"), "type": .string("commandExecution"), "command": .string("ls\npwd")]
        expect(
            CodexAgentTurn.toolCall(for: run)
                == .toolCall(
                    id: "c1", origin: "", title: "ls…", kind: .command, detail: ChatToolDetail(input: "ls\npwd")),
            "a command is a row titled by its first line")
        var done = run
        done["status"] = .string("completed")
        expect(CodexAgentTurn.toolResult(for: done) == .toolResult(id: "c1", isError: false), "a completed run succeeds")
        done["status"] = .string("declined")
        expect(CodexAgentTurn.toolResult(for: done) == .toolResult(id: "c1", isError: true), "a declined run fails")
        expect(CodexAgentTurn.toolCall(for: ["id": .string("m"), "type": .string("agentMessage")]) == nil,
            "a message is no step")
    }

    static func lookingInsideTheFolderNeedsNoAnswer() {
        let action = { (type: String, path: String?) -> JSONValue in
            var fields: [String: JSONValue] = ["type": .string(type), "command": .string("x")]
            if let path { fields["path"] = .string(path) }
            return .object(fields)
        }
        let cwd = "/Users/reader/project"
        let reads = CodexApproval.inspectedPaths(
            .array([action("read", "/Users/reader/project/a.txt"), action("search", "src"), action("listFiles", nil)]),
            in: cwd)
        expect(reads == ["/Users/reader/project/a.txt", "/Users/reader/project/src", "/Users/reader/project"],
            "Codex's own reading of a command gives the paths it looks at, relative ones from its directory")
        expect(CodexApproval.inspectedPaths(.array([action("read", "a"), action("unknown", nil)]), in: cwd) == nil,
            "one part Codex cannot read makes the whole command a command")
        expect(CodexApproval.inspectedPaths(.array([]), in: cwd) == nil, "no reading is no inspection")

        let approval = CodexApproval(
            method: CodexApproval.commandMethod,
            params: [
                "threadId": .string("t"), "itemId": .string("i"), "command": .string("/bin/bash -lc 'cat a.txt'"),
                "cwd": .string(cwd), "commandActions": .array([action("read", "/Users/reader/project/a.txt")]),
            ])
        let inside = approval?.request(changes: [])
        expect(
            inside?.action == .inspection(command: "cat a.txt", paths: ["/Users/reader/project/a.txt"]),
            "a read-only command is an inspection, shown without the shell Codex wraps it in")
        for mode in AgentMode.allCases {
            expect(inside.map { AgentApprovalPolicy.verdict(for: $0, in: workspace(mode), grants: AgentGrants()) } == .allow,
                "looking inside the folder goes through in \(mode)")
        }
        let outside = AgentApprovalRequest(
            id: "o", action: .inspection(command: "cat ~/.ssh/config", paths: ["/Users/reader/.ssh/config"]))
        expect(AgentApprovalPolicy.verdict(for: outside, in: workspace(.autoEdit), grants: AgentGrants()) == .ask,
            "looking outside it is the reader's call")
        expect(AgentApprovalPolicy.verdict(for: outside, in: workspace(.readOnly), grants: AgentGrants()) == .ask,
            "even in read-only, since it changes nothing")
        var grants = AgentGrants()
        grants.record(outside, in: workspace(.ask))
        expect(AgentApprovalPolicy.verdict(for: outside, in: workspace(.ask), grants: grants) == .allow,
            "and once allowed for the chat, the same command goes through")
    }

    static func instructionsNameTheReadersLanguage() {
        let claude = AgentInstructions.claude(language: "Chinese, Simplified")
        expect(claude.hasSuffix("in Chinese, Simplified."), "Claude describes its commands in the interface language")
        let codex = AgentInstructions.codex(folder: "/Users/reader/project", language: "English")
        expect(codex.contains("/Users/reader/project") && codex.contains("apply_patch"),
            "Codex is told its folder and to edit with patches")
        expect(codex.hasSuffix("in English."), "and the language its descriptions are read in")
    }

    static func threadsContinueOnlyWhereTheyStarted() {
        let thread = AgentThread(route: "claude", folder: "/Users/reader/project", id: "s")
        expect(thread.continues(route: "claude", in: workspace(.ask)), "same route, same folder")
        expect(thread.continues(route: "claude", in: workspace(.readOnly)), "a new mode keeps the session")
        expect(!thread.continues(route: "codex", in: workspace(.ask)), "another CLI starts its own")
        let elsewhere = AgentWorkspace(folder: URL(fileURLWithPath: "/Users/reader/other"), mode: .ask)
        expect(!thread.continues(route: "claude", in: elsewhere), "another folder starts its own")
    }

    static func decisionsSayWhetherTheyAllow() {
        expect(AgentApprovalDecision.allow.allows && AgentApprovalDecision.allowForChat.allows,
            "allowing allows")
        expect(!AgentApprovalDecision.deny.allows && !AgentApprovalDecision.redirect("x").allows,
            "refusing, with or without a redirect, does not")
    }
}
