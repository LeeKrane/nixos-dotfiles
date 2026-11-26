# Comment Cleanup Stage 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove unneeded code comments and trim the rest across the repo, one commit per area, with zero code changes.

**Architecture:** A throwaway checker outside the repo proves each area's diff changes only comments (Nix: `nix-instantiate --parse`, shell: `shfmt -mn`, Python: `ast`, Lua: stripped LuaJIT bytecode, other files: comment-line strip). One sonnet subagent per area applies the spec's rules; the main thread checks, lints, records unverifiable notes and commits.

**Tech Stack:** Nix, bash, Lua, Python 3, `just`, git.

**Spec:** `docs/superpowers/specs/2026-11-26-comment-cleanup-design.md`

## Global Constraints

- Branch `doc-cleanup`, no worktree, no push, no merge.
- Files are changed only with Edit/Write (user rule), except `nix fmt` output.
- Commit messages: subject line only, no body, no Claude attribution.
- Out of scope: `LICENSE`, `flake.lock`, JSON, `android/`, `assets/`, `secrets/`, `patches/`, `*.md` (except `docs/superpowers/comment-review.md`).
- Unverifiable why-notes stay untouched and go to `docs/superpowers/comment-review.md`.
- All prescriptive rules are deleted.

## Review Focus

1. Comment lines inside Nix strings or heredocs that become generated config: removal changes the generated file. Expected: only comment text changes; Step 2 of each area flags these as REVIEW for a line-by-line look.
2. Tool-read comments (shellcheck directives, statix/deadnix pragmas, LuaLS `---@` annotations): removal silently changes lint or editor behavior. Expected: kept. `just ci` in each area catches lint fallout; the final review greps for removed directives.
3. A why-note deleted as "obsolete" whose claim was actually still true. Expected: deleted only when verified false. The final opus review samples deleted why-notes against the code.
4. Files the checker handles in line mode (`.in`, `.scss`, `.zsh`, YAML, TOML, plymouth): a trailing comment edit on a code line shows as REVIEW. Expected: the reviewer accepts it only if the code part is byte-identical.
5. Agent drift outside its area or reformatting of untouched lines. Expected: none; Step 3 of each area checks the file list.

---

## Subagent prompt

Used by Tasks 2 to 9. Replace `{AREA}`, `{LIST}`, `{NOTES}`.

```text
You are cleaning code comments in the NixOS dotfiles repo at ~/.dotfiles, branch `doc-cleanup`. Read the spec first: docs/superpowers/specs/2026-11-26-comment-cleanup-design.md. Follow ponytail.

Your area: {AREA}. Files: run `{LIST}`. Edit only those files, only with the Edit tool. Never change code, only comments. Do not commit.

Rules (the spec wins on conflict):
- Default is delete. Keep a comment only if it fits a keep category; trim every survivor to the fewest words that keep its meaning.
- Keep: verified why/workaround notes that are needed; tool-read comments (shebang, shellcheck, statix/deadnix pragmas, noqa, LuaLS ---@ annotations, modelines); URL or issue references behind a pin, hash or workaround; license headers; section banners shortened to one line like `# Audio`.
- Delete: comments restating the code; commented-out code; history notes; every prescriptive rule ("always", "never", "do not change", "keep in sync"); speculation.
- Verify each why-note against the code and repo (does the referenced code, option, file, version still exist and behave as claimed?). Verified and needed: keep trimmed. Verified false or obsolete: delete. Cannot verify from the repo (hardware quirk, unlinked upstream bug, timing): leave it exactly as is and report it.
- Comments inside Nix strings or heredocs that become generated files follow the same rules.
- Do not reformat code, do not reflow lines you did not touch, do not leave double blank lines where a comment block was removed.

Area notes: {NOTES}

