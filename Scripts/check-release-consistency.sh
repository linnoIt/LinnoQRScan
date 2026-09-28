#!/usr/bin/env bash
#
# check-release-consistency.sh —— 校验 CocoaPods 与 SPM 两条渠道的版本自洽性
#
# 用法：
#   Scripts/check-release-consistency.sh --worktree   # 发版前预检（读工作区文件，提交前就能查）
#   Scripts/check-release-consistency.sh              # 发版终检（校验最新 tag）
#   Scripts/check-release-consistency.sh 0.2.7        # 校验指定 tag
#
# 为什么需要它：
#   两条渠道共用同一个 git tag —— SPM 从 tag 读版本，podspec 的 :tag => s.version 也指向它。
#   只要「tag 名 == podspec 版本 == Package.swift 所在提交」三者对齐，
#   「同一个版本号 = 同一份代码」就永远成立。任何一边单独改动都会被这里拦下。
#
# 注意：本机 /bin/bash 是 3.2，变量后紧跟中文字符时必须写 ${VAR}，否则会误解析变量名。

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

PODSPEC="LinnoQRScan.podspec"
WORKTREE=0
REF=""

case "${1:-}" in
  ""|--worktree)
    if [ "${1:-}" = "--worktree" ]; then
      WORKTREE=1
    else
      REF="$(git describe --tags --abbrev=0)"
    fi
    ;;
  *)
    REF="$1"
    ;;
esac

pass=0
fail=0
ok()   { printf '  ✅ %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  ❌ %s\n' "$1"; fail=$((fail + 1)); }
skip() { printf '  ➖ %s\n' "$1"; }
finish() {
  echo
  if [ "${fail}" -eq 0 ]; then
    echo "结果：${pass} 项通过，版本自洽 ✅"
  else
    echo "结果：${pass} 项通过 / ${fail} 项失败 ❌"
    exit 1
  fi
}

# ============ 读取两种模式下的文件内容 ============
if [ "${WORKTREE}" = 1 ]; then
  echo "校验对象：工作区（未提交改动也会被检查）"
  echo
  [ -f "${PODSPEC}" ] || { echo "  ❌ 工作区里找不到 ${PODSPEC}"; exit 1; }
  [ -f "Package.swift" ] || { echo "  ❌ 工作区里找不到 Package.swift"; exit 1; }
  PODSPEC_TEXT=$(cat "${PODSPEC}")
  PKG_TEXT=$(cat "Package.swift")
  IS_TAG=0
else
  echo "校验对象：${REF}（${PODSPEC} + Package.swift）"
  echo
  if ! git rev-parse -q --verify "${REF}^{commit}" >/dev/null; then
    echo "  ❌ ref 不存在：${REF}"
    exit 1
  fi
  IS_TAG=0
  if git rev-parse -q --verify "refs/tags/${REF}" >/dev/null; then IS_TAG=1; fi
  COMMIT=$(git rev-parse --short "${REF}^{commit}")
  if [ "${IS_TAG}" = 1 ]; then
    echo "提交：${COMMIT}（tag）"
  else
    echo "提交：${COMMIT}（非 tag）"
  fi
  echo

  # ---- 两个包文件都必须在这个版本里（缺一个就直接收工，避免后面 git show 抛 fatal）----
  MISSING=0
  if git cat-file -e "${REF}:Package.swift" 2>/dev/null; then
    ok "Package.swift 存在（SPM 可拉取）"
  else
    bad "Package.swift 不存在 —— 该版本无法被 SPM 拉取"
    MISSING=1
  fi
  if git cat-file -e "${REF}:${PODSPEC}" 2>/dev/null; then
    ok "${PODSPEC} 存在"
  else
    bad "${PODSPEC} 不存在"
    MISSING=1
  fi
  if [ "${MISSING}" = 1 ]; then
    finish
  fi

  PODSPEC_TEXT=$(git show "${REF}:${PODSPEC}")
  PKG_TEXT=$(git show "${REF}:Package.swift")
fi

# ============ 提取版本与关键声明 ============
POD_VERSION=$(printf '%s\n' "${PODSPEC_TEXT}" \
  | grep -E "^[[:space:]]*s\.version" | head -1 \
  | sed -E "s/.*=[[:space:]]*'([^']+)'.*/\1/")
POD_DEPLOY=$(printf '%s\n' "${PODSPEC_TEXT}" \
  | grep -E "^[[:space:]]*s\.ios\.deployment_target" | head -1 \
  | sed -E "s/.*=[[:space:]]*'([^']+)'.*/\1/")
POD_NAME=$(printf '%s\n' "${PODSPEC_TEXT}" \
  | grep -E "^[[:space:]]*s\.name" | head -1 \
  | sed -E "s/.*=[[:space:]]*'([^']+)'.*/\1/")
PKG_NAME=$(printf '%s\n' "${PKG_TEXT}" \
  | grep -E 'name:[[:space:]]*"' | head -1 \
  | sed -E 's/.*"([^"]+)".*/\1/')
PKG_IOS=$(printf '%s\n' "${PKG_TEXT}" \
  | grep -E '\.iOS\(\.v[0-9]+' | head -1 \
  | sed -E 's/.*\.v([0-9]+).*/\1/')

echo
echo "  podspec 版本 = ${POD_VERSION:-未取到} | 模块名 = ${POD_NAME:-未取到} | 部署目标 = iOS ${POD_DEPLOY:-未取到}"
echo "  Package  名称 = ${PKG_NAME:-未取到} | 平台 = iOS ${PKG_IOS:-未取到}"
echo

# ============ 1. tag 名必须等于 podspec 版本 ============
if [ "${WORKTREE}" = 1 ]; then
  skip "工作区模式，跳过「tag 名 = podspec 版本」"
elif [ "${IS_TAG}" = 1 ]; then
  if [ "${REF}" = "${POD_VERSION}" ]; then
    ok "tag 名与 podspec 版本一致（${REF}）"
  else
    bad "tag 名（${REF}）不等于 podspec 版本（${POD_VERSION}）—— 两条渠道会解析到不同版本"
  fi
else
  skip "非 tag，跳过「tag 名 = podspec 版本」"
fi

# ============ 2. podspec 的 source tag 指向自己 ============
if printf '%s\n' "${PODSPEC_TEXT}" | grep -E "^[[:space:]]*s\.source" | grep -q "s\.version\.to_s"; then
  ok "podspec 的 :tag => s.version.to_s（与 SPM 共用同一 tag）"
else
  bad "podspec 的 s.source 未使用 s.version.to_s —— 可能与 SPM 的 tag 不一致"
fi

# ============ 3. 模块名一致（消费者 import 的名字）===========
if [ "${POD_NAME}" = "${PKG_NAME}" ]; then
  ok "模块名一致（${POD_NAME}）"
else
  bad "模块名不一致：podspec=${POD_NAME} vs Package=${PKG_NAME} —— 两边 import 的名字会不同"
fi

# ============ 4. 最低部署目标一致 ============
NORM_DEPLOY=$(printf '%s' "${POD_DEPLOY}" | sed -E 's/^([0-9]+)\..*/\1/')
if [ "${NORM_DEPLOY}" = "${PKG_IOS}" ]; then
  ok "最低部署目标一致（iOS ${POD_DEPLOY}）"
else
  bad "最低部署目标不一致：podspec=iOS ${POD_DEPLOY} vs Package=iOS ${PKG_IOS}"
fi

finish
