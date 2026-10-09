#!/usr/bin/env fish

# 取消登录自启并删除已安装的 .app。

set -l app_name freewind-traffic-monitor
set -l label com.freewind.traffic-monitor
set -l installed_app $HOME/Applications/$app_name.app
set -l plist $HOME/Library/LaunchAgents/$label.plist

if test -f $plist
    echo "==> 取消自启 $label"
    launchctl bootout gui/(id -u) $plist 2>/dev/null
    rm -f $plist
end

if test -d $installed_app
    echo "==> 删除 $installed_app"
    rm -rf $installed_app
end

pkill -f "$installed_app/Contents/MacOS/$app_name" 2>/dev/null

echo "完成。"
