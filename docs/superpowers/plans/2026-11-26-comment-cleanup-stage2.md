# Comment Cleanup Stage 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean the comments that the 66 `patches/ii/` patches add, with zero code change and an unchanged series layout.

**Architecture:** A scratch clone of dots-hyprland at the pin carries the series as commits. Throwaway Python tools in `~/.cache/comment-cleanup/` list every added comment (inventory), prove each rewritten commit differs from its original only in comments (checker), and compare parser results (syntax check). Sonnet subagents edit the final tree; `git absorb` and two rebases fold the edits into the commits that added each comment; the series is re-exported with `git format-patch`.

**Tech Stack:** git (am, absorb, rebase, format-patch), Python 3 stdlib (unittest, difflib), bash, qmlformat, luac, Nix, `just`.

**Spec:** `docs/superpowers/specs/2026-11-26-comment-cleanup-stage2-design.md` (rules: `docs/superpowers/specs/2026-11-26-comment-cleanup-design.md`, "Rules")

## Global Constraints

- Dotfiles branch `doc-cleanup`, no worktree, no push, no merge.
- Files in the dotfiles repo and the tool scripts are written only with Edit/Write (user rule). Exceptions: `git format-patch` output, JSON written by the tool scripts, and git's own work in the scratch clone (am, absorb, rebase).
- `~/src/dots-hyprland` stays untouched. Patch files are never hand-edited.
- Scope: comment lines, including trailing comments, in `+` lines of the 66 patches in `patches/ii/`. Out: context and `-` lines, commit messages, the three standalone patches in `patches/`, Python docstrings.
- Series sizes: 01-fixes 11, 02-translator 6, 04-agents 4, 05-settings 41, 06-notifications 1, 07-idle 3 (66 total).
- Unverifiable comments stay untouched and go to `docs/superpowers/comment-review.md`.
- A commit that becomes empty: stop and ask the user.
- Dotfiles commits: subject line only, no body, no Claude attribution.
- Python scripts that read the clone run with `python3 -I` (the clone is downloaded data); each script adds its own directory to `sys.path`.

## Review Focus

1. A `//` or `#` inside a string literal edited as if it were a trailing comment: expected REVIEW output for a hand check, never a silent pass (Task 3: `test_string_marker_is_review`).
2. The same comment text added twice in one file by one commit (repeated section labels): expected both matched to list (a), no false matching error (Task 2: `test_duplicate_text_multiset`).
3. Trailing directives (`# shellcheck disable=...`, `# noqa`) removed or edited: expected FAIL (Task 3: `test_trailing_directive_change_fails`).
4. A comment block removed with the blank line after it: expected pass; an inserted blank or comment line: expected FAIL (Task 3: `test_delete_comment_and_blank_passes`, `test_insert_fails`).
5. Shell `$#` / `${#x}` and JS `'http://x'` not split as comments (Task 1: `test_split_ignores_shell_hash_and_urls`).

---

## File map

All outside the repo unless noted:

- `~/.cache/comment-cleanup/setup.sh`: clone, apply series, tags, `orig` backups.
- `~/.cache/comment-cleanup/commentlib.py`: language map, line classification, trailing-comment split, directive detection.
- `~/.cache/comment-cleanup/inventory.py`: lists (a) and (b), subagent groups.
- `~/.cache/comment-cleanup/check.py`: comment-only checker over commit pairs and over the working tree.
- `~/.cache/comment-cleanup/syntax.sh`: parser check, old vs new.
- `~/.cache/comment-cleanup/seqedit.py`: `GIT_SEQUENCE_EDITOR` for step 4b.
- `~/.cache/comment-cleanup/retag.sh`: move `krane/<dir>` tags by subject, check counts.
- `~/.cache/comment-cleanup/tests/`: unittest suites and `helpers.py`.
- Repo: `patches/ii/*/*.patch` (re-exported), `docs/superpowers/comment-review.md` (created in Task 5, deleted in Task 10).

Shell variables used in every task:

```bash
CC=~/.cache/comment-cleanup
R=$CC/dots-hyprland
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
```

Run the unit tests with: `cd ~/.cache/comment-cleanup && python3 -m unittest discover -s tests -v`

---

### Task 1: Scratch clone and comment library

**Files:**
- Create: `$CC/setup.sh`, `$CC/commentlib.py`, `$CC/tests/helpers.py`, `$CC/tests/test_commentlib.py`

**Interfaces:**
- Produces: clone `$R`, branch `krane` (66 commits on `$PIN`), tags `krane/<dir>`, branch `orig` and tags `orig/<dir>` at the same commits, `$CC/patchnames.before`.
- Produces (commentlib): `lang_of(path) -> 'c'|'hash'|'lua'|None`; `classify(lines: list[str], lang) -> list['blank'|'comment'|'code']`; `split_trailing(line, lang) -> (code: str, comment: str|None)`; `is_directive(text) -> bool`.

- [ ] **Step 1: Write `$CC/setup.sh` (Write tool)**

```bash
#!/usr/bin/env bash
# Usage: setup.sh  (run once; fails if the clone exists)
set -euo pipefail
CC=~/.cache/comment-cleanup
R=$CC/dots-hyprland
PIN=$(jq -r '.nodes."dots-hyprland".locked.rev' ~/.dotfiles/flake.lock)
[ -e "$R" ] && { echo "$R exists; remove it first" >&2; exit 1; }
git clone -q https://github.com/end-4/dots-hyprland "$R"
cd "$R"
git config rerere.enabled true
git config user.name krane
git config user.email "$(git -C ~/.dotfiles config user.email)"
git switch -q -C krane "$PIN"
for d in ~/.dotfiles/patches/ii/*/; do
  n=$(basename "$d")
  git am -q -3 "$d"*.patch
  git tag -f "krane/$n" >/dev/null
  git tag -f "orig/$n" >/dev/null
done
git branch -f orig krane
count=$(git rev-list --count "$PIN"..krane)
[ "$count" = 66 ] || { echo "expected 66 commits, got $count" >&2; exit 1; }
ls ~/.dotfiles/patches/ii/*/*.patch | sed "s|$HOME/.dotfiles/||" > "$CC/patchnames.before"
echo "ok: 66 commits on $PIN"
```

- [ ] **Step 2: Run it**

Run: `bash ~/.cache/comment-cleanup/setup.sh`
Expected: `ok: 66 commits on 21733c3...`. If `git am` stops, the committed series does not apply to the pin: stop and report.

- [ ] **Step 3: Write `$CC/tests/helpers.py`**

