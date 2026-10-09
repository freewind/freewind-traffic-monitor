import AppKit
import SwiftUI
import TrafficMonitorCore

/// 自定义进程列表。
///
/// 不用系统 `Table` 的原因：macOS 的 Table 不支持单元格内选字，也做不了树形缩进，
/// 而这里需要「默认聚合、点开展开分支」以及「文字可选中复制」。
struct ProcessTableView: View {
    @ObservedObject var model: TrafficViewModel
    @State private var sortField: SortField = .total
    @State private var ascending = false
    @State private var killRequest: KillRequest?

    struct KillRequest: Identifiable {
        let id = UUID()
        let title: String
        let pids: [Int32]
    }

    enum SortField: String, CaseIterable {
        case name
        case parent
        case bytesIn
        case bytesOut
        case total

        var title: String {
            switch self {
            case .name: return "进程"
            case .parent: return "启动者"
            case .bytesIn: return "上传"
            case .bytesOut: return "下载"
            case .total: return "总计"
            }
        }

        var width: CGFloat {
            switch self {
            case .name: return 230
            case .parent: return 100
            case .bytesIn, .bytesOut, .total: return 90
            }
        }

        var alignment: Alignment {
            switch self {
            case .bytesIn, .bytesOut, .total: return .trailing
            default: return .leading
            }
        }
    }

