// Tests for services/claude-agents.js in a dots-hyprland checkout.
// Usage: node test-logic.mjs [<ii root>]   (default: the krane clone)
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { test } from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";

const iiRoot = process.argv[2] ?? `${homedir()}/src/dots-hyprland/dots/.config/quickshell/ii`;
const ctx = vm.createContext({});
vm.runInContext(readFileSync(`${iiRoot}/services/claude-agents.js`, "utf8"), ctx);
const L = ctx;
const plain = v => JSON.parse(JSON.stringify(v));

const kitty = (pid, address, title, focusHistoryID) => ({ pid, address, title, focusHistoryID });

test("stripSpinner removes the busy and idle prefixes only", () => {
    assert.equal(L.stripSpinner("◑ Ricing ideas"), "Ricing ideas");
    assert.equal(L.stripSpinner("✳ Ricing ideas"), "Ricing ideas");
    assert.equal(L.stripSpinner("Ricing ideas"), "Ricing ideas");
    assert.equal(L.stripSpinner("~/src: fish"), "~/src: fish");
    assert.equal(L.stripSpinner(undefined), "");
});

test("interactive: first ancestor owning a window wins", () => {
    const s = { kind: "interactive", name: "a", ancestors: [3127, 3000, 2840, 900] };
    const w = L.matchWindow(s, [kitty(2840, "0xa", "✳ a", 1), kitty(900, "0xh", "Hyprland", 0)]);
    assert.equal(w.address, "0xa");
});

test("interactive: several windows of one process pick the title match", () => {
    const s = { kind: "interactive", name: "second", ancestors: [5, 4, 2840] };
    const w = L.matchWindow(s, [kitty(2840, "0x1", "✳ first", 0), kitty(2840, "0x2", "◐ second", 3)]);
    assert.equal(w.address, "0x2");
});

test("interactive: no or ambiguous title match falls back to most recently focused", () => {
    const s = { kind: "interactive", name: "zzz", ancestors: [2840] };
    const wins = [kitty(2840, "0x1", "✳ a", 4), kitty(2840, "0x2", "✳ b", 2)];
    assert.equal(L.matchWindow(s, wins).address, "0x2");
});

test("interactive: no window owner means null (headless)", () => {
    const s = { kind: "interactive", name: "obs", ancestors: [77, 1234] };
    assert.equal(L.matchWindow(s, [kitty(2840, "0x1", "✳ obs", 0)]), null);
});

test("background: exactly one title match or null, never ancestry", () => {
    const s = { kind: "background", name: "Ricing ideas", ancestors: [] };
    assert.equal(L.matchWindow(s, [kitty(1, "0x1", "◑ Ricing ideas", 0)]).address, "0x1");
    assert.equal(L.matchWindow(s, [kitty(1, "0x1", "◑ Ricing ideas", 0), kitty(2, "0x2", "✳ Ricing ideas", 1)]), null);
    assert.equal(L.matchWindow(s, []), null);
});

test("background with an empty name never matches an empty title", () => {
    const s = { kind: "background", name: "", ancestors: [] };
    assert.equal(L.matchWindow(s, [kitty(1, "0x1", "", 0)]), null);
});

test("background: two sessions with one name never borrow each other's window", () => {
    const wins = [kitty(1, "0x1", "◑ same-name", 0)];
    const entries = [
        { kind: "background", name: "same-name", id: "aaaa1111", status: "busy", ancestors: [] },
        { kind: "background", name: "same-name", id: "bbbb2222", status: "idle", ancestors: [] },
    ];
    const r = plain(L.annotate(entries, wins));
    assert.deepEqual(r.sessions.map(s => s.window), [null, null]);
    assert.deepEqual(r.sessions.map(s => s.rowKey), ["aaaa1111", "bbbb2222"]);
    assert.equal(L.matchWindow(entries[0], wins, false), null);
});

test("computeRowKey prefers sessionId, falls back to id, then to kind+pid+index", () => {
    assert.equal(L.computeRowKey({ kind: "interactive", sessionId: "sess-a", pid: 100 }, 0), "sess-a");
    assert.equal(L.computeRowKey({ kind: "background", sessionId: "-", id: "bg-1", pid: 200 }, 1), "bg-1");
    // No sessionId (or "-") and no id: same kind and pid, but distinct index, must stay unique.
    const a = L.computeRowKey({ kind: "background", sessionId: "-", pid: 300 }, 2);
    const b = L.computeRowKey({ kind: "background", pid: 300 }, 3);
    assert.notEqual(a, b);
});

