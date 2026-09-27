# Restyle and enable the ii sidebar translator

Sub-project 2 of 5 in bringing pctrade/end4-pC work into this repo's ii setup
(fixes, translator, dock, AI/agent overview, settings pages). It reuses the
delivery mechanism from sub-project 1,
`docs/superpowers/specs/2026-09-27-ii-fork-fixes-design.md`, and only states
where it differs.

## Background

Sub-project 1's Background section explains ii, Quickshell, the soymou module
and the pinned dots-hyprland input. This section only covers the translator.

- ii's left sidebar has a Translator tab (`modules/ii/sidebarLeft/Translator.qml`
  plus `translator/TextCanvas.qml` and `translator/LanguageSelectorButton.qml`).
  It shells out to `trans` (translate-shell, already on PATH on every host).
- The tab only exists when `sidebar.translator.enable` is true. The pinned
  `modules/common/Config.qml` defaults it to `false`, and the user's
  `~/.config/illogical-impulse/config.json` holds an explicit `false`. That is
  why the tab is missing.
- `config.json` is written and owned by ii and its settings GUI. ii fills keys
  that are missing from `config.json` with the QML defaults, but an explicit
  value always wins. A changed QML default therefore only reaches hosts whose
  `config.json` does not have the key yet, in practice a fresh host. ii
  watches the file (`watchChanges: true`), so edits apply live.
- Sub-project 5 (settings) later makes `~/.config/illogical-impulse` a
  symlink to `hosts/<host>/illogical-impulse/` in this repo, so `config.json`
  becomes a tracked file. ii is still the only writer and Nix never reads or
  writes it, so everything above still holds; a GUI change then also shows up
  as a repo diff to commit. A "fresh host" then means one whose repo directory
  has no `config.json` yet.
- The fork restyles the tab in two commits, `c7aaeb5` "My old translator design
  feat. ignis" and `6868389` "Translator opacity". There are no screenshots of
  it: none of the fork's six README screenshots shows the left sidebar, and the
  commits carry no links. The design is described from the diff below.

### What the fork's restyle changes

Upstream layout, top to bottom: target-language button, output box (inside a
scroll area), source-language button, input box. Every box and button uses the
neutral `colLayer2` surface.

Fork layout after `c7aaeb5` + `6868389`, top to bottom:

1. Input box, tinted with `colSecondaryContainer` at 20% opacity.
2. A centred row: source-language pill (`colSecondaryContainer`), a round swap
   button (`colTertiaryContainer`, `autorenew` icon), target-language pill
   (`colPrimaryContainer`).
3. Output box, tinted with `colPrimaryContainer` at 20% opacity, with the copy
   and web-search buttons.

The two boxes split the remaining height evenly (`Layout.fillHeight`) instead
of the input box having a 150 px minimum height. Language buttons become fully
rounded pills with extra padding. The outer scroll area is removed. The fork
also deletes most code comments; the port does not copy that, and upstream's
comments stay.

### Dependencies on other fork commits

The restyle assumes a swap-languages button and `swapLanguages()` function,
added by the fork in `4da3e83` "add swap language button translator". The pin
does not have it, so its translator hunks are needed too. `4da3e83` also
touches bar files; those hunks are dropped.

`966162c` "fixes" makes the input box's character counter null-safe
(`inputLoader.item?.text.length ?? 0`) and uses `StyledText` so it picks up the
shell font. Its translator hunks are a real fix and are included; its other
hunks are not.

`9f63cce` "tf" hardcodes `trans -e bing`. It is not ported. On 2026-09-27,
`trans -e bing -source auto -target auto` fails with "Bing does not support the
specified language(s)", while the default engine (Google) handles the pinned
defaults (`source auto`, `target auto`, which resolves to English from
`LANG=en_US.UTF-8`).

Nothing else is needed. The fork's copies of the three translator files at its
first commit (`7cfc5cb`) are byte-identical to the pin, and the translator
hunks of `4da3e83`, `966162c`, `c7aaeb5` and `6868389` apply to the pin in
that order with `git apply` and no fuzz. Every colour token and helper they
use (`colPrimaryContainer`, `colSecondaryContainer`, `colTertiaryContainer`,
`colTertiaryContainerHover`, `ColorUtils.transparentize`, `GroupButton`,
`RippleButton`) exists at the pin. Upstream has not changed these files since
the pin, so pin bumps should be quiet.

