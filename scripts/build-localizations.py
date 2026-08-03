#!/usr/bin/env python3
"""把 Resources/Localizations/fragments/*.strings 合并成各语言的 Localizable.strings，并校验。

为什么需要这一步：
  - 本地化表由多个来源拼装（按界面区域分片），直接手写一个大文件容易冲突。
  - 更重要的是**校验**：这套机制在查不到 key 时会静默回落到 key 本身，不会报错。
    所以"某语言少了一条"在运行时看不出来，只会显示成一串 `settings.general.xxx`。
    这里把语言间的 key 差集、重复 key、格式说明符不匹配全部变成硬错误。

用法：
    python3 scripts/build-localizations.py          # 合并 + 校验
    python3 scripts/build-localizations.py --check  # 只校验（CI 用，不写文件）
"""

from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FRAGMENTS = ROOT / "Resources" / "Localizations" / "fragments"
OUT_DIR = ROOT / "Resources" / "Localizations"

# 以 en 为准：key 集合由英文定义，其它语言必须完全对齐。
REFERENCE = "en"

ENTRY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')
SPECIFIER = re.compile(r"%(\d+\$)?[@a-zA-Z]|%%")


def parse(path: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    in_block_comment = False
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        # 跨行块注释要跟状态，不能只看行首是不是 `*`——
        # 译者写的多行注释后续行往往顶格。
        if in_block_comment:
            if "*/" in line:
                in_block_comment = False
                line = line.split("*/", 1)[1].strip()
            else:
                continue
        while line.startswith("/*"):
            if "*/" in line[2:]:
                line = line.split("*/", 1)[1].strip()
            else:
                in_block_comment = True
                line = ""
                break
        if not line or line.startswith("//"):
            continue
        # 行尾的同行注释（`"k" = "v"; /* note */`）不参与解析。
        if "/*" in line and line.index("/*") > 0:
            head, _, tail = line.partition("/*")
            if "*/" not in tail:
                in_block_comment = True
            line = head.strip()
            if not line:
                continue
        match = ENTRY.match(line)
        if not match:
            fail(f"{path.name}:{lineno}: 无法解析这一行（缺分号或引号？）\n    {raw}")
            continue
        key, value = match.group(1), match.group(2)
        if key in entries:
            fail(f"{path.name}:{lineno}: key 重复：{key}")
        entries[key] = value
    return entries


ERRORS: list[str] = []


def fail(message: str) -> None:
    ERRORS.append(message)


def specifiers(value: str) -> list[str]:
    """归一化格式说明符，用于跨语言比对。位置说明符按位置排序后比较。"""
    found = [m.group(0) for m in SPECIFIER.finditer(value) if m.group(0) != "%%"]
    return sorted(found)


def main() -> int:
    check_only = "--check" in sys.argv

    if not FRAGMENTS.is_dir():
        print(f"没有 fragments 目录：{FRAGMENTS}", file=sys.stderr)
        return 1

    # 按语言收集：fragments/<area>.<lang>.strings
    by_lang: dict[str, dict[str, str]] = defaultdict(dict)
    origin: dict[tuple[str, str], str] = {}

    for path in sorted(FRAGMENTS.glob("*.strings")):
        parts = path.name.split(".")
        if len(parts) != 3:
            fail(f"{path.name}: 文件名要形如 <area>.<lang>.strings")
            continue
        area, lang, _ = parts
        for key, value in parse(path).items():
            if key in by_lang[lang]:
                fail(f"{lang}: key 在多个分片里重复定义：{key}"
                     f"（{origin[(lang, key)]} 与 {path.name}）")
                continue
            by_lang[lang][key] = value
            origin[(lang, key)] = path.name

    if REFERENCE not in by_lang:
        fail(f"缺少参考语言 {REFERENCE} 的分片")
        return report()

    reference = by_lang[REFERENCE]

    for lang, entries in sorted(by_lang.items()):
        if lang == REFERENCE:
            continue
        missing = sorted(set(reference) - set(entries))
        extra = sorted(set(entries) - set(reference))
        for key in missing:
            fail(f"{lang}: 缺少 key（会在界面上显示成 key 本身）：{key}")
        for key in extra:
            fail(f"{lang}: 多出 en 里没有的 key（拼错？）：{key}")
        # 说明符必须一致，否则 String(format:) 会读到错误的参数类型 → 可能直接崩。
        for key in sorted(set(reference) & set(entries)):
            want, got = specifiers(reference[key]), specifiers(entries[key])
            if want != got:
                fail(f"{lang}: key `{key}` 的格式说明符与 en 不一致："
                     f"en={want} {lang}={got}")

    if ERRORS:
        return report()

    if not check_only:
        for lang, entries in sorted(by_lang.items()):
            target_dir = OUT_DIR / f"{lang}.lproj"
            target_dir.mkdir(parents=True, exist_ok=True)
            target = target_dir / "Localizable.strings"
            lines = [
                "/* 由 scripts/build-localizations.py 生成，请勿直接编辑。",
                "   改文案请改 Resources/Localizations/fragments/*.strings 后重新运行。 */",
                "",
            ]
            for key in sorted(entries):
                lines.append(f'"{key}" = "{entries[key]}";')
            target.write_text("\n".join(lines) + "\n", encoding="utf-8")
            print(f"  {target.relative_to(ROOT)}  ({len(entries)} keys)")

    print(f"✓ {len(reference)} keys × {len(by_lang)} languages, 校验通过")
    return 0


def report() -> int:
    print(f"✗ 本地化校验失败（{len(ERRORS)} 项）：", file=sys.stderr)
    for error in ERRORS:
        print(f"  - {error}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