test("effectiveStatus maps background state and keeps unknown values raw", () => {
    assert.equal(L.effectiveStatus({ status: "waiting" }), "waiting");
    assert.equal(L.effectiveStatus({ state: "blocked" }), "waiting");
    assert.equal(L.effectiveStatus({ state: "working" }), "busy");
    assert.equal(L.effectiveStatus({ state: "failed" }), "done");
    assert.equal(L.effectiveStatus({ status: "pondering" }), "pondering");
    assert.equal(L.effectiveStatus({}), "unknown");
});

test("annotate drops headless interactive sessions, counts them, and sorts", () => {
    const wins = [kitty(10, "0xa", "✳ idle-one", 0), kitty(20, "0xb", "✳ busy-one", 1), kitty(30, "0xc", "✳ wait-one", 2)];
    const entries = [
        { kind: "interactive", name: "idle-one", status: "idle", ancestors: [11, 10], lastActivity: 300 },
        { kind: "interactive", name: "busy-one", status: "busy", ancestors: [21, 20], lastActivity: 100 },
        { kind: "interactive", name: "wait-one", status: "waiting", waitingFor: "permission prompt", ancestors: [31, 30], lastActivity: 50 },
        { kind: "interactive", name: "observer", status: "busy", ancestors: [99, 1500], lastActivity: 999 },
        { kind: "background", name: "bg-job", state: "working", status: "busy", ancestors: [], startedAt: 50000, lastActivity: null },
    ];
    const r = plain(L.annotate(entries, wins));
    assert.equal(r.headlessCount, 1);
    assert.deepEqual(r.sessions.map(s => s.name), ["wait-one", "busy-one", "bg-job", "idle-one"]);
    assert.equal(r.sessions[3].window.address, "0xa");
    assert.equal(r.sessions[2].window, null);
});

test("classifyResult: 3 is missing, 127 is an ordinary error, bad JSON is an error that stops on the third", () => {
    assert.equal(L.classifyResult(3, "", "", 0).kind, "missing");
    const notFound = L.classifyResult(127, "", "exec: claude: not found", 0);
    assert.equal(notFound.kind, "error");
    assert.equal(notFound.message, "exec: claude: not found");
    const ok = L.classifyResult(0, '[{"kind":"background"}]', "", 0);
    assert.equal(ok.kind, "ok");
    assert.equal(ok.entries.length, 1);
    const bad = L.classifyResult(0, "not json", "", 0);
    assert.equal(bad.kind, "error");
    assert.equal(bad.stop, false);
    assert.equal(L.classifyResult(0, "{}", "", 2).stop, true);
    assert.equal(L.classifyResult(1, "", "boom\nmore", 0).message, "boom");
});

test("nextInterval doubles slow runs up to 15 s and resets after a fast one", () => {
    assert.equal(L.nextInterval(3000, 1500), 6000);
    assert.equal(L.nextInterval(12000, 1500), 15000);
    assert.equal(L.nextInterval(15000, 200), 3000);
});

test("subtitle: bg marker, activity or start time (no cwd basename; the group header carries it)", () => {
    const now = 1_000_000_000;
    assert.equal(L.subtitle({ cwd: "/home/krane/.dotfiles", kind: "interactive", lastActivity: (now - 120_000) / 1000 }, now), "2 min ago");
    assert.equal(L.subtitle({ cwd: "/home/krane/src/x/", kind: "background", lastActivity: null, startedAt: now - 7_200_000 }, now), "bg · started 2 h ago");
});

test("subtitle is empty for an interactive session with no lastActivity and no startedAt", () => {
    const now = 1_000_000_000;
    assert.equal(L.subtitle({ cwd: "/home/krane/proj", kind: "interactive" }, now), "");
});

