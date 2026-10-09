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
- 进程退出后 nettop 不再显示其条目，须由本工具在退出前落库

## 界面

- 菜单栏显示实时速率（如 `↓1.2 MB/s ↑340 KB/s`），每 5 秒刷新
- 点击菜单栏图标可打开主窗口
- 主窗口按进程列出上传、下载、总计，点击列标题即可切换排序
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