### Defects in the fork's version

Applying the fork's diff as-is carries two problems, which the port fixes:

- **Shadowed `buttonColor`.** `LanguageSelectorButton` declares
  `property color buttonColor`, but its base type `RippleButton` already has a
  `buttonColor` property: the computed colour that blends hover, toggled and
  disabled states and that the button background binds to. Redeclaring it
  shadows that computation, so depending on how QML resolves the lookup the
  pills lose their hover and disabled feedback. The port removes the new
  property and sets `colBackground` and `colBackgroundHover` at each call site.
  `LanguageSelectorButton` and `TextCanvas` are used only in `Translator.qml`
  (checked at the pin), so the two pills are the only call sites.
- **Long text overflows.** With the scroll area removed and the 150 px minimum
  gone, each box gets a fixed share of the height, and nothing clips or scrolls
  its content. A long paragraph pushes the text and the status row (character
  count, copy, search, paste, clear) past the bottom of the box. The port puts
  the text area of each box in a `StyledFlickable` above the status row and
  sets `clip: true` on the box, so text scrolls inside the box and the buttons
  stay reachable. The input keeps the caret in view while typing. The
  standard `TextArea.flickable` attachment would reparent the text area out of
  its `Loader`, so the port uses one flickable around both loaders and scrolls
  it to the caret on `cursorRectangleChanged` (an `ensureVisible()` helper).

Also, the fork uses `colPrimaryContainer` as the hover colour for both pills.
That makes the target pill's hover identical to its resting colour. The port
uses each pill's own `…ContainerHover` token.

## Goal

Make the translator tab visible and give it the fork's layout and colours,
without the defects above.

On "activate": no change in this repo can turn the tab on for tariognatha or
tarmantria. ii saves the whole options tree to `config.json`, so both already
hold an explicit `false`, and the repo does not write that file. On those
hosts activation is one click in ii's settings (or the `jq` command below),
done once by the user. The `Config.qml` default only covers hosts where ii has
never run, which today means taractias, which has not been deployed to its
hardware yet.

Success means:

- After the one-time toggle on existing hosts, the Translator tab appears in
  the left sidebar and survives switches and restarts. On a host whose
  `config.json` has no translator key, it is on with no toggle.
- The tab has the fork's layout: input box, centred language row with swap
  button, output box, with tinted surfaces that follow the wallpaper palette.
- Translation, swap, language selection, copy, search, paste and clear all
  work, and long text scrolls inside its box.
- All three hosts build and Quickshell starts with no new QML errors or
  warnings.

## Constraints

- Same as sub-project 1: changes live in the dots-hyprland source handed to
  the soymou module, never in `~/.config`; no public fork; no pushing.
- `config.json` stays ii-owned. This repo does not write to it at build or
  activation time.
- Only the pinned translator files and one `Config.qml` default change. No
  fork-only files, config keys or bar changes.

## Scope

### In

| Patch | Source | Port |
|---|---|---|
| Translator: null-safe character counter | `966162c` (translator hunks) | clean |
| Translator: restyle with swap button | `4da3e83` + `c7aaeb5` + `6868389` (translator hunks), squashed | hand-ported: `buttonColor` shadowing removed, pill hover tokens fixed, scrolling added, comments kept |
| Translator: enable by default | this repo | new: `sidebar.translator.enable` default `false` to `true` in `Config.qml` |

The restyle is one patch rather than three: the intermediate states (swap
button in the old layout, restyle without opacity) have no value on their own,
and the history stays short. The cost is coarser bisection. That
is acceptable because the three fork diffs were each checked to apply to the
pin separately, and the restyle touches only three files.

### Out

- `9f63cce` (hardcoded Bing engine), see above.
- Wiring the unused `language.translator.engine` config key into the `trans`
  command. Upstream declares the key but never passes `-e`. See open questions.