```python
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def run(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True).stdout


def make_repo(tmp, steps):
    """steps: [(subject, {path: content or None})]; the first step is the upstream pin.
    Returns (repo, [sha per step])."""
    repo = os.path.join(tmp, "r")
    os.mkdir(repo)
    run("git", "init", "-q", "-b", "main", repo)
    run("git", "-C", repo, "config", "user.name", "t")
    run("git", "-C", repo, "config", "user.email", "t@t")
    shas = []
    for subject, files in steps:
        for path, content in files.items():
            full = os.path.join(repo, path)
            if content is None:
                os.remove(full)
            else:
                os.makedirs(os.path.dirname(full), exist_ok=True)
                with open(full, "w") as f:
                    f.write(content)
        run("git", "-C", repo, "add", "-A")
        run("git", "-C", repo, "commit", "-q", "--allow-empty", "-m", subject)
        shas.append(run("git", "-C", repo, "rev-parse", "HEAD").strip())
    return repo, shas
```

- [ ] **Step 4: Write the failing tests `$CC/tests/test_commentlib.py`**

```python
import unittest

import helpers  # noqa: F401  (sets sys.path)
from commentlib import classify, is_directive, lang_of, split_trailing


class Lang(unittest.TestCase):
    def test_lang_of(self):
        self.assertEqual(lang_of("a/B.qml"), "c")
        self.assertEqual(lang_of("x.js"), "c")
        self.assertEqual(lang_of("x.py"), "hash")
        self.assertEqual(lang_of("x.sh"), "hash")
        self.assertEqual(lang_of("x.lua"), "lua")
        self.assertIsNone(lang_of("sequences.txt"))


class Classify(unittest.TestCase):
    def test_c_lines_and_blocks(self):
        lines = ["// a", "x = 1 // b", "", "/**", " * doc", " */", "y * 2", "/* one */", "/* c */ z()"]
        self.assertEqual(
            classify(lines, "c"),
            ["comment", "code", "blank", "comment", "comment", "comment", "code", "comment", "code"],
        )

    def test_star_outside_block_is_code(self):
        self.assertEqual(classify(["a = b", "  * c"], "c"), ["code", "code"])

    def test_python_docstring_is_code(self):
        lines = ["def f():", '    """Doc', "    # not a comment", '    """', "    # real"]
        self.assertEqual(classify(lines, "hash"), ["code", "code", "code", "code", "comment"])

    def test_directives_are_code(self):
        self.assertEqual(classify(["#!/bin/sh", "# shellcheck disable=SC2034", "# x"], "hash"),
                         ["code", "code", "comment"])
        self.assertEqual(classify(["pragma Singleton", ".pragma library"], "c"), ["code", "code"])

    def test_lua_block(self):
        self.assertEqual(classify(["--[[", "x", "]]", "-- y", "z()"], "lua"),
                         ["comment", "comment", "comment", "comment", "code"])

    def test_unknown_lang_all_code(self):
        self.assertEqual(classify(["# x", ""], None), ["code", "blank"])


class Split(unittest.TestCase):
    def test_split_basic(self):
        self.assertEqual(split_trailing("x = 1 // note", "c"), ("x = 1", "// note"))
        self.assertEqual(split_trailing("x=1  # note", "hash"), ("x=1", "# note"))
        self.assertEqual(split_trailing("x() -- n", "lua"), ("x()", "-- n"))
        self.assertEqual(split_trailing("x = 1", "c"), ("x = 1", None))

    def test_split_ignores_shell_hash_and_urls(self):
        self.assertEqual(split_trailing("echo $# ${#x}", "hash"), ("echo $# ${#x}", None))
        self.assertEqual(split_trailing("u = 'http://x' // n", "c"), ("u = 'http://x'", "// n"))
        self.assertEqual(split_trailing('s = "a // b"', "c"), ('s = "a // b"', None))
        self.assertEqual(split_trailing("t = `a ${b} // c`", "c"), ("t = `a ${b} // c`", None))

    def test_is_directive(self):
        for t in ["#!/usr/bin/env bash", "# shellcheck disable=SC1", "# noqa: E501", "# type: ignore",
                  "// @ts-ignore", "// eslint-disable-line", "// qmllint disable", "---@param x",
                  "pragma Singleton"]:
            self.assertTrue(is_directive(t), t)
        self.assertFalse(is_directive("# plain"))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 5: Run to verify failure**

Run the unit tests.
Expected: ERROR `ModuleNotFoundError: No module named 'commentlib'`

- [ ] **Step 6: Write `$CC/commentlib.py`**

```python
"""Comment classification shared by inventory.py and check.py."""
import os
import re

LANG = {".qml": "c", ".js": "c", ".mjs": "c", ".py": "hash", ".sh": "hash", ".bash": "hash", ".lua": "lua"}
MARK = {"c": "//", "hash": "#", "lua": "--"}
QUOTES = {"c": "'\"`", "hash": "'\"", "lua": "'\""}
DIRECTIVE = re.compile(
    r"^\s*(#!|#\s*(shellcheck|noqa|type:|pylint|fmt:)|//\s*(@ts-|eslint|qmllint|jshint)"
    r"|---@|--\s*luacheck|\.?pragma\b)"
)


def lang_of(path):
    return LANG.get(os.path.splitext(path)[1])


def is_directive(text):
    return bool(DIRECTIVE.match(text))


def classify(lines, lang):
    """'blank', 'comment' (whole line is comment) or 'code' per line.
    Directives and Python docstring lines are 'code', so the checker requires them unchanged."""
    out = []
    in_block = None  # closing token of an open block comment
    in_doc = None  # open triple quote (hash)
    for line in lines:
        s = line.strip()
        if in_block:
            out.append("comment")
            if in_block in s:
                in_block = None
            continue
        if in_doc:
            out.append("code")
            if s.count(in_doc) % 2 == 1:
                in_doc = None
            continue
        if not s:
            out.append("blank")
            continue
        if lang is None or is_directive(s):
            out.append("code")
            continue
        if lang == "c" and s.startswith("/*"):
            if "*/" in s[2:]:
                out.append("comment" if s.endswith("*/") else "code")
            else:
                out.append("comment")
                in_block = "*/"
            continue
        if lang == "lua" and s.startswith("--[["):
            out.append("comment")
            if "]]" not in s[4:]:
                in_block = "]]"
            continue
        if s.startswith(MARK[lang]):
            out.append("comment")
            continue
        out.append("code")
        if lang == "hash":
            for q in ('"""', "'''"):
                if s.count(q) % 2 == 1:
                    in_doc = q
                    break
    return out


def split_trailing(line, lang):
    """(code, comment) for a code line with a trailing comment, else (line, None).
    The marker must be outside quotes and preceded by whitespace."""
    if lang is None:
        return line, None
    mark = MARK[lang]
    quote = None
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in QUOTES[lang]:
            quote = ch
        elif line.startswith(mark, i) and i > 0 and line[i - 1] in " \t":
            return line[:i].rstrip(), line[i:].rstrip()
        i += 1
    return line, None