test("tildePath replaces only a whole leading home path component", () => {
    assert.equal(L.tildePath("/home/krane", "/home/krane"), "~");
    assert.equal(L.tildePath("/home/krane/.dotfiles", "/home/krane"), "~/.dotfiles");
    // Prefix lookalike: "/home/kranex" is not "/home/krane" plus more.
    assert.equal(L.tildePath("/home/kranex/foo", "/home/krane"), "/home/kranex/foo");
    assert.equal(L.tildePath("/home/krane/foo", ""), "/home/krane/foo");
    assert.equal(L.tildePath("/home/krane/foo", undefined), "/home/krane/foo");
    // Directories.home carries a "file://" prefix and may have a trailing slash.
    assert.equal(L.tildePath("/home/krane/foo", "file:///home/krane"), "~/foo");
    assert.equal(L.tildePath("/home/krane/foo", "/home/krane/"), "~/foo");
});

test("tildePath normalizes repeated slashes, \".\" segments, and a trailing slash on the path", () => {
    assert.equal(L.tildePath("/home/krane/src/x/", "/home/krane"), "~/src/x");
    assert.equal(L.tildePath("/home/krane/src/x", "/home/krane"), "~/src/x");
    assert.equal(L.tildePath("/home/krane/src//x", "/home/krane"), "~/src/x");
    assert.equal(L.tildePath("/home/krane/./src/x", "/home/krane"), "~/src/x");
    assert.equal(L.tildePath("/home/krane/", "/home/krane"), "~");
    // "/" itself is left alone, not turned into "".
    assert.equal(L.tildePath("/", "/home/krane"), "/");
});

test("normalizePath collapses all-slash input to \"/\" and never resolves \"..\"", () => {
    assert.equal(L.normalizePath("/"), "/");
    assert.equal(L.normalizePath("//"), "/");
    assert.equal(L.normalizePath("///"), "/");
    assert.equal(L.normalizePath(""), "");
    assert.equal(L.normalizePath(undefined), "");
    // No filesystem access here, so ".." is left exactly as written, even
    // when a repeated slash next to it still gets collapsed.
    assert.equal(L.normalizePath("/home/krane/../etc"), "/home/krane/../etc");
    assert.equal(L.normalizePath("/home/krane//../etc"), "/home/krane/../etc");
});

test("tildePath does not shorten anything when home normalizes to \"/\"", () => {
    assert.equal(L.tildePath("/", "/"), "/");
    assert.equal(L.tildePath("/x", "/"), "/x");
    // Normal homes still shorten as before.
    assert.equal(L.tildePath("/home/krane", "/home/krane"), "~");
});

test("a cwd with repeated slashes, a \".\" segment, or a trailing slash all land in the same group", () => {
    const home = "/home/krane";
    const entries = [
        { kind: "background", name: "double-slash", status: "idle", cwd: "/home/krane/src//x", ancestors: [], lastActivity: 1 },
        { kind: "background", name: "dot-segment", status: "idle", cwd: "/home/krane/./src/x", ancestors: [], lastActivity: 2 },
        { kind: "background", name: "trailing-slash", status: "idle", cwd: "/home/krane/src/x/", ancestors: [], lastActivity: 3 },
        { kind: "background", name: "clean", status: "idle", cwd: "/home/krane/src/x", ancestors: [], lastActivity: 4 },
    ];
    const r = plain(L.annotate(entries, [], home));
    assert.deepEqual(r.sessions.map(s => s.group), ["~/src/x", "~/src/x", "~/src/x", "~/src/x"]);
    assert.deepEqual(r.sessions.map(s => s.groupStart), [true, false, false, false]);
});

test("cwds of \"/\", \"//\" and \"///\" all group together, labelled \"/\"", () => {
    const home = "/home/krane";
    const entries = [
        { kind: "background", name: "single", status: "idle", cwd: "/", ancestors: [], lastActivity: 1 },
        { kind: "background", name: "double", status: "idle", cwd: "//", ancestors: [], lastActivity: 2 },
        { kind: "background", name: "triple", status: "idle", cwd: "///", ancestors: [], lastActivity: 3 },
    ];
    const r = plain(L.annotate(entries, [], home));
    assert.deepEqual(r.sessions.map(s => s.group), ["/", "/", "/"]);
    assert.deepEqual(r.sessions.map(s => s.groupStart), [true, false, false]);
});

test("sessions without a cwd land in the \"?\" group, sorted like any other label", () => {
    const home = "/home/krane";
    const entries = [
        { kind: "background", name: "no-cwd", status: "idle", ancestors: [], lastActivity: 1 },
        { kind: "background", name: "aardvark-proj", status: "idle", cwd: "/home/krane/aardvark", ancestors: [], lastActivity: 1 },
    ];
    const r = plain(L.annotate(entries, [], home));
    assert.deepEqual(r.sessions.map(s => s.group), ["?", "~/aardvark"]);
});

