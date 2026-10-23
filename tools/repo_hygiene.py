#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""仓库卫生检查：隐私扫描 + 陈旧信息巡检。

用法：
    python repo_hygiene.py privacy [--repo PATH] [--allow-str S]...
    python repo_hygiene.py emails  [--repo PATH] [--allow-email-pattern RE]...
    python repo_hygiene.py stale   [--repo PATH]
    python repo_hygiene.py all     [--repo PATH]

只依赖标准库。privacy 只扫「被 git 跟踪的文件」（即真正会公开的内容）。
退出码：0 = 干净，1 = 有发现（便于接进 CI / 提交前钩子）。

⚠️ 铁律：宁可报「这个文件没扫到」，也绝不把「没扫过」当成「扫过且干净」。
   本脚本历史上两次静默漏扫，都是这个模式下藏了很久才被发现：
     ① git ls-files 对中文名路径做八进制转义，open() 失败 → 全中文文件被跳过
     ② .reg 是 UTF-16LE，含 \x00 被判二进制 → 那两个文件从未被扫
"""

import argparse
import io
import os
import re
import subprocess
import sys

# stdout 编码固定成 UTF-8：Windows 上默认 cp936，中文经管道 / 重定向后被按 UTF-8
# 解读就整段乱码（AI 抓日志时看不到中文结论）。Python 3.7+ 有 reconfigure，老版本跳过。
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

# ---------------------------------------------------------------- 规则

# 允许出现的「中性示例值」与结构性常量（不算泄漏）
DEFAULT_ALLOW = [
    "192.168.1.100",      # 示例代理地址
    "192.168.1.1",        # 网关示例
    "127.0.0.1",
    "0.0.0.0",
    "255.255.255.0",
    "172.16.*", "172.17.*", "172.18.*", "172.19.*",   # 常见的「绕过代理」通配
    "172.2", "172.30.*", "172.31.*",
    "10.*",
    "192.168.*",
    "你的用户名", "<用户名>", "%USERPROFILE%", "Users\\Administrator",
]

RULES = [
    ("私网地址",
     re.compile(r"\b(?:10|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b"),
     "换成中性示例（如 192.168.1.100）"),
    ("Tailscale/CGNAT 地址",
     re.compile(r"\b100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}\b"),
     "移除或换成示例地址"),
    ("个人邮箱",
     re.compile(r"[\w.+-]+@(?:gmail|qq|163|126|outlook|hotmail|icloud|foxmail|sina|sohu)\.com", re.I),
     "改文档（别写出来）+ 见 emails 模式处理提交者邮箱"),
    ("绝对用户路径",
     re.compile(r"[A-Za-z]:[\\/]+Users[\\/]+(?!你的用户名|<|%USERPROFILE%|<用户名>)[^\\/\s\"'`]+"
                r"|/(?:home|Users)/(?!你的用户名|<|shared\b)[a-z][\w.-]*"),
     "换成 %USERPROFILE% / <用户目录>，两种分隔符都要扫"),
    ("令牌/密钥",
     re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}"
                r"|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16})\b"),
     "立刻撤销该凭据并改写历史"),
    ("机器名",
     re.compile(r"\b(?:DESKTOP|LAPTOP)-[A-Z0-9]{7}\b"),
     "换成 <主机名>"),
    ("硬编码行号引用",
     re.compile(r"第\s*\d{2,}\s*行"),
     "改用节名做交叉引用（行号必然失效）"),
]

# 已知的二进制后缀：命中即计入「按后缀跳过」，不算漏扫。
# 这里故意**不做**「遇到 \x00 就静默当二进制」的兜底 —— 那样会重演 .reg 被整类跳过的
# 旧错。未知后缀的二进制会以「读不出文本」的形式出现在报告里，这是刻意的：
# 让你确认过「它确实是二进制」之后，再把后缀加到这里。
SKIP_SUFFIX = (".dll", ".exe", ".ico", ".png", ".jpg", ".jpeg", ".gif", ".zip",
               ".7z", ".rar", ".pdf", ".woff", ".woff2", ".ttf", ".bin", ".raw")

NOREPLY_RE = re.compile(r"(?:\d+\+)?[\w.-]+@users\.noreply\.github\.com$", re.I)


# ---------------------------------------------------------------- 工具

def run(cmd, cwd):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True)
    out = p.stdout.decode("utf-8", "replace")
    err = p.stderr.decode("utf-8", "replace")
    return p.returncode, out, err


def tracked_files(repo):
    # ★ 必须用 -z（NUL 分隔），不能用默认的换行分隔输出。
    #   默认输出会把非 ASCII 路径做 C 风格引号 + 八进制转义：
    #       "docs/\351\234\200\346\261\202.md"
    #   拿这个字符串去 open() 必然失败 → read_text 返回 None → 调用方 continue
    #   → **所有中文名文件被静默跳过**，扫描等于空跑。
    #   -z 是唯一彻底的做法：NUL 分隔 + 完全不做任何转义（比 -c core.quotepath=false
    #   更硬，后者只是关掉转义但仍然按换行切分，路径里含换行时照样错）。
    code, out, _ = run(["git", "ls-files", "-z"], repo)
    if code != 0:
        print("!! 不是 git 仓库或 git 不可用:", repo)
        sys.exit(2)
    return [f for f in out.split("\x00") if f.strip()]


def read_text(path):
    try:
        b = io.open(path, "rb").read()
    except OSError:
        return None
    # ★ 先认 BOM。Windows 用 reg export 导出的 .reg 是 UTF-16LE，
    #   旧版按「含 \x00 就是二进制」跳过 → 这类文件**从未被扫过**。
    if b[:2] in (b"\xff\xfe", b"\xfe\xff"):
        for enc in ("utf-16", "utf-16-le", "utf-16-be"):
            try:
                return b.decode(enc)
            except UnicodeDecodeError:
                continue
        return None
    if b"\x00" in b[:2048]:
        return None
    for enc in ("utf-8-sig", "gbk"):
        try:
            return b.decode(enc)
        except UnicodeDecodeError:
            continue
    return b.decode("utf-8", "replace")


# ---------------------------------------------------------------- privacy

def mode_privacy(repo, allow):
    allow = list(DEFAULT_ALLOW) + list(allow)
    hits = []
    files = tracked_files(repo)
    scanned = 0
    binary = 0
    unreadable = []
    for f in files:
        if f.lower().endswith(SKIP_SUFFIX):
            binary += 1
            continue
        p = os.path.join(repo, f)
        if not os.path.exists(p):
            # 枚举出来却在磁盘上找不到 → 路径编码/枚举环节有问题。
            # 「读不到所以没扫」和「扫过且干净」是两件事，必须分开记账。
            unreadable.append((f, "路径不存在（拿不到文件）"))
            continue
        text = read_text(p)
        if text is None:
            unreadable.append((f, "读不出文本（二进制或被占用）"))
            continue
        scanned += 1
        for lineno, line in enumerate(text.splitlines(), 1):
            if any(a and a in line for a in allow):
                # 允许项可能只覆盖一行中的一部分，仍逐规则检查剩余内容
                scrubbed = line
                for a in allow:
                    if a:
                        scrubbed = scrubbed.replace(a, " ")
                if not any(rx.search(scrubbed) for _, rx, _ in RULES):
                    continue
                target = scrubbed
            else:
                target = line
            for name, rx, fix in RULES:
                m = rx.search(target)
                if m:
                    hits.append((name, f, lineno, line.strip()[:120], fix))
    _report("被跟踪文件的隐私扫描", hits,
            files=len(files), scanned=scanned, binary=binary,
            unreadable=unreadable)
    return 0 if (not hits and not unreadable) else 1


# ---------------------------------------------------------------- emails

def mode_emails(repo, allow_pat):
    code, out, _ = run(["git", "log", "--all", "--format=%ae"], repo)
    if code != 0:
        print("!! 无法读取 git 历史")
        return 2
    emails = {}
    for e in out.splitlines():
        e = e.strip()
        if e:
            emails[e] = emails.get(e, 0) + 1
    allow = [re.compile(p, re.I) for p in allow_pat]
    bad = {e: n for e, n in emails.items()
           if not NOREPLY_RE.search(e) and not any(a.search(e) for a in allow)}
    print("=== 提交者邮箱分布（git log --all） ===")
    for e, n in sorted(emails.items(), key=lambda x: -x[1]):
        flag = "  <== 非 noreply" if e in bad else ""
        print("  %-56s %4d%s" % (e, n, flag))

    # 顺带看一眼 refs/original（filter-branch 的备份引用会包含旧邮箱）
    code2, out2, _ = run(["git", "for-each-ref", "--format=%(refname)", "refs/original"], repo)
    if out2.strip():
        print("\n注意：存在 filter-branch 备份引用（会出现在 --all 里，别误判）：")
        for r in out2.splitlines():
            print("  ", r)

    if bad:
        print("\n发现非 noreply 邮箱 —— 处理办法见 SKILL.md 第 6.2 节"
              "（git config user.email + 必要时 filter-branch 重写历史并强制推送 tag）")
    else:
        print("\n全部为 noreply / 允许的邮箱 ✅")
    return 0 if not bad else 1


# ---------------------------------------------------------------- stale

def find_version(repo):
    for cand in ("VERSION", "version.txt"):
        p = os.path.join(repo, cand)
        if os.path.isfile(p):
            t = read_text(p)
            if t:
                m = re.search(r"\d+\.\d+(?:\.\d+)?", t)
                if m:
                    return m.group(0), cand
    return None, None


def mode_stale(repo):
    version, src = find_version(repo)
    print("=== 陈旧信息巡检 ===")
    if not version:
        print("  (没找到 VERSION 文件，跳过版本一致性检查)")
    else:
        print("  版本唯一来源: %s = %s" % (src, version))

    issues = []
    stale_issues = []
    # 文档去重（Windows 下 README.md / readme.md 是同一个文件）
    seen = set()
    docs = []
    for d in sorted(os.listdir(repo)):
        if d.lower() in ("handoff.md", "readme.md") and d.lower() not in seen:
            seen.add(d.lower())
            docs.append(d)

    for d in docs:
        text = read_text(os.path.join(repo, d)) or ""
        lines = text.splitlines()

        for lineno, line in enumerate(lines, 1):
            # 1) 「当前版本 / 当前状态」必须等于 VERSION
            if version and re.search(r"当前版本|当前状态", line):
                found = re.findall(r"\bv?(\d+\.\d+\.\d+)\b", line)
                if found and version not in found:
                    issues.append("%s:%d 「当前版本/当前状态」写的是 %s，VERSION 是 %s"
                                  % (d, lineno, "/".join(found), version))

            # 2)「已发布」列表要含当前版本
            #    跳过待办清单项与标题：它们是在「提醒你去更新」，不是在陈述事实
            if (version and "已发布" in line and version not in line
                    and not re.match(r"\s*(?:[-*+]\s*)?\[[ xX]\]", line)
                    and not line.lstrip().startswith("#")):
                issues.append("%s:%d 「已发布」列表里没有当前版本 %s" % (d, lineno, version))

            # 3) 发布示例命令里的版本号
            m = re.search(r"release\s+create\s+v(\d+\.\d+\.\d+)", line)
            if m and version and m.group(1) != version:
                issues.append("%s:%d 发布示例命令写的是 v%s，当前版本是 v%s"
                              % (d, lineno, m.group(1), version))

            # 4) 硬编码行号引用
            if re.search(r"第\s*\d{2,}\s*行", line):
                issues.append("%s:%d 用了硬编码行号引用，改成节名" % (d, lineno))

            # 5) 产物体积描述（只认与产物同行的描述，避免误伤别的文件体积）
            #    不在代码里写死具体产物名 —— 不同项目的产物名不同
            if re.search(r"\.(?:exe|zip|msi|apk|dmg|img|bin|jar|whl|tgz)\b|单文件|产物|构建结果", line):
                for sm in re.finditer(r"约\s*\*{0,2}(\d+)\s*(KB|字节)\*{0,2}", line):
                    n = int(sm.group(1))
                    claimed = n * 1024 if sm.group(2) == "KB" else n
                    stale_issues.append((d, lineno, n, sm.group(2), claimed))

    issues.extend(_check_artifacts(repo, stale_issues))

    if issues:
        print("\n发现 %d 处疑点：" % len(issues))
        for i in issues:
            print("  -", i)
        print("\n提示：发版后请按 SKILL.md 第四节清单逐项更新。")
        return 1
    print("\n未发现陈旧/矛盾的描述 ✅")
    return 0


def _check_artifacts(repo, claims):
    """把文档里对产物体积的描述与 dist 下的实际文件对账。"""
    out = []
    dist = os.path.join(repo, "dist")
    real = None
    if os.path.isdir(dist):
        # 取 dist 下最大的可执行产物（不写死文件名，换项目也能用）
        cands = []
        for f in sorted(os.listdir(dist)):
            p = os.path.join(dist, f)
            if os.path.isfile(p) and f.lower().endswith((".exe", ".msi", ".apk", ".bin")):
                cands.append((f, os.path.getsize(p)))
        if cands:
            real = max(cands, key=lambda x: x[1])
    if real:
        print("  dist 下实际产物: %s = %d 字节 (%.0f KB)" % (real[0], real[1], real[1] / 1024.0))
    for d, lineno, n, unit, claimed in claims:
        if real and abs(claimed - real[1]) > 12 * 1024:
            out.append("%s:%d 写「约 %d %s」，实际 %s = %d 字节（%.0f KB）"
                       % (d, lineno, n, unit, real[0], real[1], real[1] / 1024.0))
    # 同一文档对同一产物给出多个不同体积
    by_doc = {}
    for d, lineno, n, unit, claimed in claims:
        by_doc.setdefault(d, set()).add(claimed)
    for d, vals in by_doc.items():
        if len(vals) > 1:
            out.append("%s 对同一产物给了多个体积描述 %s，核对哪个是对的"
                       % (d, " / ".join("%d KB" % (v // 1024) for v in sorted(vals))))
    return out


def _vkey(v):
    parts = [int(x) for x in re.findall(r"\d+", v)]
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])


# ---------------------------------------------------------------- 输出

def _report(title, hits, files=None, scanned=None, binary=None, unreadable=None):
    print("=== %s ===" % title)
    if files is not None:
        print("  扫描文件数: %d" % files)
    if scanned is not None:
        extra = ("（其中 %d 个二进制/按后缀跳过）" % binary) if binary else ""
        print("  实际读取并逐行检查: %d 个%s" % (scanned, extra))
    # 先报「没扫到」—— 否则下面的 ✅ 会让人以为全都扫过了
    if unreadable:
        print("  ★ 有 %d 个被跟踪文件**没扫到**，不算通过：" % len(unreadable))
        for f, why in unreadable:
            print("     - %s  （%s）" % (f, why))
    if not hits:
        if not unreadable:
            print("  未发现可疑内容 ✅")
        return
    print("  发现 %d 处可疑：" % len(hits))
    for name, f, lineno, snippet, fix in hits:
        print("  [%s] %s:%d" % (name, f, lineno))
        print("      %s" % snippet)
        print("      → %s" % fix)


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description="仓库卫生检查：隐私扫描 + 陈旧信息巡检")
    ap.add_argument("mode", choices=["privacy", "emails", "stale", "all"])
    ap.add_argument("--repo", default=os.getcwd(), help="仓库路径（默认当前目录）")
    ap.add_argument("--allow-str", action="append", default=[],
                    help="本次额外允许出现的字符串（可多次）")
    ap.add_argument("--allow-email-pattern", action="append", default=[],
                    help="允许的邮箱正则（可多次），例如机器人账号")
    args = ap.parse_args()

    repo = os.path.abspath(args.repo)
    codes = []
    if args.mode in ("privacy", "all"):
        codes.append(mode_privacy(repo, args.allow_str))
    if args.mode in ("emails", "all"):
        if args.mode == "all":
            print()
        codes.append(mode_emails(repo, args.allow_email_pattern))
    if args.mode in ("stale", "all"):
        if args.mode == "all":
            print()
        codes.append(mode_stale(repo))
    sys.exit(1 if any(c for c in codes) else 0)


if __name__ == "__main__":
    main()
