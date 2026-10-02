# ii settings: steps and decisions for you

Everything below either needs sudo, a live desktop session, a judgment call
only you can make, or touches your own private host config. Background on
why each item exists is in
[2026-10-02-ii-settings-premerge.md](2026-10-02-ii-settings-premerge.md) and
the three fix specs it links.

## Decisions

1. **Merge choice.** You can merge now and treat Specs 1-3 as accepted
   follow-up work, or hold the merge until they're implemented and
   re-reviewed. The open issues are confined to the new settings window
   (see [2026-10-02-ii-settings-changes.md](2026-10-02-ii-settings-changes.md)),
   so merging first is reasonable if you'd rather iterate on `main`; holding
   is reasonable if you'd rather not carry a known boot-time-persistence gap
   even briefly. Either way, decide before the next step.
2. **Approve Specs 1-3.** Read
   [2026-10-02-ii-settings-boot-path-design.md](../specs/2026-10-02-ii-settings-boot-path-design.md),
   [2026-10-02-ii-settings-gui-write-paths-design.md](../specs/2026-10-02-ii-settings-gui-write-paths-design.md),
   and
   [2026-10-02-ii-settings-input-hardening-design.md](../specs/2026-10-02-ii-settings-input-hardening-design.md),
   and say which (if any) to implement as written, which need changes, and
   which to skip.
3. **The local-only commits at the bottom of this branch.** This branch
   carries two commits that add the machine the work was done on, which
   must never leave this checkout. Confirm you still want them kept at the
   bottom and excluded from anything handed back — this is the current
   state, not a change being proposed.
4. **Privacy review and your own config commits** (per host, see below) —
   you're the only one who can judge what's sensitive in your own config.
5. **taractias stays deferred** until its hardware is verified, same as
   earlier in this branch — nothing to decide here unless you want to
   change that.

## Runbook

Ordered to touch sudo/switch/reboot the fewest times. Steps 1-2 need no
switch; Step 3 is one switch; Step 4 is the privacy review that follows it;
Step 5 is the hand-back check, done last, right before anything leaves this
checkout.

1. **Verification gates (no switch needed on their own, but run them before
   switching for real):**
   ```
   cd ~/.dotfiles && nixos-rebuild dry-build --flake .#tariognatha
   just check-new-host
   ```
   Run both on real hardware with enough memory (the test VM's dry-build
   reliably runs out of memory on the full system build; the narrower
   home-manager activation build was used instead during development and
   passed, but the full dry-build itself still needs to run clean here).

2. **GUI acceptance checks**, on a host already running this branch's
   config, no reboot required — the full checklist is
   [2026-10-02-ii-settings-manual-test.md](2026-10-02-ii-settings-manual-test.md);
   the short version: open the settings window, click through each page,
   confirm a setting change shows up in `hyprctl getoption` and in
   `hosts/<host>/ii-settings.json`, confirm opening the page twice without
   changing anything writes nothing, confirm each animation preset leaves
   `hyprctl configerrors` empty.

3. **Switch** tarmantria and tariognatha:
   ```
   sudo nixos-rebuild switch --flake .#<host>
   ```
   Then check the Hyprland config errors are empty and the writer still
   answers:
   ```
   command cat ~/.config/hypr/custom/krane_gui.lua; hyprctl configerrors
   krane-ii-settings set hyprland input:kb_layout us; echo "exit $?"
   ```
   taractias is not included here — see the decision above.

4. **Privacy review of each switched host's config**, before committing it:
   ```
   less ~/.dotfiles/hosts/<host>/illogical-impulse/config.json
   ```
   Pay particular attention to anything that identifies you or your
   location — weather city, GPS toggle, any booru/account usernames, AI
   endpoint keys, wallpaper/recording/snip save paths, and the profile
   section. Once you're satisfied nothing in there needs trimming or
   `.gitignore`-ing:
   ```
   git add hosts/<host>/illogical-impulse && git commit -m "Track <host>'s ii config"
   ```

5. **Before anything is pushed, format-patched, or handed back**: run the
   leak check this repo's `CLAUDE.md` describes (the grep for this
   machine's hostname prefix across the diff and the log range) and confirm
   it prints nothing. This applies to every export, not just the final one
   — re-run it any time new commits are added above the two local-only
   commits at the bottom of the branch.

## After this

Once you've made the decisions above, work on the approved specs can start
(or, if you chose to merge first, continue as follow-up branches off
`main`). The manual test checklist should be re-run against whichever specs
land, per the "needs" column in
[2026-10-02-ii-settings-manual-test.md](2026-10-02-ii-settings-manual-test.md).