test("groups sort waiting before busy before idle, ties by most recent activity then path", () => {
    const home = "/home/krane";
    const entries = [
        { kind: "background", name: "idle-old", status: "idle", cwd: "/home/krane/zzz", ancestors: [], lastActivity: 100 },
        { kind: "background", name: "busy-one", status: "busy", cwd: "/home/krane/busy-proj", ancestors: [], lastActivity: 200 },
        { kind: "background", name: "wait-one", status: "waiting", cwd: "/home/krane/wait-proj", ancestors: [], lastActivity: 50 },
        { kind: "background", name: "idle-new", status: "idle", cwd: "/home/krane/aaa", ancestors: [], lastActivity: 500 },
    ];
    const r = plain(L.annotate(entries, [], home));
    assert.deepEqual(r.sessions.map(s => s.group), ["~/wait-proj", "~/busy-proj", "~/aaa", "~/zzz"]);
});

test("groups tied on rank and peak activity break the tie alphabetically by path", () => {
    const home = "/home/krane";
    const entries = [
        { kind: "background", name: "z-sess", status: "idle", cwd: "/home/krane/zeta", ancestors: [], lastActivity: 100 },
        { kind: "background", name: "a-sess", status: "idle", cwd: "/home/krane/alpha", ancestors: [], lastActivity: 100 },
    ];
    const r = plain(L.annotate(entries, [], home));
    assert.deepEqual(r.sessions.map(s => s.group), ["~/alpha", "~/zeta"]);
});

test("a group's rank is the best rank among its sessions, not its peak activity", () => {
    const home = "/home/krane";
    const entries = [
        { kind: "background", name: "idle-in-mixed", status: "idle", cwd: "/home/krane/mixed", ancestors: [], lastActivity: 10 },
        { kind: "background", name: "busy-in-mixed", status: "busy", cwd: "/home/krane/mixed", ancestors: [], lastActivity: 20 },
        { kind: "background", name: "idle-alone", status: "idle", cwd: "/home/krane/alone", ancestors: [], lastActivity: 999 },
    ];
    const r = plain(L.annotate(entries, [], home));
    // "alone" has far more recent activity, but "mixed" holds a busy session, so it leads.
    assert.deepEqual([...new Set(r.sessions.map(s => s.group))], ["~/mixed", "~/alone"]);
});

test("within a group, sessions keep the existing rank-asc, activity-desc order", () => {
    const home = "/home/krane";
    const entries = [
        { kind: "background", name: "idle-old", status: "idle", cwd: "/home/krane/proj", ancestors: [], lastActivity: 10 },
        { kind: "background", name: "busy", status: "busy", cwd: "/home/krane/proj", ancestors: [], lastActivity: 20 },
        { kind: "background", name: "idle-new", status: "idle", cwd: "/home/krane/proj", ancestors: [], lastActivity: 30 },
        { kind: "background", name: "waiting", status: "waiting", cwd: "/home/krane/proj", ancestors: [], lastActivity: 5 },
    ];
    const r = plain(L.annotate(entries, [], home));
    assert.deepEqual(r.sessions.map(s => s.name), ["waiting", "busy", "idle-new", "idle-old"]);
});

test("groupStart is set exactly once per group, on its first session", () => {
    const home = "/home/krane";
    const entries = [
        { kind: "background", name: "a1", status: "idle", cwd: "/home/krane/p1", ancestors: [], lastActivity: 1 },
        { kind: "background", name: "a2", status: "busy", cwd: "/home/krane/p1", ancestors: [], lastActivity: 2 },
        { kind: "background", name: "b1", status: "idle", cwd: "/home/krane/p2", ancestors: [], lastActivity: 3 },
    ];
    const r = plain(L.annotate(entries, [], home));
    assert.deepEqual(r.sessions.map(s => s.name), ["a2", "a1", "b1"]);
    assert.deepEqual(r.sessions.map(s => s.groupStart), [true, false, true]);
    assert.equal(r.sessions.filter(s => s.groupStart).length, 2);
});

test("attachCommand opens a new kitty on the short id", () => {
    assert.deepEqual(plain(L.attachCommand({ id: "cd9c41f1" })), ["kitty", "-e", "claude", "attach", "cd9c41f1"]);
});