    private let indentWidth: CGFloat = 18
    private let pidWidth: CGFloat = 110
    private let statusWidth: CGFloat = 84

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedGroups) { group in
                        groupRow(group)

                        if model.isExpanded(group) {
                            ForEach(group.children.sorted { $0.total > $1.total }) { child in
                                childRow(group: group, child: child)
                            }
                        }
                    }
                }
            }
            .textSelection(.enabled)
        }
        .alert("结束进程", isPresented: killAlertBinding, presenting: killRequest) { request in
            Button("结束", role: .destructive) {
                model.terminate(pids: request.pids)
                killRequest = nil
            }
            Button("取消", role: .cancel) {
                killRequest = nil
            }
        } message: { request in
            Text("\(request.title)\n将结束 \(request.pids.count) 个进程：\(request.pids.map(String.init).joined(separator: ", "))")
        }
    }

    private var killAlertBinding: Binding<Bool> {
        Binding(
            get: { killRequest != nil },
            set: { if !$0 { killRequest = nil } }
        )
    }

    private var sortedGroups: [ProcessGroup] {
        model.visibleGroups.sorted { lhs, rhs in
            switch compare(lhs, rhs) {
            case .orderedSame:
                return false
            case .orderedAscending:
                return ascending
            case .orderedDescending:
                return !ascending
            }
        }
    }

    private func compare(_ lhs: ProcessGroup, _ rhs: ProcessGroup) -> ComparisonResult {
        switch sortField {
        case .name, .parent:
            return lhs.name.localizedStandardCompare(rhs.name)
        case .bytesIn:
            return compareValues(lhs.bytesIn, rhs.bytesIn)
        case .bytesOut:
            return compareValues(lhs.bytesOut, rhs.bytesOut)
        case .total:
            return compareValues(lhs.total, rhs.total)
        }
    }

    private func compareValues(_ lhs: UInt64, _ rhs: UInt64) -> ComparisonResult {
        if lhs == rhs {
            return .orderedSame
        }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    private var header: some View {
        HStack(spacing: 0) {
            ForEach(SortField.allCases, id: \.self) { field in
                Button {
                    if sortField == field {
                        ascending.toggle()
                    } else {
                        sortField = field
                        ascending = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        if field.alignment == .trailing {
                            Spacer(minLength: 0)
                        }
                        Text(field.title)
                            .font(.callout.weight(.semibold))
                        if sortField == field {
                            Image(systemName: ascending ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                        if field.alignment != .trailing {
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(width: field.width, alignment: field.alignment)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text("PID")
                .font(.callout.weight(.semibold))
                .frame(width: pidWidth, alignment: .leading)

            Text("状态")
                .font(.callout.weight(.semibold))
                .frame(width: statusWidth, alignment: .leading)

            Text("命令")
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func groupRow(_ group: ProcessGroup) -> some View {
        let id = group.name
        let runningPIDs = group.children
            .filter { $0.isRunning(activePIDs: model.activePIDs) }
            .flatMap(\.pids)

        return rowContent(
            selected: model.selectedRowID == id,
            expandable: group.isExpandable,
            expanded: model.isExpanded(group),
            onToggle: { model.toggleExpansion(group) },
            name: group.name,
            nameWeight: .semibold,
            parent: "",
            pidText: group.pidSummaryText,
            statusText: group.statusText(activePIDs: model.activePIDs),
            isRunning: !runningPIDs.isEmpty,
            bytesIn: group.bytesIn,
            bytesOut: group.bytesOut,
            total: group.total,
            command: group.summaryCommand
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                model.select(
                    id: id,
                    text: ProcessRowFormatter.text(for: group, activePIDs: model.activePIDs)
                )
            }
        )
        .contextMenu {
            Button("复制命令") { model.copyCommand(of: group) }
            Button("复制整行") {
                model.copyRow(ProcessRowFormatter.text(for: group, activePIDs: model.activePIDs))
            }
            Divider()
            Button("结束进程") {
                killRequest = KillRequest(title: "进程：\(group.name)", pids: runningPIDs)
            }
            .disabled(runningPIDs.isEmpty)
        }
    }

    private func childRow(group: ProcessGroup, child: ProcessBreakdown) -> some View {
        let id = group.name + "\u{1}" + child.id
        let isRunning = child.isRunning(activePIDs: model.activePIDs)

        return rowContent(
            selected: model.selectedRowID == id,
            expandable: false,
            expanded: false,
            onToggle: {},
            name: child.scriptName,
            nameWeight: .regular,
            parent: child.parent,
            pidText: child.pidText,
            statusText: child.statusText(activePIDs: model.activePIDs),
            isRunning: isRunning,
            bytesIn: child.bytesIn,
            bytesOut: child.bytesOut,
            total: child.total,
            command: child.command,
            indent: indentWidth
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                model.select(
                    id: id,
                    text: ProcessRowFormatter.text(for: child, activePIDs: model.activePIDs)
                )
            }
        )
        .contextMenu {
            Button("复制命令") { model.copy(child.command) }
            Button("复制整行") {
                model.copyRow(ProcessRowFormatter.text(for: child, activePIDs: model.activePIDs))
            }
            Divider()
            Button("结束进程") {
                killRequest = KillRequest(title: "脚本：\(child.scriptName)", pids: child.pids)
            }
            .disabled(!isRunning)
        }
    }

    private func rowContent(
        selected: Bool,
        expandable: Bool,
        expanded: Bool,
        onToggle: @escaping () -> Void,
        name: String,
        nameWeight: Font.Weight,
        parent: String,
        pidText: String,
        statusText: String,
        isRunning: Bool,
        bytesIn: UInt64,
        bytesOut: UInt64,
        total: UInt64,
        command: String,
        indent: CGFloat = 0
    ) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                if expandable {
                    Button(action: onToggle) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .frame(width: 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 14)
                }

                Text(name)
                    .fontWeight(nameWeight)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.leading, indent)
            .frame(width: SortField.name.width - indent, alignment: .leading)

            Text(parent)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: SortField.parent.width, alignment: .leading)

            Text(pidText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: pidWidth, alignment: .leading)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(isRunning ? Color.green : Color.secondary)
                .lineLimit(1)
                .frame(width: statusWidth, alignment: .leading)

            Text(ByteFormat.size(bytesIn))
                .monospacedDigit()
                .frame(width: SortField.bytesIn.width, alignment: .trailing)

            Text(ByteFormat.size(bytesOut))
                .monospacedDigit()
                .frame(width: SortField.bytesOut.width, alignment: .trailing)

            Text(ByteFormat.size(total))
                .monospacedDigit()
                .frame(width: SortField.total.width, alignment: .trailing)

            Text(command)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(command)
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
    }
}