- Changing the default source or target language.
- The screen translator (`modules/ii/screenTranslator`), a separate feature.
- Writing `config.json` from Nix, and moving the existing `launchOnStartup`
  sed entry into the series.

## Design

### Patch series

The three patches go into their own directory, `patches/ii/02-translator/`, as
further commits on the shared `krane` branch in the clone, after the
sub-project 1 commits (tag `krane/01-fixes`). They are exported with
`git format-patch -o patches/ii/02-translator krane/01-fixes..krane/02-translator`.
The generic `lib/mk-host.nix` wiring from sub-project 1 picks the new
directory up with no change, since it applies every `patches/ii/*/` directory
in lexical order.

This sub-project starts after sub-project 1 has landed, because that is where
the `patches/ii/` layout and the wiring come from. The three patches touch only
translator files and `Config.qml`, and sub-project 1 touches neither, so they
also apply to the bare pin; only the stacking order is fixed. Build check 1
below confirms the changes are present in the output.

Commit message trailers follow sub-project 1. For the restyle:

```
Translator: restyle with swap button

Backport of pctrade/end4-pC 4da3e83, c7aaeb5, 6868389 (translator hunks)
https://github.com/pctrade/end4-pC/commit/c7aaeb5a58a7c4c965d9e692877ace415b4171bb
Problem: user wants the fork's translator layout
Port: hand-ported (squashed; dropped bar hunks and comment stripping; removed
  buttonColor shadow; per-pill hover tokens; added scrolling)
Drop when: never (feature, not a fix); revisit if upstream restyles Translator.qml
```

For the default flip, `Port: new` and `Drop when: upstream defaults
sidebar.translator.enable to true`.

### Files changed (paths relative to the ii root)

- `modules/ii/sidebarLeft/Translator.qml`: `swapLanguages()`; new layout
  (input, language row, output) with the fork's colours and 0.8
  transparentize; outer `StyledFlickable` removed; upstream comments kept.
- `modules/ii/sidebarLeft/translator/LanguageSelectorButton.qml`: full
  rounding and extra padding from the fork; no `buttonColor` property;
  `colBackground` stays `colLayer2` as the fallback.
- `modules/ii/sidebarLeft/translator/TextCanvas.qml`: `containerColor`
  property; `Layout.fillHeight`; `clip: true`; text loaders inside a
  `StyledFlickable` that takes the slot of the existing spacer above the
  status row; the `966162c` counter fix.
- `modules/common/Config.qml`: `sidebar.translator.enable: true`.

### Enabling on existing hosts

Three options were weighed:

1. **Change the QML default only.** Clean and in keeping with how
   `launchOnStartup` is handled, but it does nothing on a host whose
   `config.json` already says `false`, which is every host that has run ii.
2. **Rewrite `config.json` from an activation script** (for example with `jq`).
   This reaches existing hosts, but it breaks the rule that `config.json` is
   ii-owned. Run on every switch, it would undo the user turning the
   translator off in the GUI. Run once behind a marker file, it adds state and
   a script for a one-time toggle.
