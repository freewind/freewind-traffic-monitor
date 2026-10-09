import Foundation

/// 代理进程过滤。
///
/// 经本地代理或 TUN 的流量会在 nettop 中同时记到代理进程名下，
/// 查看排行时默认应当排除，否则代理进程会长期占据榜首。
public enum ProxyProcessFilter {
    public static let defaultIgnoredNames: Set<String> = [
        "verge-mihomo",
        "clash-verge",
        "clash",
        "mihomo",
    ]

    public static func visible(
        _ rows: [ProcessTotal],
        ignoring names: Set<String> = defaultIgnoredNames,
        enabled: Bool = true
    ) -> [ProcessTotal] {
        guard enabled else {
            return rows
        }
        return rows.filter { !names.contains($0.name) }
    }
}
