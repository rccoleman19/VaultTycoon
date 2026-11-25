# Decisions

## 2026-11-25 — Batch merge of stack #114–#148 into main
- Decision: Ryan approved via Chief's question card 6:06 AM CT merging the stacked
  PRs #114–#148 as one batch, via #148 (feat/dead-time-opening @ c32a72a9)
  retargeted to main and merged with a merge commit. No squash, no rebase.
- Merge commit: 3605a01fa58d9d62ede4d882c9b8806d8bd770f8 (tree eb3e064a; parents
  2e382fe2 old main, c32a72a9 stack tip). #114 auto-marked merged; #115–#147
  closed as landed via #148. Stack branches kept.
- Why: 35 accepted PRs had sat unmerged since Oct 26; Ryan's "ship or pause" call.
- Verified at tip c32a72a9 and again on merged main 3605a01f (2026-11-25):
  check.sh EXIT 0, FAIL 0; fresh-wing md5 674fbb398939; five standard wins at
  280 s, nobody dead; trial merge with main clean (tree eb3e064a, docs/dot only
  differs from the tip).
- Known limits carried onto main: 05 s4242 post-Stock gap 30.0 s (zero headroom);
  flicker 15/12 at cap; zz_flicker03 probe crash in _refresh_alert_details;
  salvage_nudge_kind raw-salvage budgeting; VT-1 save-layout-marker still open.
- Not decided here: VT-1 behaviour (reject vs accept legacy pre-hex saves).
