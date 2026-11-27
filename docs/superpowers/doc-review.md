# Stage 3 doc review list

Statements the docs make that the repo cannot confirm, plus open follow-ups. Each item has a suggested decision; mark the ones you want changed.

## Patch messages
1. [ ] `patches/ii/01-fixes/0006` message cites `modules/home/illogical-impulse.nix` (now `modules/home/desktop/illogical-impulse.nix`). Suggested: re-export the patch with the path fixed.

## External or runtime facts kept in the docs (suggested: keep all)
2. [ ] README: update PRs need "Allow GitHub Actions to create and approve pull requests" in the repo settings.
3. [ ] II-INTEGRATION: background Claude sessions are matched by title because a supervisor spawned them (pid ancestry leads elsewhere).
4. [ ] II-INTEGRATION: "(checked 2026-09-30) a permission prompt in another workspace's kitty window produces an ii popup". Suggested: drop the date.
5. [ ] II-INTEGRATION 07-idle: Hyprland ignores the inhibitor until its layer surface is mapped / zero alpha under fullscreen.
6. [ ] II-INTEGRATION: `/run/greetd.run` blocks a second autologin in the same boot.
7. [ ] II-INTEGRATION: "Opus 5.5 works the same with `claude-opus-5-5`" and Anthropic's OpenAI-compatible endpoint is "for testing and comparison".
8. [ ] II-INTEGRATION 0011: "Neovim looks frozen" symptom. Suggested: keep.
9. [ ] INSTALL: QCA9377 Wi-Fi stalls under default IOMMU (why taractias has `iommu=pt`).
10. [ ] INSTALL: GPU model names (RTX 4070 Ti class, AMD Vega iGPU).
11. [ ] INSTALL: NVIDIA black-screen ladder steps (untested guidance).
12. [ ] INSTALL: systemd-boot auto-discovers Windows on the same ESP.
13. [ ] INSTALL: pinning public DNS cures "Resolving timed out".
14. [ ] INSTALL + secrets: an uncommitted secrets file evaluates as absent.
15. [ ] VERIFY: hardware rows (G502 libinput name, rtw88, Vega VA-API).
16. [ ] secrets: the GitHub PAT is fine-grained, limited to the repo, Issues read/write.
17. [ ] secrets: server SSH host keys are generated ahead and kept in the password manager.

## Follow-ups outside docs
18. [ ] `scripts/bootstrap-sops.sh` skeleton lists only `wg0-private-key`; desktops need all six `wireguard/*` keys. Suggested: fix in a separate change.
19. [ ] README dropped "a non-booting kernel needs physical access to pick the previous generation" (not in code). Suggested: leave out.
20. [ ] Dropped Go note ("go is global because NixVim's gopls needs it on PATH"). Suggested: re-add as a comment in `modules/home/desktop/dev.nix` if true, else leave out.

## ii-settings handoffs (deleted; steps the repo cannot show as done)
21. [ ] Live-session checks from the manual test list (Hyprland, Idle, animation presets, Displays keep-or-revert, reboot/hotplug cycle, presets) and runbook steps 1, 3, 5. The branch merged long ago and later work built on it. Suggested: accept as done; no action.
22. [ ] Decisions 1, 3, 5 (merge timing, local-only commits, taractias deferred). Suggested: moot after merge, except taractias: still no tracked `illogical-impulse/config.json`. Accept.
