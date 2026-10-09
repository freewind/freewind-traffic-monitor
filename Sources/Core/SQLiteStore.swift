import Foundation
import SQLite3

/// 采样结果的持久化存储（系统自带 SQLite，无第三方依赖）。
public final class SQLiteStore {
    public enum StoreError: Error, CustomStringConvertible {
        case openFailed(String)
        case executeFailed(String)
        case prepareFailed(String)

        public var description: String {
            switch self {
            case .openFailed(let message): return "打开数据库失败: \(message)"
            case .executeFailed(let message): return "执行 SQL 失败: \(message)"
            case .prepareFailed(let message): return "准备 SQL 失败: \(message)"
            }
        }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var db: OpaquePointer?

    public init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            throw StoreError.openFailed(message)
        }

        db = handle
        try execute(
            """
            CREATE TABLE IF NOT EXISTS traffic (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts INTEGER NOT NULL,
                name TEXT NOT NULL,
                pid INTEGER NOT NULL,
                bytes_in INTEGER NOT NULL,
                bytes_out INTEGER NOT NULL
            );
            """
        )
        try execute("CREATE INDEX IF NOT EXISTS idx_traffic_ts ON traffic (ts);")
        try execute("CREATE INDEX IF NOT EXISTS idx_traffic_name ON traffic (name);")
    }

    deinit {
        sqlite3_close(db)
    }

    /// 应用支持目录下的默认数据库路径。
    public static func defaultPath() throws -> String {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("freewind-traffic-monitor", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("traffic.sqlite3").path
    }

    public func record(_ deltas: [TrafficDelta]) throws {
        guard !deltas.isEmpty else {
            return
        }

        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let statement = try prepare(
                "INSERT INTO traffic (ts, name, pid, bytes_in, bytes_out) VALUES (?, ?, ?, ?, ?);"
            )
            defer { sqlite3_finalize(statement) }

            for delta in deltas {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_int64(statement, 1, delta.timestamp)
                sqlite3_bind_text(statement, 2, delta.name, -1, Self.transient)
                sqlite3_bind_int64(statement, 3, Int64(delta.pid))
                sqlite3_bind_int64(statement, 4, Int64(bitPattern: delta.bytesIn))
                sqlite3_bind_int64(statement, 5, Int64(bitPattern: delta.bytesOut))

                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw StoreError.executeFailed(lastErrorMessage())
                }
            }

            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    /// 区间内的进程流量合计，按总流量降序。
    /// 区间为左闭右开：[from, to)。
    public func totals(from: Int64, to: Int64) throws -> [ProcessTotal] {
        let statement = try prepare(
            """
            SELECT name, SUM(bytes_in), SUM(bytes_out)
            FROM traffic
            WHERE ts >= ? AND ts < ?
            GROUP BY name
            ORDER BY SUM(bytes_in) + SUM(bytes_out) DESC;
            """
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, from)
        sqlite3_bind_int64(statement, 2, to)

        var result: [ProcessTotal] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let name = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let bytesIn = UInt64(bitPattern: sqlite3_column_int64(statement, 1))
            let bytesOut = UInt64(bitPattern: sqlite3_column_int64(statement, 2))
            result.append(ProcessTotal(name: name, bytesIn: bytesIn, bytesOut: bytesOut))
        }

        return result
    }

    public func sampleCount() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM traffic;")
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int64(statement, 0))
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage()
            sqlite3_free(errorMessage)
            throw StoreError.executeFailed(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StoreError.prepareFailed(lastErrorMessage())
        }
        return statement
    }

    private func lastErrorMessage() -> String {
        guard let db else {
            return "unknown"
        }
        return String(cString: sqlite3_errmsg(db))
    }
}
