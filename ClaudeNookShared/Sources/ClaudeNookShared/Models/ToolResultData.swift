//
//  ToolResultData.swift
//  ClaudeNookShared
//
//  Structured models for all Claude Code tool results.
//

import Foundation

// MARK: - Tool Result Wrapper

/// Structured tool result data - parsed from JSONL tool_result blocks
public enum ToolResultData: Equatable, Sendable {
    case read(ReadResult)
    case edit(EditResult)
    case write(WriteResult)
    case bash(BashResult)
    case grep(GrepResult)
    case glob(GlobResult)
    case todoWrite(TodoWriteResult)
    case task(TaskResult)
    case webFetch(WebFetchResult)
    case webSearch(WebSearchResult)
    case askUserQuestion(AskUserQuestionResult)
    case bashOutput(BashOutputResult)
    case killShell(KillShellResult)
    case exitPlanMode(ExitPlanModeResult)
    case mcp(MCPResult)
    case generic(GenericResult)
}

// MARK: - Read Tool Result

public struct ReadResult: Equatable, Sendable {
    public let filePath: String
    public let content: String
    public let numLines: Int
    public let startLine: Int
    public let totalLines: Int

    public init(filePath: String, content: String, numLines: Int, startLine: Int, totalLines: Int) {
        self.filePath = filePath
        self.content = content
        self.numLines = numLines
        self.startLine = startLine
        self.totalLines = totalLines
    }

    public var filename: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
}

// MARK: - Edit Tool Result

public struct EditResult: Equatable, Sendable {
    public let filePath: String
    public let oldString: String
    public let newString: String
    public let replaceAll: Bool
    public let userModified: Bool
    public let structuredPatch: [PatchHunk]?

    public init(filePath: String, oldString: String, newString: String, replaceAll: Bool, userModified: Bool, structuredPatch: [PatchHunk]?) {
        self.filePath = filePath
        self.oldString = oldString
        self.newString = newString
        self.replaceAll = replaceAll
        self.userModified = userModified
        self.structuredPatch = structuredPatch
    }

    public var filename: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
}

public struct PatchHunk: Equatable, Sendable {
    public let oldStart: Int
    public let oldLines: Int
    public let newStart: Int
    public let newLines: Int
    public let lines: [String]

    public init(oldStart: Int, oldLines: Int, newStart: Int, newLines: Int, lines: [String]) {
        self.oldStart = oldStart
        self.oldLines = oldLines
        self.newStart = newStart
        self.newLines = newLines
        self.lines = lines
    }
}

// MARK: - Write Tool Result

public struct WriteResult: Equatable, Sendable {
    public enum WriteType: String, Equatable, Sendable {
        case create
        case overwrite
    }

    public let type: WriteType
    public let filePath: String
    public let content: String
    public let structuredPatch: [PatchHunk]?

    public init(type: WriteType, filePath: String, content: String, structuredPatch: [PatchHunk]?) {
        self.type = type
        self.filePath = filePath
        self.content = content
        self.structuredPatch = structuredPatch
    }

    public var filename: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
}

// MARK: - Bash Tool Result

public struct BashResult: Equatable, Sendable {
    public let stdout: String
    public let stderr: String
    public let interrupted: Bool
    public let isImage: Bool
    public let returnCodeInterpretation: String?
    public let backgroundTaskId: String?

    public init(stdout: String, stderr: String, interrupted: Bool, isImage: Bool, returnCodeInterpretation: String?, backgroundTaskId: String?) {
        self.stdout = stdout
        self.stderr = stderr
        self.interrupted = interrupted
        self.isImage = isImage
        self.returnCodeInterpretation = returnCodeInterpretation
        self.backgroundTaskId = backgroundTaskId
    }

    public var hasOutput: Bool {
        !stdout.isEmpty || !stderr.isEmpty
    }

    public var displayOutput: String {
        if !stdout.isEmpty {
            return stdout
        }
        if !stderr.isEmpty {
            return stderr
        }
        return "(No content)"
    }
}

