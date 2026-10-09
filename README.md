# freewind-traffic-monitor

macOS 菜单栏流量监控工具，用于定位本机哪些进程在偷偷消耗流量。

## 目标

- 实时显示上传 / 下载速率
- 按进程统计某时间段（今天、近 N 天、自定义区间）的上传、下载与总流量
- 支持按任意列排序，快速找出流量大户
- 默认忽略代理进程（如 verge-mihomo）

## 实现方式

- 每 5 秒调用系统自带 `nettop -l 1 -P -x -J bytes_in,bytes_out -n` 取全表快照
- 对同一进程做累计差值，得到区间流量
- SQLite 持久化采样结果，支持按天聚合回溯

无需开发者签名、无需系统扩展、无需 root。

## 已知限制

- 走代理端口（127.0.0.1 本地代理）的流量在 nettop 中记在代理进程名下，看不到真实发起进程
- 走 TUN 模式的流量会被双计（真实进程 + 代理进程各记一次）
- 进程退出后 nettop 与 ps 都不再显示其条目，因此命令行信息必须在采样当时保存，无法事后补算
- 升级到带细分功能的版本之前，已入库的历史数据只能是聚合后的进程名，无法还原到具体脚本

## 界面

- 菜单栏显示实时速率（如 `↓1.2 MB/s ↑340 KB/s`），每 5 秒刷新
- 点击菜单栏图标可打开主窗口
- 主窗口默认按进程名聚合（`node` 只有一行），点行首箭头可展开树状明细，看到具体脚本与启动者（如 `tsserver.js ← zed`）
- 每行显示 PID 与运行状态（运行中 / 已退出），便于区分历史进程与当前正在跑的进程
- 单击行内任意位置（包含文字上）都会选中该行；文字可拖选，⌘C 复制拖选的文字
- 行右键菜单可「复制命令」「复制整行」「结束进程」（结束需确认，已退出的进程该项禁用；只能结束当前用户有权限的进程）
- 工具栏提供「复制选中」（⇧⌘C）与「复制全部（含展开明细）」，粘贴出来是制表符分隔的表格
- 区间支持今天、近 7 天、自定义日期
- 默认隐藏代理进程（`verge-mihomo`、`clash-verge`、`clash`、`mihomo`），可用“忽略代理进程”开关关掉

## 环境变量

| 变量 | 作用 |
|---|---|
| `TM_INTERVAL` | 采样间隔秒数，默认 5 |
| `TM_OPEN_WINDOW` | 设为 1 时启动即打开主窗口 |

## 运行

```bash
swift run
```

或构建 .app：

```bash
./swift-compile-build.fish
```

## 测试

```bash
swift test
```

## 安装与开机自启

```bash
fish scripts/install-autostart.fish
```

该脚本会构建 .app、安装到 `~/Applications/freewind-traffic-monitor.app`、
写入 `~/Library/LaunchAgents/com.freewind.traffic-monitor.plist` 并注册登录自启。

取消安装与自启：

```bash
fish scripts/uninstall-autostart.fish
```
