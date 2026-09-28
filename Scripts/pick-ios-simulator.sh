#!/usr/bin/env bash
#
# 挑选一个当前环境可用的 iPhone 模拟器，输出可直接喂给 xcodebuild 的 -destination 参数。
#
# 为什么需要它：
#   CI runner 镜像里的模拟器机型与系统版本会随 Xcode 版本变化，硬编码
#   "platform=iOS Simulator,name=iPhone 15,OS=18.0" 迟早报
#   "Unable to find a device matching the provided destination specifier"。
#   改为运行时探测，镜像升级后 CI 不会因此变红。
#
# 输出（stdout，单行）：platform=iOS Simulator,id=<UDID>
# 所有诊断信息写 stderr，避免污染 stdout。
#
# 用法：
#   xcodebuild test -scheme XXX -destination "$(Scripts/pick-ios-simulator.sh)"

set -euo pipefail

# 找 python3：PATH 优先，其次兜底的系统路径
PY=""
if command -v python3 >/dev/null 2>&1; then
  PY="$(command -v python3)"
elif [ -x /usr/bin/python3 ]; then
  PY="/usr/bin/python3"
fi

if [ -z "$PY" ]; then
  echo "错误：找不到 python3，无法解析模拟器列表。" >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "错误：找不到 xcrun（需要安装 Xcode 命令行工具）。" >&2
  exit 1
fi

DEST="$(
  xcrun simctl list devices available -j | "$PY" -c '
import json, sys

devices = json.load(sys.stdin)["devices"]

# runtime key 形如 com.apple.CoreSimulator.SimRuntime.iOS-26-0
# 字符串反序排 ≈ 系统版本由新到旧；取最新的一个可用 iPhone。
for runtime in sorted(devices, reverse=True):
    if "SimRuntime.iOS-" not in runtime:
        continue
    for device in devices[runtime]:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            print("platform=iOS Simulator,id=%s" % device["udid"])
            raise SystemExit(0)
'
)"

if [ -z "$DEST" ]; then
  echo "错误：没有找到任何可用的 iPhone 模拟器。" >&2
  echo "当前可用设备如下：" >&2
  xcrun simctl list devices available >&2 || true
  exit 1
fi

echo "已选择模拟器：$DEST" >&2
printf '%s\n' "$DEST"
