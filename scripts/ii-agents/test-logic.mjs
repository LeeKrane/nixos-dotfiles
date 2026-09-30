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

test("subtitle: cwd basename, bg marker, activity or start time", () => {
    const now = 1_000_000_000;
    assert.equal(L.subtitle({ cwd: "/home/krane/.dotfiles", kind: "interactive", lastActivity: (now - 120_000) / 1000 }, now), ".dotfiles · 2 min ago");
    assert.equal(L.subtitle({ cwd: "/home/krane/src/x/", kind: "background", lastActivity: null, startedAt: now - 7_200_000 }, now), "x · bg · started 2 h ago");
});

test("attachCommand opens a new kitty on the short id", () => {
    assert.deepEqual(plain(L.attachCommand({ id: "cd9c41f1" })), ["kitty", "-e", "claude", "attach", "cd9c41f1"]);
});
