import Foundation

/// 从命令行推导进程的可读标识。
///
/// nettop 只能给出进程名，而一台机器上可能有上百个 `node` 进程。
/// 这里从命令行里找出真正执行的脚本，把标识细分成 `node · tsserver.js` 这样的形式，
/// 使排行能区分是哪个脚本在消耗流量。
public enum ProcessIdentity {
    /// 语言运行时/解释器的名字：它们的命令行里第二段才是真正的脚本。
    private static let interpreters: Set<String> = [
        "node", "nodejs", "bun", "deno", "python", "python3", "ruby", "perl", "php", "ts-node", "tsx",
    ]

    /// 这些文件名本身不具区分度，需要借上一层目录名。
    private static let genericFileNames: Set<String> = [
        "index.js", "main.js", "cli.js", "server.js", "app.js",
        "index.mjs", "main.mjs", "index.cjs", "main.cjs", "index.ts", "main.ts",
    ]

    /// 这些目录名同样不具区分度，需要继续向上找。
    private static let genericDirectoryNames: Set<String> = [
        "dist", "build", "out", "lib", "libs", "bin", "src", "esm", "cjs", "release", "binaries",
    ]

    public static func name(from command: String) -> String {
        guard let executable = tokens(of: command).first else {
            return ""
        }
        return (executable as NSString).lastPathComponent
    }

    /// 显示标识：解释器加脚本名，普通程序保持原名。
    public static func label(name: String, command: String) -> String {
        guard interpreters.contains(name.lowercased()) else {
            return name
        }

        // 有些进程会改写 argv[0]（如 Next.js 把首段写成 `next-server (v16.3.8)`），
        // 这时首段的基名才是真正的身份，比不确定的脚本参数更可靠。
        let argv0 = ProcessIdentity.name(from: command)
        if !argv0.isEmpty, argv0.lowercased() != name.lowercased() {
            return "\(name) · \(truncated(argv0))"
        }

        guard let script = scriptArgument(in: command),
              let distinguishing = distinguishingName(forScriptPath: script) else {
            return name
        }
        return "\(name) · \(truncated(distinguishing))"
    }

    /// 脚本名上限，避免很长的 chunk 文件名把界面撑爆。
    static let maxDetailLength = 32

    static func truncated(_ value: String) -> String {
        guard value.count > maxDetailLength else {
            return value
        }
        return String(value.prefix(maxDetailLength - 1)) + "…"
    }

    /// 取第一个不以 `-` 开头的参数，即脚本或子命令路径。
    static func scriptArgument(in command: String) -> String? {
        for (index, token) in tokens(of: command).enumerated() where index > 0 {
            guard !token.hasPrefix("-"), !token.hasPrefix("\""), !token.hasPrefix("'") else {
                continue
            }
            return token
        }
        return nil
    }

    /// 用文件名或最近的具区分度目录名来标识脚本。
    static func distinguishingName(forScriptPath path: String) -> String? {
        let fileName = (path as NSString).lastPathComponent
        guard !fileName.isEmpty else {
            return nil
        }

        if !genericFileNames.contains(fileName.lowercased()) {
            return fileName
        }

        var directory = (path as NSString).deletingLastPathComponent
        while !directory.isEmpty, directory != "/", directory != "." {
            let name = (directory as NSString).lastPathComponent
            if !genericDirectoryNames.contains(name.lowercased()) {
                return name
            }
            directory = (directory as NSString).deletingLastPathComponent
        }

        return fileName
    }

    private static func tokens(of command: String) -> [String] {
        command.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    }
}