3. **Turn it on in the ii settings GUI** (Settings, Interface, "Enable
   translator"). One click per host. ii itself writes the change to
   `config.json`, which is the ownership model the constraint protects.

The design uses 1 for hosts where ii has never run (taractias) and 3 for
tariognatha and tarmantria. Option 1 is kept even though it reaches no host
in use today: it costs one small patch, it matches how `launchOnStartup` is
already handled, and it means a reinstalled or new host gets the translator
without anyone remembering the toggle. The patch uses the series rather than an
`iiPatches` sed entry because `property bool enable: false` occurs many times
in `Config.qml`: a sed would need a range address that silently stops matching
if the file changes, while a patch fails the build instead.

`docs/II-INTEGRATION.md` gets a line under the sub-project 1 "Backported fork
fixes" section saying the translator is on by default for fresh hosts and is
toggled in the GUI on existing ones, with the equivalent command for a
terminal:

```sh
f=~/.config/illogical-impulse/config.json
jq '.sidebar.translator.enable = true' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
```

### Engine and language defaults

Unchanged: engine unset (translate-shell's default, Google), source `auto`,
target `auto`. The language pickers already save the user's choice into
`config.json`.

## Error handling

- A patch that stops applying fails the `applyPatches` derivation, as in
  sub-project 1.
- `trans` failures (network down, engine refusing a language pair) show as an
  empty output box. That is upstream behaviour and is not changed here.
- Scrolling is required, not optional: the long-text acceptance check must
  pass before the restyle patch is exported. If the caret-following pattern
  misbehaves (caret not followed, wheel events captured by the wrong
  flickable, a mouse drag scrolling instead of selecting), fix it in the
  restyle commit. The status row stays outside the
  flickable in every variant, so its buttons can never be pushed out of view.

## Testing

### Build

1. `nix build` of the `patchedDotfiles` derivation, then confirm the three
   translator files and `Config.qml` in its output contain the changes (for
   example, grep for `swapLanguages` and `enable: true` under
   `sidebar.translator`). This catches missing wiring, which would otherwise
   build cleanly.
2. `nixos-rebuild dry-build --flake .#<host>` for tariognatha, tarmantria and
   taractias.

### Runtime

3. After switching, restart qs: no new QML errors or warnings in `qs log`
   compared with before, in particular nothing mentioning `buttonColor`,
   `Translator`, `TextCanvas` or `LanguageSelectorButton`.
4. Toggle "Enable translator" on in Settings, Interface. The Translator tab
   appears in the left sidebar after Intelligence (after Agents once
   sub-project 4 has landed) without restarting qs.

### Acceptance checks

| Check | Hosts |
|---|---|
| Layout is input, centred source/swap/target row, output. Boxes and pills are tinted from the wallpaper palette; change the wallpaper and the tints follow. | tariognatha (both monitors), tarmantria |
| Type "Bonjour le monde": after about 300 ms the output shows "Hello world". | tariognatha, tarmantria |
| Pick source `fr` and target `de`, translate, then press swap: the pills swap, the output re-translates, and after restarting qs both choices persist (`jq .language.translator ~/.config/illogical-impulse/config.json`). | tariognatha |
| Hover each pill and the swap button: each shows a visible hover change. | tariognatha |
| Paste a 1500-character paragraph: the input scrolls, the caret stays visible while typing at the end, the output scrolls, and the character count, paste, clear, copy and search buttons stay visible and work. | tariognatha, tarmantria |
| Empty input: the counter shows "0 characters" and no `TypeError` appears in the log. | tariognatha |
| Missing-key default: copy `config.json` to a backup, remove only the key with `jq 'del(.sidebar.translator.enable)'`, restart qs, and confirm the tab is present. The key is not expected back in the file yet: ii writes `config.json` only after an option changes (`onAdapterUpdated`), so it reappears as `true` after the next settings change. Restore the backup afterwards. The rest of the file is never moved or regenerated. | tarmantria |
| Readability: on one light and one dark wallpaper, the pill and box text are easy to read against the 20% tints. | tariognatha DP-2 |

taractias checks wait until it is verified on its hardware, as in sub-project 1.

## Commits

As in sub-project 1, one commit per patch file, plus one commit for the docs
line.

## Open questions for the user

1. **Enable on existing hosts through the GUI** rather than a one-shot
   activation script. Default: GUI toggle (or the documented `jq` command),
   no script. This means the switch alone does not make the tab appear on
   tariognatha or tarmantria.
2. **Wire the `engine` config key** so that setting
   `language.translator.engine` in `config.json` passes `-e <engine>` to
   `trans`. Default: not done; Google works today, and the fork's own switch
   to Bing breaks with the default `auto` target.
3. **Target language.** `auto` resolves to English from the system locale.
   Default: leave it; the picker saves any other choice.
4. **Fixes to the fork's design** (per-pill hover colours, scrolling). Default:
   included, since the fork's version loses hover feedback and hides the
   buttons on long text. Say if the fork's exact look matters more.
5. **Show the detected source language.** When the source is `auto`, the
   source pill could show what `trans -identify` detected (for example
   "auto (fr)"), so a wrong guess is visible. `trans -b -identify` works on
   2026-09-27. Default: not done; it is a new feature beyond the fork's
   design, and it would add a second `trans` call per translation.