Reply with only:
1. Files changed (count) and comment lines removed/trimmed (rough counts).
2. Unverifiable notes, one per line: `path:line | comment text | why it cannot be verified`.
3. Files skipped and why.
```

### Task 1: Comment-only checker and review list

**Files:**
- Create: `~/.cache/comment-cleanup/check-comments.py` (outside the repo, deleted after Task 10)
- Create: `~/.cache/comment-cleanup/test_check_comments.py`
- Create: `docs/superpowers/comment-review.md`

**Interfaces:**
- Produces: `python3 ~/.cache/comment-cleanup/check-comments.py [BASE]`, run inside the repo with `shfmt` and `luajit` on PATH. Compares every file changed since BASE (default HEAD) with its BASE version. Prints `OK path (mode)` or `REVIEW path (mode)` plus a diff; exit 0 when all OK, else 1.

- [ ] **Step 1: Write the failing test** to `~/.cache/comment-cleanup/test_check_comments.py`:

```python
import os
import subprocess
import tempfile
import unittest

CHECK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "check-comments.py")


class CheckComments(unittest.TestCase):
    def run_case(self, name, old, new):
        with tempfile.TemporaryDirectory() as d:
            subprocess.run(["git", "init", "-q", d], check=True)
            p = os.path.join(d, "sub", name)
            os.makedirs(os.path.dirname(p))
            with open(p, "w") as f:
                f.write(old)
            subprocess.run(["git", "-C", d, "add", "."], check=True)
            subprocess.run(["git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "x"], check=True)
            with open(p, "w") as f:
                f.write(new)
            r = subprocess.run(["python3", CHECK], cwd=d, capture_output=True, text=True)
            return r.returncode, r.stdout

    def assertOk(self, name, old, new):
        code, out = self.run_case(name, old, new)
        self.assertEqual(code, 0, out)

    def assertReview(self, name, old, new):
        code, out = self.run_case(name, old, new)
        self.assertEqual(code, 1, out)
        self.assertIn("REVIEW", out)

    def test_nix_comment_removed(self):
        self.assertOk("a.nix", "# why\n{ x = 1; # trailing\n}\n", "{ x = 1; }\n")

    def test_nix_code_changed(self):
        self.assertReview("a.nix", "# why\n{ x = 1; }\n", "{ x = 2; }\n")

    def test_nix_comment_inside_string_changed(self):
        self.assertReview("a.nix", "{ s = ''\n  # generated comment\n  a\n''; }\n", "{ s = ''\n  a\n''; }\n")

    def test_nix_relative_path_literal(self):
        self.assertOk("a.nix", "# c\n{ p = ./foo; }\n", "{ p = ./foo; }\n")

    def test_sh_comments_removed(self):
        self.assertOk("a.sh", "#!/usr/bin/env bash\n# why\necho hi # trailing\n", "#!/usr/bin/env bash\necho hi\n")

    def test_sh_code_changed(self):
        self.assertReview("a.sh", "#!/usr/bin/env bash\necho hi\n", "#!/usr/bin/env bash\necho bye\n")

    def test_lua_comment_removed(self):
        self.assertOk("a.lua", "-- why\nlocal x = 1\nreturn x\n", "local x = 1\nreturn x\n")

    def test_lua_code_changed(self):
        self.assertReview("a.lua", "local x = 1\nreturn x\n", "local x = 2\nreturn x\n")

    def test_py_comment_removed(self):
        self.assertOk("a.py", "# why\nx = 1  # t\n", "x = 1\n")

    def test_py_docstring_changed(self):
        self.assertReview("a.py", 'def f():\n    """Doc."""\n', 'def f():\n    pass\n')

    def test_scss_comment_removed(self):
        self.assertOk("a.scss", "// why\n#id { color: red; }\n", "#id { color: red; }\n")

    def test_scss_code_changed(self):
        self.assertReview("a.scss", "#id { color: red; }\n", "#id { color: blue; }\n")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd ~/.cache/comment-cleanup && nix shell nixpkgs#shfmt nixpkgs#luajit -c python3 -m unittest test_check_comments -v`
Expected: FAIL, every case, `can't open file .../check-comments.py`.

- [ ] **Step 3: Write the checker** to `~/.cache/comment-cleanup/check-comments.py`:

```python
#!/usr/bin/env python3
"""Exit 1 if any file changed since BASE (default HEAD) differs in more than comments."""
import ast
import difflib
import os
import subprocess
import sys
import tempfile

MARKERS = {
    ".nix": ("#",), ".sh": ("#",), ".zsh": ("#",), ".py": ("#",), ".toml": ("#",),
    ".yml": ("#",), ".yaml": ("#",), ".jq": ("#",), ".ini": ("#", ";"),
    ".lua": ("--",), ".scss": ("//",), ".mjs": ("//",), ".js": ("//",), ".qml": ("//",),
}
DEFAULT_MARKERS = ("#", "//")


def run(cmd, src, cwd=None):
    return subprocess.run(cmd, input=src, cwd=cwd, capture_output=True, text=True, check=True).stdout


def git(root, *args):
    return subprocess.run(["git", *args], cwd=root, capture_output=True, text=True, check=True).stdout


def luajit(src):
    with tempfile.TemporaryDirectory() as d:
        i, o = os.path.join(d, "in.lua"), os.path.join(d, "out")
        with open(i, "w") as f:
            f.write(src)
        subprocess.run(["luajit", "-b", "-s", i, o], check=True, capture_output=True)
        with open(o, "rb") as f:
            return f.read().hex()


def semantic(path, src, root):
    ext = os.path.splitext(path)[1]
    if ext == ".nix":
        return run(["nix-instantiate", "--parse", "-"], src, cwd=os.path.join(root, os.path.dirname(path)))
    if ext == ".sh":
        return run(["shfmt", "-mn", "-ln", "bash"], src)
    if ext == ".py":
        return ast.dump(ast.parse(src))
    if ext == ".lua":
        return luajit(src)
    return None


def strip_lines(path, src):
    markers = MARKERS.get(os.path.splitext(path)[1], DEFAULT_MARKERS)
    return "".join(
        line.rstrip() + "\n"
        for line in src.splitlines()
        if line.strip() and not line.strip().startswith(markers)
    )


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
    root = git(".", "rev-parse", "--show-toplevel").strip()
    bad = 0
    for entry in git(root, "diff", "--name-status", base).splitlines():
        status, path = entry.split("\t")[0], entry.split("\t")[-1]
        if status != "M":
            print(f"REVIEW {path}: status {status}")
            bad = 1
            continue
        old = git(root, "show", f"{base}:{path}")
        with open(os.path.join(root, path)) as f:
            new = f.read()
        mode = "semantic"
        try:
            o, n = semantic(path, old, root), semantic(path, new, root)
        except Exception:
            o = n = None
        if o is None or n is None:
            mode = "lines"
            o, n = strip_lines(path, old), strip_lines(path, new)
        if o == n:
            print(f"OK     {path} ({mode})")
            continue
        bad = 1
        print(f"REVIEW {path} ({mode})")
        sys.stdout.writelines(difflib.unified_diff(o.splitlines(True), n.splitlines(True), "old", "new", n=1))
    sys.exit(bad)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run tests to verify they pass** (same command as Step 2). Expected: 12 tests OK.
- [ ] **Step 5: Create the review list** `docs/superpowers/comment-review.md`:

```markdown
# Comment review list

Why/workaround notes that could not be verified from the repo. They are unchanged in the code.
For each: keep, trim, or delete. This file is deleted before `doc-cleanup` merges.
```

- [ ] **Step 6: Commit**

```bash
cd ~/.dotfiles && git add docs/superpowers/comment-review.md && git commit -m "Add review list for unverifiable comments"
```

### Task 2: Area 1, modules/nixos

**Files:**
- Modify: comment lines in files from `git ls-files modules/nixos`
- Modify: `docs/superpowers/comment-review.md` (append section `## modules/nixos`)

**Interfaces:**
- Consumes: `~/.cache/comment-cleanup/check-comments.py` (Task 1), `docs/superpowers/comment-review.md` (Task 1)
- Produces: one commit `Trim comments in modules/nixos`

Notes: Largest file `modules/nixos/common/claude.nix` (52 comment lines).

- [ ] **Step 1: Dispatch the cleaner.** `Agent`, `model: "sonnet"`, prompt = the Subagent prompt with `{AREA}` = `modules/nixos`, `{LIST}` = `git ls-files modules/nixos`, `{NOTES}` = the notes above.
- [ ] **Step 2: Run the comment-only check.**

Run: `cd ~/.dotfiles && nix shell nixpkgs#shfmt nixpkgs#luajit -c python3 ~/.cache/comment-cleanup/check-comments.py HEAD`
Expected: every file `OK`. For each `REVIEW` file read the shown diff. Accept only if every differing line is comment text inside a string or heredoc, or a docstring. Revert anything else with Edit.

- [ ] **Step 3: Check scope.** Run `git -C ~/.dotfiles diff --stat HEAD`. Expected: only files from `git ls-files modules/nixos` (plus nothing else). Revert stray edits.
- [ ] **Step 4: Lint and test.**

Run: `cd ~/.dotfiles && just ci`
Expected: exit 0. On `nixfmt` failure only: run `nix fmt -- <listed files>`, re-run Steps 2 and 4.

- [ ] **Step 5: Record unverifiable notes.** Append the agent's list to `docs/superpowers/comment-review.md` under `## modules/nixos`, one line each: `- \`path:line\` comment text. Reason.`. Write `- none` if empty. Spot-check 3 entries: each comment is still present in the file, unchanged.
- [ ] **Step 6: Commit.**

```bash
cd ~/.dotfiles && git add -A -- modules/nixos docs/superpowers/comment-review.md && git commit -m "Trim comments in modules/nixos"
```

### Task 3: Area 2, modules/home

**Files:**
- Modify: comment lines in files from `git ls-files modules/home`
- Modify: `docs/superpowers/comment-review.md` (append section `## modules/home`)

**Interfaces:**
- Consumes: `~/.cache/comment-cleanup/check-comments.py` (Task 1), `docs/superpowers/comment-review.md` (Task 1)
- Produces: one commit `Trim comments in modules/home`

Notes: Heavy files: `desktop/spt.nix` (100), `desktop/illogical-impulse.nix` (68), `desktop/tarkov-common.nix` (63), `desktop/recording.nix` (61), `desktop/ii-settings.nix`, `desktop/hypr-config.nix`. Many comments sit inside Nix strings that become Hyprland/Lua/shell config: expect REVIEW lines from the checker there.

- [ ] **Step 1: Dispatch the cleaner.** `Agent`, `model: "sonnet"`, prompt = the Subagent prompt with `{AREA}` = `modules/home`, `{LIST}` = `git ls-files modules/home`, `{NOTES}` = the notes above.
- [ ] **Step 2: Run the comment-only check.**

Run: `cd ~/.dotfiles && nix shell nixpkgs#shfmt nixpkgs#luajit -c python3 ~/.cache/comment-cleanup/check-comments.py HEAD`
Expected: every file `OK`. For each `REVIEW` file read the shown diff. Accept only if every differing line is comment text inside a string or heredoc, or a docstring. Revert anything else with Edit.

- [ ] **Step 3: Check scope.** Run `git -C ~/.dotfiles diff --stat HEAD`. Expected: only files from `git ls-files modules/home` (plus nothing else). Revert stray edits.
- [ ] **Step 4: Lint and test.**

Run: `cd ~/.dotfiles && just ci`
Expected: exit 0. On `nixfmt` failure only: run `nix fmt -- <listed files>`, re-run Steps 2 and 4.

- [ ] **Step 5: Record unverifiable notes.** Append the agent's list to `docs/superpowers/comment-review.md` under `## modules/home`, one line each: `- \`path:line\` comment text. Reason.`. Write `- none` if empty. Spot-check 3 entries: each comment is still present in the file, unchanged.
- [ ] **Step 6: Commit.**

```bash
cd ~/.dotfiles && git add -A -- modules/home docs/superpowers/comment-review.md && git commit -m "Trim comments in modules/home"
```

### Task 4: Area 3, modules/nixvim

**Files:**
- Modify: comment lines in files from `git ls-files modules/nixvim`
- Modify: `docs/superpowers/comment-review.md` (append section `## modules/nixvim`)

**Interfaces:**
- Consumes: `~/.cache/comment-cleanup/check-comments.py` (Task 1), `docs/superpowers/comment-review.md` (Task 1)
- Produces: one commit `Trim comments in modules/nixvim`

Notes: Includes Lua and Lua specs (`lua/dynamic-theme.lua`, `tests/*_spec.lua`). Keep LuaLS annotations (`---@type`, `---@param`, ...): tools read them.

- [ ] **Step 1: Dispatch the cleaner.** `Agent`, `model: "sonnet"`, prompt = the Subagent prompt with `{AREA}` = `modules/nixvim`, `{LIST}` = `git ls-files modules/nixvim`, `{NOTES}` = the notes above.
- [ ] **Step 2: Run the comment-only check.**

Run: `cd ~/.dotfiles && nix shell nixpkgs#shfmt nixpkgs#luajit -c python3 ~/.cache/comment-cleanup/check-comments.py HEAD`
Expected: every file `OK`. For each `REVIEW` file read the shown diff. Accept only if every differing line is comment text inside a string or heredoc, or a docstring. Revert anything else with Edit.

- [ ] **Step 3: Check scope.** Run `git -C ~/.dotfiles diff --stat HEAD`. Expected: only files from `git ls-files modules/nixvim` (plus nothing else). Revert stray edits.
- [ ] **Step 4: Lint and test.**

Run: `cd ~/.dotfiles && just ci`
Expected: exit 0. On `nixfmt` failure only: run `nix fmt -- <listed files>`, re-run Steps 2 and 4.

- [ ] **Step 5: Record unverifiable notes.** Append the agent's list to `docs/superpowers/comment-review.md` under `## modules/nixvim`, one line each: `- \`path:line\` comment text. Reason.`. Write `- none` if empty. Spot-check 3 entries: each comment is still present in the file, unchanged.
- [ ] **Step 6: Commit.**

```bash
cd ~/.dotfiles && git add -A -- modules/nixvim docs/superpowers/comment-review.md && git commit -m "Trim comments in modules/nixvim"
```

### Task 5: Area 4, hosts and templates

**Files:**
- Modify: comment lines in files from `git ls-files hosts templates`
- Modify: `docs/superpowers/comment-review.md` (append section `## hosts and templates`)

**Interfaces:**
- Consumes: `~/.cache/comment-cleanup/check-comments.py` (Task 1), `docs/superpowers/comment-review.md` (Task 1)
- Produces: one commit `Trim comments in hosts and templates`

Notes: Skip `hosts/*/hardware-configuration.nix` (generated). In `templates/`, keep placeholder hints that tell the reader what to fill in, trimmed.

- [ ] **Step 1: Dispatch the cleaner.** `Agent`, `model: "sonnet"`, prompt = the Subagent prompt with `{AREA}` = `hosts and templates`, `{LIST}` = `git ls-files hosts templates`, `{NOTES}` = the notes above.
- [ ] **Step 2: Run the comment-only check.**

Run: `cd ~/.dotfiles && nix shell nixpkgs#shfmt nixpkgs#luajit -c python3 ~/.cache/comment-cleanup/check-comments.py HEAD`
Expected: every file `OK`. For each `REVIEW` file read the shown diff. Accept only if every differing line is comment text inside a string or heredoc, or a docstring. Revert anything else with Edit.

- [ ] **Step 3: Check scope.** Run `git -C ~/.dotfiles diff --stat HEAD`. Expected: only files from `git ls-files hosts templates` (plus nothing else). Revert stray edits.
- [ ] **Step 4: Lint and test.**

Run: `cd ~/.dotfiles && just ci`
Expected: exit 0. On `nixfmt` failure only: run `nix fmt -- <listed files>`, re-run Steps 2 and 4.

- [ ] **Step 5: Record unverifiable notes.** Append the agent's list to `docs/superpowers/comment-review.md` under `## hosts and templates`, one line each: `- \`path:line\` comment text. Reason.`. Write `- none` if empty. Spot-check 3 entries: each comment is still present in the file, unchanged.
- [ ] **Step 6: Commit.**

```bash
cd ~/.dotfiles && git add -A -- hosts templates docs/superpowers/comment-review.md && git commit -m "Trim comments in hosts and templates"
```

### Task 6: Area 5, lib, flake.nix, overlays

**Files:**
- Modify: comment lines in files from `git ls-files lib overlays flake.nix`
- Modify: `docs/superpowers/comment-review.md` (append section `## lib, flake.nix, overlays`)

**Interfaces:**
- Consumes: `~/.cache/comment-cleanup/check-comments.py` (Task 1), `docs/superpowers/comment-review.md` (Task 1)
- Produces: one commit `Trim comments in lib, flake.nix and overlays`

Notes: `flake.nix` has 139 comment lines; `lib/mk-host.nix` 70.

- [ ] **Step 1: Dispatch the cleaner.** `Agent`, `model: "sonnet"`, prompt = the Subagent prompt with `{AREA}` = `lib, flake.nix, overlays`, `{LIST}` = `git ls-files lib overlays flake.nix`, `{NOTES}` = the notes above.
- [ ] **Step 2: Run the comment-only check.**

Run: `cd ~/.dotfiles && nix shell nixpkgs#shfmt nixpkgs#luajit -c python3 ~/.cache/comment-cleanup/check-comments.py HEAD`
Expected: every file `OK`. For each `REVIEW` file read the shown diff. Accept only if every differing line is comment text inside a string or heredoc, or a docstring. Revert anything else with Edit.

- [ ] **Step 3: Check scope.** Run `git -C ~/.dotfiles diff --stat HEAD`. Expected: only files from `git ls-files lib overlays flake.nix` (plus nothing else). Revert stray edits.
- [ ] **Step 4: Lint and test.**

Run: `cd ~/.dotfiles && just ci`
Expected: exit 0. On `nixfmt` failure only: run `nix fmt -- <listed files>`, re-run Steps 2 and 4.

- [ ] **Step 5: Record unverifiable notes.** Append the agent's list to `docs/superpowers/comment-review.md` under `## lib, flake.nix, overlays`, one line each: `- \`path:line\` comment text. Reason.`. Write `- none` if empty. Spot-check 3 entries: each comment is still present in the file, unchanged.
- [ ] **Step 6: Commit.**

```bash
cd ~/.dotfiles && git add -A -- lib overlays flake.nix docs/superpowers/comment-review.md && git commit -m "Trim comments in lib, flake.nix and overlays"
```

### Task 7: Area 6, scripts, install.sh, justfile, .github

**Files:**
- Modify: comment lines in files from `git ls-files scripts install.sh justfile .github`
- Modify: `docs/superpowers/comment-review.md` (append section `## scripts, install.sh, justfile, .github`)

**Interfaces:**
- Consumes: `~/.cache/comment-cleanup/check-comments.py` (Task 1), `docs/superpowers/comment-review.md` (Task 1)
- Produces: one commit `Trim comments in scripts, install.sh, justfile and CI`

Notes: `install.sh` has 451 comment lines: split it across two subagents (lines 1 to the middle function boundary, then the rest) if one context cannot hold it. `justfile` recipe comments are shown by `just --list`: keep them, trimmed. Heredoc bodies are file content: same rules, checker flags them.

- [ ] **Step 1: Dispatch the cleaner.** `Agent`, `model: "sonnet"`, prompt = the Subagent prompt with `{AREA}` = `scripts, install.sh, justfile, .github`, `{LIST}` = `git ls-files scripts install.sh justfile .github`, `{NOTES}` = the notes above.
- [ ] **Step 2: Run the comment-only check.**

Run: `cd ~/.dotfiles && nix shell nixpkgs#shfmt nixpkgs#luajit -c python3 ~/.cache/comment-cleanup/check-comments.py HEAD`
Expected: every file `OK`. For each `REVIEW` file read the shown diff. Accept only if every differing line is comment text inside a string or heredoc, or a docstring. Revert anything else with Edit.

- [ ] **Step 3: Check scope.** Run `git -C ~/.dotfiles diff --stat HEAD`. Expected: only files from `git ls-files scripts install.sh justfile .github` (plus nothing else). Revert stray edits.
- [ ] **Step 4: Lint and test.**

Run: `cd ~/.dotfiles && just ci`
Expected: exit 0. On `nixfmt` failure only: run `nix fmt -- <listed files>`, re-run Steps 2 and 4.

- [ ] **Step 5: Record unverifiable notes.** Append the agent's list to `docs/superpowers/comment-review.md` under `## scripts, install.sh, justfile, .github`, one line each: `- \`path:line\` comment text. Reason.`. Write `- none` if empty. Spot-check 3 entries: each comment is still present in the file, unchanged.
- [ ] **Step 6: Commit.**

```bash
cd ~/.dotfiles && git add -A -- scripts install.sh justfile .github docs/superpowers/comment-review.md && git commit -m "Trim comments in scripts, install.sh, justfile and CI"
```

### Task 8: Area 7, pkgs

**Files:**
- Modify: comment lines in files from `git ls-files pkgs`
- Modify: `docs/superpowers/comment-review.md` (append section `## pkgs`)

**Interfaces:**
- Consumes: `~/.cache/comment-cleanup/check-comments.py` (Task 1), `docs/superpowers/comment-review.md` (Task 1)
- Produces: one commit `Trim comments in pkgs`

Notes: `pkgs/krane-ii-settings/krane_ii_settings.py` (36): docstrings count as comments; the checker flags docstring edits as REVIEW, which is expected.

- [ ] **Step 1: Dispatch the cleaner.** `Agent`, `model: "sonnet"`, prompt = the Subagent prompt with `{AREA}` = `pkgs`, `{LIST}` = `git ls-files pkgs`, `{NOTES}` = the notes above.
- [ ] **Step 2: Run the comment-only check.**

Run: `cd ~/.dotfiles && nix shell nixpkgs#shfmt nixpkgs#luajit -c python3 ~/.cache/comment-cleanup/check-comments.py HEAD`
Expected: every file `OK`. For each `REVIEW` file read the shown diff. Accept only if every differing line is comment text inside a string or heredoc, or a docstring. Revert anything else with Edit.

- [ ] **Step 3: Check scope.** Run `git -C ~/.dotfiles diff --stat HEAD`. Expected: only files from `git ls-files pkgs` (plus nothing else). Revert stray edits.
- [ ] **Step 4: Lint and test.**

Run: `cd ~/.dotfiles && just ci`
Expected: exit 0. On `nixfmt` failure only: run `nix fmt -- <listed files>`, re-run Steps 2 and 4.

- [ ] **Step 5: Record unverifiable notes.** Append the agent's list to `docs/superpowers/comment-review.md` under `## pkgs`, one line each: `- \`path:line\` comment text. Reason.`. Write `- none` if empty. Spot-check 3 entries: each comment is still present in the file, unchanged.
- [ ] **Step 6: Commit.**

```bash
cd ~/.dotfiles && git add -A -- pkgs docs/superpowers/comment-review.md && git commit -m "Trim comments in pkgs"
```

### Task 9: Area 8, rest

**Files:**
- Modify: comment lines in files from `git ls-files tests config .sops.yaml statix.toml .gitignore .gitattributes .envrc`
- Modify: `docs/superpowers/comment-review.md` (append section `## rest`)

**Interfaces:**
- Consumes: `~/.cache/comment-cleanup/check-comments.py` (Task 1), `docs/superpowers/comment-review.md` (Task 1)
- Produces: one commit `Trim comments in tests, config and root files`

Notes: `config/zsh/p10k.zsh` is generated by the powerlevel10k wizard: leave it untouched and list it as skipped. `.gitignore`/`.gitattributes` entry comments usually just label the next line: delete those.

- [ ] **Step 1: Dispatch the cleaner.** `Agent`, `model: "sonnet"`, prompt = the Subagent prompt with `{AREA}` = `rest`, `{LIST}` = `git ls-files tests config .sops.yaml statix.toml .gitignore .gitattributes .envrc`, `{NOTES}` = the notes above.
- [ ] **Step 2: Run the comment-only check.**

Run: `cd ~/.dotfiles && nix shell nixpkgs#shfmt nixpkgs#luajit -c python3 ~/.cache/comment-cleanup/check-comments.py HEAD`
Expected: every file `OK`. For each `REVIEW` file read the shown diff. Accept only if every differing line is comment text inside a string or heredoc, or a docstring. Revert anything else with Edit.

- [ ] **Step 3: Check scope.** Run `git -C ~/.dotfiles diff --stat HEAD`. Expected: only files from `git ls-files tests config .sops.yaml statix.toml .gitignore .gitattributes .envrc` (plus nothing else). Revert stray edits.
- [ ] **Step 4: Lint and test.**

Run: `cd ~/.dotfiles && just ci`
Expected: exit 0. On `nixfmt` failure only: run `nix fmt -- <listed files>`, re-run Steps 2 and 4.

- [ ] **Step 5: Record unverifiable notes.** Append the agent's list to `docs/superpowers/comment-review.md` under `## rest`, one line each: `- \`path:line\` comment text. Reason.`. Write `- none` if empty. Spot-check 3 entries: each comment is still present in the file, unchanged.
- [ ] **Step 6: Commit.**

```bash
cd ~/.dotfiles && git add -A -- tests config .sops.yaml statix.toml .gitignore .gitattributes .envrc docs/superpowers/comment-review.md && git commit -m "Trim comments in tests, config and root files"
```

### Task 10: Whole-stage verification and review

**Files:**
- Read only: everything changed since `160c49c`

**Interfaces:**
- Consumes: the eight area commits and `docs/superpowers/comment-review.md`

- [ ] **Step 1: Whole-stage comment check.** Run: `cd ~/.dotfiles && nix shell nixpkgs#shfmt nixpkgs#luajit -c python3 ~/.cache/comment-cleanup/check-comments.py 160c49c`. Expected: every REVIEW file was already accepted in its area task; the new plan and review list under `docs/superpowers/` show as `status A`, which is expected.
- [ ] **Step 2: Directive check.** Run: `git -C ~/.dotfiles diff 160c49c -- . ':!docs' | grep -E '^-.*(shellcheck|statix|deadnix|noqa|---@|#!|vim:)'`. Expected: no output, or each hit moved, not removed.
- [ ] **Step 3: Host evaluation and flake checks** (includes the `krane-ii-settings` unittest suite, `flake.nix:765`). Run: `cd ~/.dotfiles && just check`. Expected: exit 0.
- [ ] **Step 4: Installer test**, only if `install.sh` changed. Run: `cd ~/.dotfiles && just install-test`. Expected: exit 0.
- [ ] **Step 5: Opus review.** `Agent`, `model: "opus"`: review `git diff 160c49c..HEAD` against the spec. Check: every surviving comment fits a keep category; sample 15 deleted why-notes and confirm each was false, obsolete or restated the code; no prescriptive rules remain (`grep -rnE '#.*\b(always|never|do not|don.t|must|keep in sync)\b'` over in-scope files); review-list entries are unchanged in the code. Fix confirmed findings with Edit, re-run Steps 1 to 3, commit `Fix comment cleanup review findings`.
- [ ] **Step 6: Hand off.** Tell the user: commit range, comment lines before/after (`git ls-files | grep -E '\.(nix|lua|sh|py)$' | grep -vE '^(patches|android|assets|secrets)/' | xargs grep -hcE '^\s*(#|--)' | paste -sd+ | bc` at `160c49c` and HEAD), review-list path and entry count, anything skipped. Delete `~/.cache/comment-cleanup` after the user is done with the review list.
