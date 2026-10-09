import SwiftUI
import TrafficMonitorCore

struct ContentView: View {
    @ObservedObject var model: TrafficViewModel
    @State private var sortOrder: [KeyPathComparator<ProcessTotal>] = ProcessTotal.defaultSortOrder

    private var sortedRows: [ProcessTotal] {
        model.visibleRows.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            table
            Divider()
            footer
        }
        .frame(minWidth: 680, minHeight: 420)
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

                Button("刷新") {
                    model.refresh()
                }
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

    private var table: some View {
        Table(sortedRows, sortOrder: $sortOrder) {
            TableColumn("进程", value: \.name)
                .width(min: 160, ideal: 220)

            TableColumn("上传", value: \.bytesIn) { row in
                Text(ByteFormat.size(row.bytesIn))
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)

            TableColumn("下载", value: \.bytesOut) { row in
                Text(ByteFormat.size(row.bytesOut))
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)

            TableColumn("总计", value: \.total) { row in
                Text(ByteFormat.size(row.total))
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let lastError = model.lastError {
                Text(lastError)
                    .foregroundStyle(.red)
            } else {
                Text("共 \(sortedRows.count) 个进程")
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
