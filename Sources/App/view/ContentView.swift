import SwiftUI
import TrafficMonitorCore

struct ContentView: View {
    @ObservedObject var model: TrafficViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ProcessTableView(model: model)
            Divider()
            footer
        }
        .frame(minWidth: 900, minHeight: 440)
        .onAppear { model.refresh() }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("区间", selection: $model.rangeKind) {
                    ForEach(TrafficViewModel.RangeKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                .onChange(of: model.rangeKind) { model.refresh() }

                Toggle("忽略代理进程", isOn: $model.ignoreProxyProcesses)
                    .toggleStyle(.checkbox)

                Spacer()

                Text("↓ \(ByteFormat.rate(model.downloadRate))   ↑ \(ByteFormat.rate(model.uploadRate))")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)

                Button("复制选中") { model.copySelection() }
                    .help("复制当前选中行（快捷键 ⇧⌘C；⌘C 用于复制拖选的文字）")
                    .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("复制全部") { model.copyAll() }

                Button("刷新") { model.refresh() }
            }

            if model.rangeKind == .custom {
                HStack(spacing: 8) {
                    DatePicker("从", selection: $model.customStart, displayedComponents: .date)
                    DatePicker("到", selection: $model.customEnd, displayedComponents: .date)
                    Spacer()
                }
                .onChange(of: model.customStart) { model.refresh() }
                .onChange(of: model.customEnd) { model.refresh() }
            }
        }
        .padding(12)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let actionMessage = model.actionMessage {
                Text(actionMessage)
                    .foregroundStyle(actionMessage.hasPrefix("已结束") ? Color.secondary : Color.red)
            } else if let lastError = model.lastError {
                Text(lastError)
                    .foregroundStyle(.red)
            } else {
                Text("共 \(model.visibleGroups.count) 个进程")
                if model.ignoreProxyProcesses, model.hiddenProcessCount > 0 {
                    Text("（已隐藏 \(model.hiddenProcessCount) 个代理进程）")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("上传 \(ByteFormat.size(model.totalBytesIn))   下载 \(ByteFormat.size(model.totalBytesOut))   合计 \(ByteFormat.size(model.totalBytes))")
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text(model.rangeText)
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .padding(12)
    }
}
