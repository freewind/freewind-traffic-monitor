#!/usr/bin/env fish

# 构建 .app、安装到 ~/Applications，并注册登录自启的 LaunchAgent。

set -l script_dir (realpath (dirname (status filename)))
set -l root (realpath $script_dir/..)
set -l app_name freewind-traffic-monitor
set -l label com.freewind.traffic-monitor
set -l install_dir $HOME/Applications
set -l installed_app $install_dir/$app_name.app
set -l plist $HOME/Library/LaunchAgents/$label.plist
set -l log_path $HOME/Library/Logs/freewind-traffic-monitor.log
set -l template $root/autostart/$label.plist.template

test -f $template; or begin
    echo "缺少模板: $template" >&2
    exit 1
end

cd $root; or exit 1

echo "==> 构建 $app_name"
env ROOT_DIR=$root fish $root/swift-compile-build.fish >/dev/null
or begin
    echo "构建失败" >&2
    exit 1
end

set -l built $root/build/$app_name.app
test -d $built; or begin
    echo "缺少构建产物: $built" >&2
    exit 1
end

echo "==> 安装到 $installed_app"
mkdir -p $install_dir
rm -rf $installed_app
cp -R $built $installed_app

set -l executable $installed_app/Contents/MacOS/$app_name
test -x $executable; or begin
    echo "缺少可执行文件: $executable" >&2
    exit 1
end

echo "==> 写入 $plist"
mkdir -p (dirname $plist)
sed -e "s|__LABEL__|$label|g" -e "s|__EXECUTABLE__|$executable|g" -e "s|__LOG__|$log_path|g" $template > $plist

echo "==> 注册自启"
launchctl bootout gui/(id -u) $plist 2>/dev/null
launchctl bootstrap gui/(id -u) $plist
or begin
    echo "launchctl bootstrap 失败" >&2
    exit 1
end

echo "完成。App: $installed_app"
echo "自启配置: $plist"
echo "日志: $log_path"