```

- [ ] **Step 7: Run to verify pass**

Run the unit tests.
Expected: all `test_commentlib` tests PASS.

No commit: everything in this task is outside the repo.

---

### Task 2: Inventory (lists a and b, subagent groups)

**Files:**
- Create: `$CC/inventory.py`, `$CC/tests/test_inventory.py`

**Interfaces:**
- Consumes: `commentlib` (Task 1), `helpers.make_repo`.
- Produces: CLI `python3 -I inventory.py REPO PIN TIP TAGPREFIX OUT.json [GROUPS]`. JSON `{"a": [entry], "b": [entry], "groups": [[file, ...], ...]}`; entry = `{"file", "line", "text", "kind": "full"|"trailing", "subject", "series"}`. For (a), `line` is the 1-based line in the TIP tree and `subject` the blame commit's subject. For (b), `line` is the line in the introducing commit's tree. Exit 1 with `ERROR ...` lines when matching fails.
- Functions used by Task 3: `git(repo, *args) -> str`, `blame_shas(repo, rev, path) -> list[sha]` (one per line).

- [ ] **Step 1: Write the failing tests `$CC/tests/test_inventory.py`**

```python
import tempfile
import unittest

from helpers import make_repo, run
from inventory import build, make_groups


class Build(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo, s = make_repo(self.tmp.name, [
            ("upstream", {"m.qml": "// upstream note\nItem {}\n"}),
            ("A add", {"m.qml": "// upstream note\nItem {}\nx = 1 // note a\n// gone\n// Spacer\n// Spacer\n"}),
            ("B change", {"m.qml": "// upstream note\nItem {}\nx = 2 // note a\n// Spacer\n// Spacer\n"}),
        ])
        self.pin, self.tip = s[0], s[-1]
        run("git", "-C", self.repo, "tag", "k/01-x", self.tip)

    def tearDown(self):
        self.tmp.cleanup()

    def test_lists(self):
        a, b, errors = build(self.repo, self.pin, self.tip, "k/")
        self.assertEqual(errors, [])
        self.assertEqual(sorted((e["subject"], e["text"]) for e in a),
                         [("A add", "// Spacer"), ("A add", "// Spacer"), ("B change", "// note a")])
        self.assertEqual(sorted((e["subject"], e["text"]) for e in b),
                         [("A add", "// gone"), ("A add", "// note a")])
        self.assertTrue(all(e["series"] == "01-x" for e in a + b))

    def test_upstream_comment_not_listed(self):
        a, b, _ = build(self.repo, self.pin, self.tip, "k/")
        self.assertNotIn("// upstream note", [e["text"] for e in a + b])

    def test_duplicate_text_multiset(self):
        a, _, errors = build(self.repo, self.pin, self.tip, "k/")
        self.assertEqual([e["line"] for e in a if e["text"] == "// Spacer"], [4, 5])
        self.assertEqual(errors, [])

    def test_groups_disjoint_by_file(self):
        a = [{"file": f, "line": 1} for f in ["x", "x", "y", "z", "z", "z"]]
        b = [{"file": "w", "line": 1}]
        groups = make_groups(a, b, 2)
        flat = [f for g in groups for f in g]
        self.assertEqual(sorted(flat), ["w", "x", "y", "z"])
        self.assertEqual(len(flat), len(set(flat)))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run to verify failure**

Run the unit tests.
Expected: ERROR `No module named 'inventory'`

- [ ] **Step 3: Write `$CC/inventory.py`**

```python
#!/usr/bin/env python3
"""Spec step 2. Usage: inventory.py REPO PIN TIP TAGPREFIX OUT.json [GROUPS]"""
import json
import os
import re
import subprocess
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from commentlib import classify, lang_of, split_trailing  # noqa: E402


def git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True, text=True).stdout


def comments_in(lines, lang):
    """[(line_no, text, kind)] for every comment in a file."""
    out = []
    for i, (line, cls) in enumerate(zip(lines, classify(lines, lang)), 1):
        if cls == "comment":
            out.append((i, line.strip(), "full"))
        elif cls == "code":
            _, comment = split_trailing(line, lang)
            if comment:
                out.append((i, comment, "trailing"))
    return out


def added_comments(repo, commit):
    diff = git(repo, "diff", "-U0", "--no-color", "--no-ext-diff", "--no-renames", commit + "^", commit)
    added = defaultdict(set)
    path, n = None, 0
    for line in diff.splitlines():
        if line.startswith("+++ "):
            path = None if line == "+++ /dev/null" else line[6:]
        elif line.startswith("@@"):
            n = int(re.match(r"@@ -\S+ \+(\d+)", line).group(1))
        elif line.startswith("+") and path:
            added[path].add(n)
            n += 1
    out = []
    for path, nums in added.items():
        lang = lang_of(path)
        if lang is None:
            continue
        lines = git(repo, "show", f"{commit}:{path}").splitlines()
        out += [(path, i, t, k) for i, t, k in comments_in(lines, lang) if i in nums]
    return out


def blame_shas(repo, rev, path):
    shas, cur = [], None
    for line in git(repo, "blame", "--line-porcelain", rev, "--", path).splitlines():
        m = re.match(r"^([0-9a-f]{40}) ", line)
        if m:
            cur = m.group(1)
        elif line.startswith("\t"):
            shas.append(cur)
    return shas


def final_comments(repo, pin, tip, commits):
    out = []
    for path in git(repo, "diff", "--name-only", "--no-renames", pin, tip).splitlines():
        lang = lang_of(path)
        if lang is None or git(repo, "ls-tree", tip, "--", path) == "":
            continue
        lines = git(repo, "show", f"{tip}:{path}").splitlines()
        shas = blame_shas(repo, tip, path)
        out += [(path, i, t, k, shas[i - 1]) for i, t, k in comments_in(lines, lang) if shas[i - 1] in commits]
    return out


def series_of(repo, pin, prefix):
    owner, prev = {}, pin
    for tag in sorted(git(repo, "tag", "-l", prefix + "*").splitlines()):
        for sha in git(repo, "rev-list", f"{prev}..{tag}").splitlines():
            owner[sha] = tag[len(prefix):]
        prev = tag
    return owner


def build(repo, pin, tip, prefix):
    commits = git(repo, "rev-list", "--reverse", f"{pin}..{tip}").splitlines()
    subject = {c: git(repo, "log", "-1", "--format=%s", c).strip() for c in commits}
    series = series_of(repo, pin, prefix)
    pool = defaultdict(list)  # (subject, file, text) -> final-tree entries not matched yet
    for path, i, text, kind, sha in final_comments(repo, pin, tip, set(commits)):
        pool[(subject[sha], path, text)].append(
            {"file": path, "line": i, "text": text, "kind": kind, "subject": subject[sha],
             "series": series.get(sha)})
    a, b, errors = [], [], []
    for c in commits:
        for path, i, text, kind in added_comments(repo, c):
            key = (subject[c], path, text)
            if pool[key]:
                a.append(pool[key].pop(0))
            else:
                b.append({"file": path, "line": i, "text": text, "kind": kind, "subject": subject[c],
                          "series": series.get(c)})
    for key, left in pool.items():
        for e in left:
            errors.append(f"ERROR final-tree comment matches no added line: {e['file']}:{e['line']} {key}")
    return a, b, errors


def make_groups(a, b, n):
    weight = defaultdict(int)
    for e in a + b:
        weight[e["file"]] += 1
    groups, load = [[] for _ in range(n)], [0] * n
    for path in sorted(weight, key=lambda p: (-weight[p], p)):
        k = load.index(min(load))
        groups[k].append(path)
        load[k] += weight[path]
    return [sorted(g) for g in groups if g]


def main():
    repo, pin, tip, prefix, out = sys.argv[1:6]
    n = int(sys.argv[6]) if len(sys.argv) > 6 else 6
    a, b, errors = build(repo, pin, tip, prefix)
    with open(out, "w") as f:
        json.dump({"a": a, "b": b, "groups": make_groups(a, b, n)}, f, indent=1)
    print(f"a={len(a)} b={len(b)} errors={len(errors)}")
    for e in errors:
        print(e)
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run to verify pass**

Run the unit tests.
Expected: all PASS.

- [ ] **Step 5: Run on the real series**

Run: `cd ~/.cache/comment-cleanup && python3 -I inventory.py "$R" "$PIN" krane krane/ inventory.json 6`
Expected: `a=<n> b=<m> errors=0`, a+b roughly 475 (the spec's rough count). A large gap means the classifier misses a comment form: inspect a sample with `rg '^\+\s*(//|#|--|/\*|\*)' ~/.dotfiles/patches/ii` before going on. Any ERROR: stop and report.

---

### Task 3: Comment-only checker

**Files:**
- Create: `$CC/check.py`, `$CC/tests/test_check.py`

**Interfaces:**
- Consumes: `commentlib`, `inventory.git`, `inventory.blame_shas`.
- Produces: CLI `python3 -I check.py REPO PIN OLD_TIP NEW_TIP` (commit pairs) and `python3 -I check.py REPO PIN --worktree` (HEAD vs working tree). Prints `REVIEW subject | file:line | old -> new` and `FAIL ...` lines and a summary line; exit 1 on any FAIL. Functions: `compare_file(old, new, lang) -> (fails, reviews, touched_old_indexes)`, `check(repo, pin, old_tip, new_tip) -> (fails, reviews)`, `check_worktree(repo, pin) -> (fails, reviews)`.

- [ ] **Step 1: Write the failing tests `$CC/tests/test_check.py`**

```python
import os
import tempfile
import unittest

from helpers import make_repo, run
from check import check, check_worktree, compare_file


class Compare(unittest.TestCase):
    def ok(self, old, new, lang="c"):
        fails, reviews, _ = compare_file(old, new, lang)
        return fails, reviews

    def test_delete_comment_and_blank_passes(self):
        self.assertEqual(self.ok(["a()", "// x", "", "b()"], ["a()", "b()"])[0], [])

    def test_delete_code_fails(self):
        self.assertTrue(self.ok(["a()", "b()"], ["a()"])[0])

    def test_insert_fails(self):
        self.assertTrue(self.ok(["a()"], ["a()", ""])[0])
        self.assertTrue(self.ok(["a()"], ["// new", "a()"])[0])

    def test_trim_comment_passes(self):
        self.assertEqual(self.ok(["// long long note", "// more", "a()"], ["// short", "a()"]), ([], []))

    def test_trailing_cut_is_review(self):
        fails, reviews = self.ok(["x = 1 // note"], ["x = 1"])
        self.assertEqual((fails, len(reviews)), ([], 1))

    def test_string_marker_is_review(self):
        fails, reviews = self.ok(['f("a") // b'], ['f("a") // c'])
        self.assertEqual((fails, len(reviews)), ([], 1))

    def test_code_change_fails(self):
        self.assertTrue(self.ok(["x = 1 // n"], ["x = 2 // n"])[0])

    def test_trailing_directive_change_fails(self):
        self.assertTrue(self.ok(["a=1  # shellcheck disable=SC2034"], ["a=1"], "hash")[0])
        self.assertTrue(self.ok(["import x  # noqa: F401"], ["import x"], "hash")[0])

    def test_shebang_and_docstring_fail(self):
        self.assertTrue(self.ok(["#!/bin/sh", "a"], ["a"], "hash")[0])
        self.assertTrue(self.ok(['"""Doc."""', "a"], ["a"], "hash")[0])

    def test_unknown_type_any_change_fails(self):
        self.assertTrue(self.ok(["# x", "y"], ["y"], None)[0])


class Pairs(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo, (self.pin, self.old) = make_repo(self.tmp.name, [
            ("upstream", {"m.qml": "// up\nItem {}\n"}),
            ("A", {"m.qml": "// up\nItem {}\n// mine\nx()\n"}),
        ])

    def tearDown(self):
        self.tmp.cleanup()

    def commit_new(self, content, subject="A"):
        run("git", "-C", self.repo, "checkout", "-q", "-B", "new", self.pin)
        with open(os.path.join(self.repo, "m.qml"), "w") as f:
            f.write(content)
        run("git", "-C", self.repo, "commit", "-q", "-am", subject)
        return run("git", "-C", self.repo, "rev-parse", "HEAD").strip()

    def test_own_comment_removed_passes(self):
        new = self.commit_new("// up\nItem {}\nx()\n")
        self.assertEqual(check(self.repo, self.pin, self.old, new)[0], [])

    def test_upstream_comment_removed_fails(self):
        new = self.commit_new("Item {}\n// mine\nx()\n")
        self.assertTrue(any("upstream" in f for f in check(self.repo, self.pin, self.old, new)[0]))

    def test_subject_mismatch_fails(self):
        new = self.commit_new("// up\nItem {}\nx()\n", subject="renamed")
        self.assertTrue(any("subject" in f for f in check(self.repo, self.pin, self.old, new)[0]))

    def test_worktree(self):
        path = os.path.join(self.repo, "m.qml")
        with open(path, "w") as f:
            f.write("// up\nItem {}\nx()\n")
        self.assertEqual(check_worktree(self.repo, self.pin)[0], [])
        with open(path, "w") as f:
            f.write("// up\nItem {}\n// mine\ny()\n")
        self.assertTrue(check_worktree(self.repo, self.pin)[0])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run to verify failure**

Run the unit tests.
Expected: ERROR `No module named 'check'`

- [ ] **Step 3: Write `$CC/check.py`**

```python
#!/usr/bin/env python3
"""Spec "Verification". Usage: check.py REPO PIN OLD_TIP NEW_TIP | check.py REPO PIN --worktree"""
import difflib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from commentlib import classify, is_directive, lang_of, split_trailing  # noqa: E402
from inventory import blame_shas, git  # noqa: E402


def compare_file(old, new, lang):
    fails, reviews, touched = [], [], []
    co, cn = classify(old, lang), classify(new, lang)
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, old, new, autojunk=False).get_opcodes():
        if op == "equal":
            continue
        touched += range(i1, i2)
        if op == "insert":
            fails.append(f"inserted lines {j1 + 1}-{j2}")
            continue
        if op == "delete":
            fails += [f"deleted non-comment line {i + 1}: {old[i]!r}"
                      for i in range(i1, i2) if co[i] not in ("blank", "comment")]
            continue
        old_code = [i for i in range(i1, i2) if co[i] == "code"]
        new_code = [j for j in range(j1, j2) if cn[j] == "code"]
        if any(cn[j] == "comment" for j in range(j1, j2)) and not any(co[i] == "comment" for i in range(i1, i2)):
            fails.append(f"comment line added at {j1 + 1}")
        if len(old_code) != len(new_code):
            fails.append(f"code lines {i1 + 1}-{i2} changed in count")
            continue
        for i, j in zip(old_code, new_code):
            o, n = old[i], new[j]
            if o == n:
                continue
            oc, ocm = split_trailing(o, lang)
            nc, ncm = split_trailing(n, lang)
            same_code = ocm is not None and oc.rstrip() == (nc if ncm else n).rstrip()
            if same_code and not is_directive(ocm) and not (ncm and is_directive(ncm)):
                reviews.append((i, o, n))
            else:
                fails.append(f"code changed at old line {i + 1}: {o!r} -> {n!r}")
    return fails, reviews, touched


def show(repo, rev, path):
    if git(repo, "ls-tree", rev, "--", path) == "":
        return None
    return git(repo, "show", f"{rev}:{path}").splitlines()


def compare_path(repo, label, path, a, b, base_rev, own):
    if a is None or b is None:
        return [f"FAIL {label} | {path}: file added or removed"], []
    f, r, touched = compare_file(a, b, lang_of(path))
    fails = [f"FAIL {label} | {path}: {x}" for x in f]
    reviews = [f"REVIEW {label} | {path}:{i + 1} | {o!r} -> {n!r}" for i, o, n in r]
    if touched:
        shas = blame_shas(repo, base_rev, path)
        fails += [f"FAIL {label} | {path}:{i + 1}: edits an upstream line: {a[i]!r}"
                  for i in touched if shas[i] not in own]
    return fails, reviews


def check(repo, pin, old_tip, new_tip):
    olds = git(repo, "rev-list", "--reverse", f"{pin}..{old_tip}").splitlines()
    news = git(repo, "rev-list", "--reverse", f"{pin}..{new_tip}").splitlines()
    subj = {c: git(repo, "log", "-1", "--format=%s", c).strip() for c in olds + news}
    so, sn = [subj[c] for c in olds], [subj[c] for c in news]
    if so != sn:
        diff = sorted(set(so) ^ set(sn))
        return [f"FAIL subject lists differ ({len(so)} vs {len(sn)}): {diff[:5]}"], []
    fails, reviews = [], []
    for k, (o, n) in enumerate(zip(olds, news)):
        own = set(olds[: k + 1])
        for path in git(repo, "diff", "--name-only", "--no-renames", o, n).splitlines():
            f, r = compare_path(repo, subj[o], path, show(repo, o, path), show(repo, n, path), o, own)
            fails += f
            reviews += r
    return fails, reviews


def check_worktree(repo, pin):
    own = set(git(repo, "rev-list", f"{pin}..HEAD").splitlines())
    fails, reviews = [], []
    for path in git(repo, "diff", "--name-only", "--no-renames", "HEAD").splitlines():
        full = os.path.join(repo, path)
        b = open(full).read().splitlines() if os.path.exists(full) else None
        f, r = compare_path(repo, "worktree", path, show(repo, "HEAD", path), b, "HEAD", own)
        fails += f
        reviews += r
    return fails, reviews


def main():
    repo, pin = sys.argv[1:3]
    if sys.argv[3] == "--worktree":
        fails, reviews = check_worktree(repo, pin)
    else:
        fails, reviews = check(repo, pin, sys.argv[3], sys.argv[4])
    for line in reviews + fails:
        print(line)
    print(f"fails={len(fails)} reviews={len(reviews)}")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run to verify pass**

Run the unit tests.
Expected: all PASS.

- [ ] **Step 5: Sanity run on the unchanged series**

Run: `cd ~/.cache/comment-cleanup && python3 -I check.py "$R" "$PIN" orig krane`
Expected: `fails=0 reviews=0` (identical histories).

---

### Task 4: Syntax check and sequence editor

**Files:**
- Create: `$CC/syntax.sh`, `$CC/seqedit.py`, `$CC/tests/test_tools.py`

**Interfaces:**
- Produces: `bash syntax.sh REPO OLD NEW`: `FAIL path` for each file whose parser succeeds on OLD but fails on NEW, `SKIP path` when it fails on OLD too; exit 1 on any FAIL.
- Produces: `GIT_SEQUENCE_EDITOR="python3 -I $CC/seqedit.py SUBJECTS_FILE"`: rewrites `pick <sha> <subject>` to `edit <sha> <subject>` when `<subject>` is a line of SUBJECTS_FILE; exits 1 if a listed subject is missing from the todo (git then aborts the rebase).

- [ ] **Step 1: Write the failing tests `$CC/tests/test_tools.py`**

```python
import os
import subprocess
import tempfile
import unittest

from helpers import make_repo

CC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def syntax(repo, old, new):
    return subprocess.run(["bash", f"{CC}/syntax.sh", repo, old, new], capture_output=True, text=True)


class Syntax(unittest.TestCase):
    def test_broken_shell_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo, (old, new) = make_repo(tmp, [("o", {"a.sh": 'echo "a # b"\n'}), ("n", {"a.sh": 'echo "a\n'})])
            r = syntax(repo, old, new)
            self.assertEqual(r.returncode, 1)
            self.assertIn("FAIL a.sh", r.stdout)

    def test_clean_python_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo, (old, new) = make_repo(tmp, [("o", {"a.py": "x = 1  # c\n"}), ("n", {"a.py": "x = 1\n"})])
            r = syntax(repo, old, new)
            self.assertEqual(r.returncode, 0, r.stdout)

    def test_broken_qml_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo, (old, new) = make_repo(tmp, [("o", {"a.qml": "Item {\n}\n"}), ("n", {"a.qml": "Item {\n"})])
            self.assertEqual(syntax(repo, old, new).returncode, 1)


class SeqEdit(unittest.TestCase):
    def run_edit(self, tmp, subjects, todo):
        with open(f"{tmp}/s", "w") as f:
            f.write(subjects)
        with open(f"{tmp}/todo", "w") as f:
            f.write(todo)
        r = subprocess.run(["python3", f"{CC}/seqedit.py", f"{tmp}/s", f"{tmp}/todo"])
        with open(f"{tmp}/todo") as f:
            return r.returncode, f.read()

    def test_marks_edit_by_subject(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, todo = self.run_edit(tmp, "fix: b thing\n", "pick 111 fix: a\npick 222 fix: b thing\n# c\n")
            self.assertEqual((code, todo), (0, "pick 111 fix: a\nedit 222 fix: b thing\n# c\n"))

    def test_missing_subject_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(self.run_edit(tmp, "nope\n", "pick 111 fix: a\n")[0], 1)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run to verify failure**

Run the unit tests.
Expected: the `test_tools` tests FAIL (scripts missing).

- [ ] **Step 3: Write `$CC/syntax.sh`**

```bash
#!/usr/bin/env bash
# Usage: syntax.sh REPO OLD NEW
set -uo pipefail
repo=$1 old=$2 new=$3
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export PYTHONPYCACHEPREFIX=$tmp/pycache
parse() {
  case $1 in
    *.sh | *.bash) bash -n "$1" ;;
    *.py) python3 -I -m py_compile "$1" ;;
    *.lua) nix shell nixpkgs#lua5_4 -c luac -p "$1" ;;
    *.qml | *.js | *.mjs) qmlformat "$1" >/dev/null ;;
    *) return 0 ;;
  esac
}
status=0
while IFS= read -r path; do
  ext=${path##*.}
  git -C "$repo" show "$old:$path" >"$tmp/old.$ext" 2>/dev/null || continue
  if ! git -C "$repo" show "$new:$path" >"$tmp/new.$ext" 2>/dev/null; then
    echo "FAIL $path (missing in new)"; status=1; continue
  fi
  if parse "$tmp/old.$ext" >/dev/null 2>&1; then
    parse "$tmp/new.$ext" >/dev/null 2>&1 || { echo "FAIL $path"; status=1; }
  else
    echo "SKIP $path (parser fails on old)"
  fi
done < <(git -C "$repo" diff --name-only --no-renames "$old" "$new")
exit $status
```

- [ ] **Step 4: Write `$CC/seqedit.py`**

```python
#!/usr/bin/env python3
"""GIT_SEQUENCE_EDITOR for spec step 4b. Usage: seqedit.py SUBJECTS_FILE TODO"""
import sys

subjects_file, todo = sys.argv[1], sys.argv[-1]
with open(subjects_file) as f:
    wanted = {line.rstrip("\n") for line in f if line.strip()}
seen, out = set(), []
with open(todo) as f:
    for line in f:
        parts = line.rstrip("\n").split(" ", 2)
        if len(parts) == 3 and parts[0] == "pick" and parts[2] in wanted:
            line = f"edit {parts[1]} {parts[2]}\n"
            seen.add(parts[2])
        out.append(line)
with open(todo, "w") as f:
    f.writelines(out)
for s in sorted(wanted - seen):
    print(f"subject not in todo: {s}", file=sys.stderr)
sys.exit(1 if wanted - seen else 0)
```

- [ ] **Step 5: Run to verify pass**

Run the unit tests.
Expected: all PASS.

- [ ] **Step 6: Tool sanity on the real series**

Run: `bash ~/.cache/comment-cleanup/syntax.sh "$R" "$PIN" krane | cut -d' ' -f1 | sort | uniq -c; nix shell nixpkgs#lua5_4 -c luac -v`
Expected: `luac` prints a version; no FAIL lines (the series as built today parses). If most QML files SKIP, `qmlformat` cannot parse ii's QML: stop and report.

---

### Task 5: Edit the final tree with subagents

**Files:**
- Modify (scratch clone working tree): files in the `inventory.json` groups.
- Create: `$CC/group-<k>.json` (script output), `$CC/decisions.json` (Write tool), `docs/superpowers/comment-review.md` (repo, Write tool).

**Interfaces:**
- Consumes: `$CC/inventory.json` (Task 2).
- Produces: uncommitted edits in `$R`; `$CC/decisions.json` = list of `{"subject", "file", "text", "action": "delete"|"trim"|"keep", "new": str|null}` for every list (b) entry; the review list.

- [ ] **Step 1: Write one input file per group**

```bash
cd ~/.cache/comment-cleanup
python3 -I -c '
import json
inv = json.load(open("inventory.json"))
for k, files in enumerate(inv["groups"]):
    fs = set(files)
    json.dump({"files": files, "a": [e for e in inv["a"] if e["file"] in fs],
               "b": [e for e in inv["b"] if e["file"] in fs]}, open(f"group-{k}.json", "w"), indent=1)
print(len(inv["groups"]))'
```
Expected: prints the group count (6).

- [ ] **Step 2: Dispatch the subagents in parallel (model: sonnet), one per group, with this prompt** (replace `{K}`)

```text
You clean code comments in a scratch clone of dots-hyprland at ~/.cache/comment-cleanup/dots-hyprland. Read the rules first: ~/.dotfiles/docs/superpowers/specs/2026-11-26-comment-cleanup-design.md ("Rules") and ~/.dotfiles/docs/superpowers/specs/2026-11-26-comment-cleanup-stage2-design.md. Follow ponytail.

Your input: ~/.cache/comment-cleanup/group-{K}.json. "a" entries are comments in the current working tree (file relative to the clone, 1-based line, text, kind full|trailing, subject of the commit that last touched the line). "b" entries are comments that exist only in earlier commits.

For each "a" entry: edit only that comment, only with the Edit tool. Never touch another line, never change code, never reformat. A trailing comment goes together with the whitespace before it. When you delete a whole comment block, also delete one adjacent blank line only if two blank lines would otherwise remain. Do not commit and do not run git commands that change state.

For each "b" entry: do not edit. Decide delete, trim (give the new text) or keep. To see its context, run: git -C ~/.cache/comment-cleanup/dots-hyprland log --format='%H %s' orig | grep -F "<subject>"
then: git -C ~/.cache/comment-cleanup/dots-hyprland show <sha>:<file>

Rules (the stage 1 spec wins on conflict):
- Default is delete. Keep only: verified and needed why/workaround notes (trimmed); machine-read directives (shebang, shellcheck, noqa, type:, qmllint, eslint, @ts-, ---@, pragma); URL or issue references behind a pin or workaround; license headers; section banners shortened to one line.
- Delete: comments restating the code, commented-out code, history notes, every prescriptive rule ("always", "never", "keep in sync"), speculation.
- Verify each why-note against the code in the clone (does the referenced code, property, file or behavior exist as claimed?). Verified and needed: keep, trimmed to the fewest words. Verified false or obsolete: delete. Cannot be verified from the clone or ~/.dotfiles (hardware quirk, unlinked upstream bug, timing): leave untouched and report it.
- Before deleting a comment, search for pointers to it with both of these, and keep the comment and report the pointer if something points at it:
  rg -n -F "<distinctive phrase>" ~/.dotfiles --glob '!patches/**'
  rg -n -F "<phrase>" ~/.dotfiles/patches/ii | grep -v '^[^:]*:[0-9]*:[+ -]'
- Python docstrings are out of scope: leave them.

Reply with only:
1. Counts: a-entries deleted / trimmed / kept / unverifiable.
2. b decisions, one JSON object per line: {"subject": ..., "file": ..., "text": ..., "action": "delete"|"trim"|"keep", "new": "<trimmed text>" or null}
3. Unverifiable, one per line: file:line | subject | comment text | why it cannot be verified
4. Pointers found, one per line: comment file:line | pointing location
```

- [ ] **Step 3: Collect replies**

Write (Write tool) all b decisions into `$CC/decisions.json` as one JSON array. Then check coverage:

```bash
cd ~/.cache/comment-cleanup
python3 -I -c '
import json
b = json.load(open("inventory.json"))["b"]
d = json.load(open("decisions.json"))
key = lambda e: (e["subject"], e["file"], e["text"])
missing = [key(e) for e in b if key(e) not in {key(x) for x in d}]
print("missing:", missing)'
```
Expected: `missing: []`. Otherwise ask the owning subagent for the missing decisions.

- [ ] **Step 4: Check the working tree**

```bash
cd ~/.cache/comment-cleanup
git -C "$R" diff --name-only | sort > edited-files
python3 -I -c 'import json; print("\n".join(sorted(f for g in json.load(open("inventory.json"))["groups"] for f in g)))' > assigned-files
comm -23 edited-files assigned-files
python3 -I check.py "$R" "$PIN" --worktree > check-worktree.txt; echo exit=$?; tail -1 check-worktree.txt
```
Expected: `comm` prints nothing; `exit=0`. Read every `REVIEW` line: each must cut or change a real trailing comment, not part of a string. Fix any FAIL by restoring the code line with the Edit tool and re-run.

- [ ] **Step 5: Write the review list**

Find each unverifiable entry's patch file: `rg -l -F "<subject>" ~/.dotfiles/patches/ii`. Write (Write tool) `docs/superpowers/comment-review.md`:

```markdown
# Stage 2 comment review list

Unverifiable comments in `patches/ii/`, left untouched. Decide each: keep, trim (give the text) or delete.
This file is deleted before merge.

- `patches/ii/<dir>/<file>.patch` | <subject> | `<file>:<line>` | `<comment text>` | <why it cannot be verified>
```

If there are no unverifiable entries, skip this step and Step 6.

- [ ] **Step 6: Commit the review list**

```bash
git -C ~/.dotfiles add docs/superpowers/comment-review.md
git -C ~/.dotfiles commit -m "Add review list for stage 2 comment cleanup"
```

---

### Task 6: Fold list (a) edits into their commits (step 4a)

**Files:**
- Modify: scratch clone history (branch `krane`).

**Interfaces:**
- Consumes: working-tree edits from Task 5, `check.py`, `syntax.sh`.
- Produces: branch `krane` with 66 commits, list (a) edits folded in.

- [ ] **Step 1: Absorb**

```bash
cd "$R"
git add -u
nix shell nixpkgs#git-absorb -c git absorb --base "$PIN"
git status --short
```
Expected: fixup commits created. `git status --short` lists files with hunks absorb could not place (still staged).

- [ ] **Step 2: Place leftovers by hand**

For each file still listed:
1. Find the target commit of each leftover hunk (`git diff --cached -U0 <file>`) from its `a` entry's `subject` in `inventory.json`: `git log --format=$'%H\t%s' "$PIN"..krane | awk -F'\t' -v s="<subject>" '$2 == s {print $1}'`.
2. All hunks of the file target one commit: `git commit -q --fixup=<sha> -- <file>`.
3. Hunks target several commits: save the edited content (Read tool), `git restore --staged --worktree <file>`, re-apply only the first commit's edits with the Edit tool, `git commit -q --fixup=<sha1> -- <file>`, then the next commit's edits, and so on.

Repeat until `git status --short` is empty.

- [ ] **Step 3: Autosquash**

```bash
cd "$R"
GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash --empty=stop "$PIN"
```
On a conflict: resolve the file with the Edit tool as the later commit's version with the list (a) decision applied (comment deleted or trimmed), then `git add <file>` and `git rebase --continue`. If git reports that a commit became empty: `git rebase --abort`, stop, ask the user.

- [ ] **Step 4: Verify**

```bash
cd ~/.cache/comment-cleanup
git -C "$R" rev-list --count "$PIN"..krane
git -C "$R" status --short
python3 -I check.py "$R" "$PIN" orig krane > check-4a.txt; echo exit=$?; tail -1 check-4a.txt
bash syntax.sh "$R" orig krane > syntax-4a.txt; echo exit=$?; grep -v '^SKIP' syntax-4a.txt
```
Expected: `66`; empty status; both `exit=0`. Read every `REVIEW` line in `check-4a.txt`. On a FAIL: `git rebase -i "$PIN"` with that commit marked `edit` (use `seqedit.py` with a one-line subjects file), restore the code line with the Edit tool, amend, continue, re-run this step.

---

### Task 7: List (b) edits in the introducing commits (step 4b)

**Files:**
- Modify: scratch clone history.
- Create: `$CC/b-subjects.txt` (Write tool).

**Interfaces:**
- Consumes: `$CC/decisions.json`, `seqedit.py`.
- Produces: branch `krane`, 66 commits, all edits applied.

- [ ] **Step 1: Subjects to edit**

Write `$CC/b-subjects.txt`: one line per distinct `subject` in `decisions.json` whose `action` is not `keep`. If none, skip to Step 4.

- [ ] **Step 2: Rebase with edit stops**

```bash
cd "$R"
GIT_SEQUENCE_EDITOR="python3 -I $HOME/.cache/comment-cleanup/seqedit.py $HOME/.cache/comment-cleanup/b-subjects.txt" \
  git rebase -i --empty=stop "$PIN"
```
Expected: stops at the first marked commit. If `seqedit.py` reports a missing subject, git aborts: fix `b-subjects.txt` and re-run.

- [ ] **Step 3: At each stop**

1. `git log -1 --format=%s` names the commit. Apply every decision for that subject with the Edit tool: delete the comment, or replace its text with `new`.
2. `git add -u && git commit -q --amend --no-edit && git rebase --continue`
3. On a conflict in a later commit: edit the conflicted lines to the later commit's lines (that side already carries its 4a edits), `git add <file>`, `git rebase --continue`.
4. If git reports that a commit became empty: `git rebase --abort`, stop, ask the user.

- [ ] **Step 4: Verify**

```bash
cd ~/.cache/comment-cleanup
git -C "$R" rev-list --count "$PIN"..krane
python3 -I check.py "$R" "$PIN" orig krane > check-4b.txt; echo exit=$?; tail -1 check-4b.txt
bash syntax.sh "$R" orig krane > syntax-4b.txt; echo exit=$?; grep -v '^SKIP' syntax-4b.txt
```
Expected: `66`; both `exit=0`; every `REVIEW` line in `check-4b.txt` read and confirmed as a real comment edit.

---

### Task 8: Re-tag, export, commit per series

**Files:**
- Create: `$CC/retag.sh`
- Modify: `patches/ii/*/*.patch` (re-exported)

**Interfaces:**
- Consumes: branch `krane`, tags `orig/<dir>`, `$CC/patchnames.before`.
- Produces: `krane/<dir>` tags on rewritten commits, the re-exported series, one dotfiles commit per changed series.

- [ ] **Step 1: Write `$CC/retag.sh`**

```bash
#!/usr/bin/env bash
# Usage: retag.sh REPO PIN  (moves krane/<dir> to the krane commit whose subject matches orig/<dir>)
set -euo pipefail
repo=$1 pin=$2
declare -A want=([01-fixes]=11 [02-translator]=6 [04-agents]=4 [05-settings]=41 [06-notifications]=1 [07-idle]=3)
prev=$pin
for tag in $(git -C "$repo" tag -l 'orig/*' | sort); do
  n=${tag#orig/}
  s=$(git -C "$repo" log -1 --format=%s "$tag")
  sha=$(git -C "$repo" log --format=$'%H\t%s' "$pin"..krane | awk -F'\t' -v s="$s" '$2 == s {print $1}')
  [ "$(wc -w <<<"$sha")" = 1 ] || { echo "no unique match for $n: $s" >&2; exit 1; }
  git -C "$repo" tag -f "krane/$n" "$sha" >/dev/null
  c=$(git -C "$repo" rev-list --count "$prev..krane/$n")
  [ "$c" = "${want[$n]}" ] || { echo "$n has $c commits, want ${want[$n]}" >&2; exit 1; }
  prev=krane/$n
done
[ "$(git -C "$repo" rev-list --count "$pin..krane/07-idle")" = 66 ] || { echo "total is not 66" >&2; exit 1; }
[ "$(git -C "$repo" rev-parse krane/07-idle)" = "$(git -C "$repo" rev-parse krane)" ] \
  || { echo "krane/07-idle is not the branch tip" >&2; exit 1; }
echo "tags ok"
```

- [ ] **Step 2: Run it**

Run: `bash ~/.cache/comment-cleanup/retag.sh "$R" "$PIN"`
Expected: `tags ok`

- [ ] **Step 3: Export (loop from `docs/II-INTEGRATION.md`, adapted)**

```bash
cd "$R"
if [ -d .git/rebase-apply ] || [ -d .git/rebase-merge ]; then
  echo "an am/rebase is still in progress; finish it before exporting" >&2; exit 1
fi
prev="$PIN"
for d in ~/.dotfiles/patches/ii/*/; do
  n=$(basename "$d")
  git rev-parse --verify -q "krane/$n" >/dev/null || { echo "tag krane/$n missing" >&2; break; }
  rm -f "$d"*.patch
  git format-patch -q --zero-commit --no-signature --no-numbered -o "$d" "$prev..krane/$n"
  prev="krane/$n"
done
ls ~/.dotfiles/patches/ii/*/*.patch | sed "s|$HOME/.dotfiles/||" | diff ~/.cache/comment-cleanup/patchnames.before - && echo "names identical"
git -C ~/.dotfiles status --short | grep -v ' patches/ii/' ; echo "---"
git -C ~/.dotfiles diff -- patches/ii | grep -E '^[+-](From:|Date:|Subject:|Backport|Problem|Port|Drop when)'
```
Expected: `names identical`; nothing before `---` (only `patches/ii` changed); the last command prints nothing (commit headers and messages unchanged).

- [ ] **Step 4: Remaining-comment check**

Run: `cd ~/.cache/comment-cleanup && python3 -I inventory.py "$R" "$PIN" krane krane/ remaining.json 1`
Expected: `errors=0`. Read every entry in `remaining.json` (`a` and `b`): each must be a kept comment (directive, verified why-note, reference, license, one-line banner) or on the review list. A stray comment: back to Task 6 or 7 for that line, then repeat Task 8.

- [ ] **Step 5: Commit per series**

```bash
cd ~/.dotfiles
for d in patches/ii/*/; do
  n=$(basename "$d")
  git add "$d"
  git diff --cached --quiet || git commit -q -m "Clean comments in ii $n patches"
done
git log --oneline -7
```
Expected: one commit per series that changed (06-notifications adds no comments and may produce none).

---

### Task 9: Whole-stage verification and review

**Files:** none, unless a check fails.

- [ ] **Step 1: Cross-references**

```bash
cd ~/.dotfiles
rg -n '`0[0-9]{3}`' docs/II-INTEGRATION.md | head -60
ls patches/ii/*/
rg -n -i 'see .*(comment|above|below)|comment in' patches/ii | grep -v '^[^:]*:[0-9]*:[+ -]'
rg -n 'patches/ii' lib/mk-host.nix README.md docs/*.md
```
Check: every patch number and name in the `docs/II-INTEGRATION.md` tables exists under `patches/ii/` with the same subject; every "see ..." in commit messages and in remaining comments resolves. Fix broken pointers with the Edit tool and commit: `Fix references after stage 2 comment cleanup`.

- [ ] **Step 2: Lint and tests**

Run: `cd ~/.dotfiles && just ci`
Expected: exit 0.

- [ ] **Step 3: Flake check**

Run: `cd ~/.dotfiles && just check`
Expected: exit 0.

- [ ] **Step 4: Real build of the patched source**

Run: `cd ~/.dotfiles && nix build --no-link .#nixosConfigurations.tariognatha.config.system.build.toplevel`
Expected: exit 0. A failure naming a `.patch` file means the series does not apply after `illogical-flake-cheatsheet-fkeys.patch`: stop and report.

- [ ] **Step 5: Opus review**

Dispatch one subagent (model: opus) with: "Review the stage 2 diff, `git -C ~/.dotfiles diff <plan-commit>..HEAD -- patches/ii docs` (plan-commit = `git log --format=%H -1 -- docs/superpowers/plans/2026-11-26-comment-cleanup-stage2.md`), against docs/superpowers/specs/2026-11-26-comment-cleanup-stage2-design.md and the stage 1 rules. Check: only comment text in + lines changed; commit messages unchanged; kept comments fit a keep category; sample 20 deleted why-notes against the code in ~/.cache/comment-cleanup/dots-hyprland. Output: numbered defects with patch file and line, or 'none'." Fix confirmed defects through Tasks 6 to 8, then repeat Steps 2 to 4.

- [ ] **Step 6: Report to the user**

Report: commits created, counts (deleted / trimmed / kept / unverifiable), the review list path, and that the second round waits for their decisions.

---

### Task 10: Review list round and cleanup (after the user decides)

- [ ] **Step 1: Apply decisions**

For each decided entry in `docs/superpowers/comment-review.md`: if the comment is in the final tree, edit it in `$R` with the Edit tool and run Task 5 Step 4 and Task 6; otherwise add a decision to `$CC/decisions.json`, write its subject to `$CC/b-subjects.txt` and run Task 7. Then Task 8 (commit subject: `Apply review decisions to stage 2 ii patch comments`, one commit) and Task 9 Steps 2 to 4.

- [ ] **Step 2: Delete the review list**

```bash
git -C ~/.dotfiles rm -q docs/superpowers/comment-review.md
git -C ~/.dotfiles commit -m "Drop stage 2 comment review list"
```

- [ ] **Step 3: Before merge only**

Delete `~/.cache/comment-cleanup/` when the user says the branch is ready to merge.