// MARK: - Grep Tool Result

public struct GrepResult: Equatable, Sendable {
    public enum Mode: String, Equatable, Sendable {
        case filesWithMatches = "files_with_matches"
        case content
        case count
    }

    public let mode: Mode
    public let filenames: [String]
    public let numFiles: Int
    public let content: String?
    public let numLines: Int?
    public let appliedLimit: Int?

    public init(mode: Mode, filenames: [String], numFiles: Int, content: String?, numLines: Int?, appliedLimit: Int?) {
        self.mode = mode
        self.filenames = filenames
        self.numFiles = numFiles
        self.content = content
        self.numLines = numLines
        self.appliedLimit = appliedLimit
    }
}

// MARK: - Glob Tool Result

public struct GlobResult: Equatable, Sendable {
    public let filenames: [String]
    public let durationMs: Int
    public let numFiles: Int
    public let truncated: Bool

    public init(filenames: [String], durationMs: Int, numFiles: Int, truncated: Bool) {
        self.filenames = filenames
        self.durationMs = durationMs
        self.numFiles = numFiles
        self.truncated = truncated
    }
}

// MARK: - TodoWrite Tool Result

public struct TodoWriteResult: Equatable, Sendable {
    public let oldTodos: [TodoItem]
    public let newTodos: [TodoItem]

    public init(oldTodos: [TodoItem], newTodos: [TodoItem]) {
        self.oldTodos = oldTodos
        self.newTodos = newTodos
    }
}

public struct TodoItem: Equatable, Sendable {
    public let content: String
    public let status: String // "pending", "in_progress", "completed"
    public let activeForm: String?

    public init(content: String, status: String, activeForm: String?) {
        self.content = content
        self.status = status
        self.activeForm = activeForm
    }
}

// MARK: - Task (Agent) Tool Result

public struct TaskResult: Equatable, Sendable {
    public let agentId: String
    public let status: String
    public let content: String
    public let prompt: String?
    public let totalDurationMs: Int?
    public let totalTokens: Int?
    public let totalToolUseCount: Int?

    public init(agentId: String, status: String, content: String, prompt: String?, totalDurationMs: Int?, totalTokens: Int?, totalToolUseCount: Int?) {
        self.agentId = agentId
        self.status = status
        self.content = content
        self.prompt = prompt
        self.totalDurationMs = totalDurationMs
        self.totalTokens = totalTokens
        self.totalToolUseCount = totalToolUseCount
    }
}

// MARK: - WebFetch Tool Result

public struct WebFetchResult: Equatable, Sendable {
    public let url: String
    public let code: Int
    public let codeText: String
    public let bytes: Int
    public let durationMs: Int
    public let result: String

    public init(url: String, code: Int, codeText: String, bytes: Int, durationMs: Int, result: String) {
        self.url = url
        self.code = code
        self.codeText = codeText
        self.bytes = bytes
        self.durationMs = durationMs
        self.result = result
    }
}

// MARK: - WebSearch Tool Result

public struct WebSearchResult: Equatable, Sendable {
    public let query: String
    public let durationSeconds: Double
    public let results: [SearchResultItem]

    public init(query: String, durationSeconds: Double, results: [SearchResultItem]) {
        self.query = query
        self.durationSeconds = durationSeconds
        self.results = results
    }
}

public struct SearchResultItem: Equatable, Sendable {
    public let title: String
    public let url: String
    public let snippet: String

    public init(title: String, url: String, snippet: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

// MARK: - AskUserQuestion Tool Result

public struct AskUserQuestionResult: Equatable, Sendable {
    public let questions: [QuestionItem]
    public let answers: [String: String]

    public init(questions: [QuestionItem], answers: [String: String]) {
        self.questions = questions
        self.answers = answers
    }
}

public struct QuestionItem: Equatable, Sendable {
    public let question: String
    public let header: String?
    public let options: [QuestionOption]

    public init(question: String, header: String?, options: [QuestionOption]) {
        self.question = question
        self.header = header
        self.options = options
    }
}

public struct QuestionOption: Equatable, Sendable {
    public let label: String
    public let description: String?

    public init(label: String, description: String?) {
        self.label = label
        self.description = description
    }
}

// MARK: - BashOutput Tool Result

public struct BashOutputResult: Equatable, Sendable {
    public let shellId: String
    public let status: String
    public let stdout: String
    public let stderr: String
    public let stdoutLines: Int
    public let stderrLines: Int
    public let exitCode: Int?
    public let command: String?
    public let timestamp: String?

    public init(shellId: String, status: String, stdout: String, stderr: String, stdoutLines: Int, stderrLines: Int, exitCode: Int?, command: String?, timestamp: String?) {
        self.shellId = shellId
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.stdoutLines = stdoutLines
        self.stderrLines = stderrLines
        self.exitCode = exitCode
        self.command = command
        self.timestamp = timestamp
    }
}

// MARK: - KillShell Tool Result

public struct KillShellResult: Equatable, Sendable {
    public let shellId: String
    public let message: String

    public init(shellId: String, message: String) {
        self.shellId = shellId
        self.message = message
    }
}

// MARK: - ExitPlanMode Tool Result

public struct ExitPlanModeResult: Equatable, Sendable {
    public let filePath: String?
    public let plan: String?
    public let isAgent: Bool

    public init(filePath: String?, plan: String?, isAgent: Bool) {
        self.filePath = filePath
        self.plan = plan
        self.isAgent = isAgent
    }
}

// MARK: - MCP Tool Result (Generic)

public struct MCPResult: Equatable, @unchecked Sendable {
    public let serverName: String
    public let toolName: String
    public let rawResult: [String: Any]

    public init(serverName: String, toolName: String, rawResult: [String: Any]) {
        self.serverName = serverName
        self.toolName = toolName
        self.rawResult = rawResult
    }

    public static func == (lhs: MCPResult, rhs: MCPResult) -> Bool {
        lhs.serverName == rhs.serverName &&
        lhs.toolName == rhs.toolName &&
        NSDictionary(dictionary: lhs.rawResult).isEqual(to: rhs.rawResult)
    }
}

// MARK: - Generic Tool Result (Fallback)

public struct GenericResult: Equatable, @unchecked Sendable {
    public let rawContent: String?
    public let rawData: [String: Any]?

    public init(rawContent: String?, rawData: [String: Any]?) {
        self.rawContent = rawContent
        self.rawData = rawData
    }

    public static func == (lhs: GenericResult, rhs: GenericResult) -> Bool {
        lhs.rawContent == rhs.rawContent
    }
}

// MARK: - Tool Status Display

public struct ToolStatusDisplay: Sendable {
    public let text: String
    public let isRunning: Bool

    public init(text: String, isRunning: Bool) {
        self.text = text
        self.isRunning = isRunning
    }

    /// Get running status text for a tool
    public static func running(for toolName: String, input: [String: String]) -> ToolStatusDisplay {
        switch toolName {
        case "Read":
            return ToolStatusDisplay(text: "Reading...", isRunning: true)
        case "Edit":
            return ToolStatusDisplay(text: "Editing...", isRunning: true)
        case "Write":
            return ToolStatusDisplay(text: "Writing...", isRunning: true)
        case "Bash":
            if let desc = input["description"], !desc.isEmpty {
                return ToolStatusDisplay(text: desc, isRunning: true)
            }
            return ToolStatusDisplay(text: "Running...", isRunning: true)
        case "Grep", "Glob":
            if let pattern = input["pattern"] {
                return ToolStatusDisplay(text: "Searching: \(pattern)", isRunning: true)
            }
            return ToolStatusDisplay(text: "Searching...", isRunning: true)
        case "WebSearch":
            if let query = input["query"] {
                return ToolStatusDisplay(text: "Searching: \(query)", isRunning: true)
            }
            return ToolStatusDisplay(text: "Searching...", isRunning: true)
        case "WebFetch":
            return ToolStatusDisplay(text: "Fetching...", isRunning: true)
        case "Task":
            if let desc = input["description"], !desc.isEmpty {
                return ToolStatusDisplay(text: desc, isRunning: true)
            }
            return ToolStatusDisplay(text: "Running agent...", isRunning: true)
        case "TodoWrite":
            return ToolStatusDisplay(text: "Updating todos...", isRunning: true)
        case "EnterPlanMode":
            return ToolStatusDisplay(text: "Entering plan mode...", isRunning: true)
        case "ExitPlanMode":
            return ToolStatusDisplay(text: "Exiting plan mode...", isRunning: true)
        default:
            return ToolStatusDisplay(text: "Running...", isRunning: true)
        }
    }

    /// Get completed status text for a tool result
    public static func completed(for toolName: String, result: ToolResultData?) -> ToolStatusDisplay {
        guard let result = result else {
            return ToolStatusDisplay(text: "Completed", isRunning: false)
        }

        switch result {
        case .read(let r):
            let lineText = r.totalLines > r.numLines ? "\(r.numLines)+ lines" : "\(r.numLines) lines"
            return ToolStatusDisplay(text: "Read \(r.filename) (\(lineText))", isRunning: false)

        case .edit(let r):
            return ToolStatusDisplay(text: "Edited \(r.filename)", isRunning: false)

        case .write(let r):
            let action = r.type == .create ? "Created" : "Wrote"
            return ToolStatusDisplay(text: "\(action) \(r.filename)", isRunning: false)

        case .bash(let r):
            if let bgId = r.backgroundTaskId {
                return ToolStatusDisplay(text: "Running in background (\(bgId))", isRunning: false)
            }
            if let interpretation = r.returnCodeInterpretation {
                return ToolStatusDisplay(text: interpretation, isRunning: false)
            }
            return ToolStatusDisplay(text: "Completed", isRunning: false)

        case .grep(let r):
            let fileWord = r.numFiles == 1 ? "file" : "files"
            return ToolStatusDisplay(text: "Found \(r.numFiles) \(fileWord)", isRunning: false)

        case .glob(let r):
            let fileWord = r.numFiles == 1 ? "file" : "files"
            if r.numFiles == 0 {
                return ToolStatusDisplay(text: "No files found", isRunning: false)
            }
            return ToolStatusDisplay(text: "Found \(r.numFiles) \(fileWord)", isRunning: false)

        case .todoWrite:
            return ToolStatusDisplay(text: "Updated todos", isRunning: false)

        case .task(let r):
            return ToolStatusDisplay(text: r.status.capitalized, isRunning: false)

        case .webFetch(let r):
            return ToolStatusDisplay(text: "\(r.code) \(r.codeText)", isRunning: false)

        case .webSearch(let r):
            let time = r.durationSeconds >= 1 ?
                "\(Int(r.durationSeconds))s" :
                "\(Int(r.durationSeconds * 1000))ms"
            let searchWord = r.results.count == 1 ? "search" : "searches"
            return ToolStatusDisplay(text: "Did 1 \(searchWord) in \(time)", isRunning: false)

        case .askUserQuestion:
            return ToolStatusDisplay(text: "Answered", isRunning: false)

        case .bashOutput(let r):
            return ToolStatusDisplay(text: "Status: \(r.status)", isRunning: false)

        case .killShell:
            return ToolStatusDisplay(text: "Terminated", isRunning: false)

        case .exitPlanMode:
            return ToolStatusDisplay(text: "Plan ready", isRunning: false)

        case .mcp:
            return ToolStatusDisplay(text: "Completed", isRunning: false)

        case .generic:
            return ToolStatusDisplay(text: "Completed", isRunning: false)
        }
    }
}
