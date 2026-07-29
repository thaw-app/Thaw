<!-- ftask:managed v1 — auto-generated; edit OUTSIDE this block -->
# Agent rules — thaw-pr-846 (managed by ftask)

- This repo is part of sunke's agent-OS. Agents NEVER run git directly here — use `bun ~/.claude/PAI/TOOLS/ftask.ts`.
- Base branch: `development`. Feature work happens on a `ftask new <slug>` feat branch (single-dir mode), never on `development` directly.
- Test gate: `ftask ship` runs valid SPEC-targeted paths first, then none detected — add a test suite; `ftask ship` will WARN until then once as the final local-ff gate (PR: required CI owns full); invalid/missing targets fall back to full and failures BLOCK merge.
- Ship semantics: `ftask ship` merges into `development` then STOPS — sunke verifies in his local environment on `development` (worktree mode: the main checkout already shows the merge, zero switching); only after his OK run `ftask postship <slug> --finalize` (push + remove worktree + delete branch). NOT OK → `ftask revert <slug>`.
- Code questions (where is X / who calls X / what breaks if I change X): this repo has a `.codegraph/` index — use the `codegraph_*` MCP tools (explore/callers/callees/impact) FIRST instead of grep/Read sweeps; cross-repo queries take a `projectPath` arg. Human-readable architecture map: vault `AgentOS/<repo>/GRAPH.md`.
- When you fix a bug found while troubleshooting (a 排障), add a regression test that FAILS without the fix BEFORE `ftask ship`, and record the root cause as one line under "Known gotchas" below.
- Global protocol: `~/.claude/CLAUDE.md` (Claude), `~/.codex/AGENTS.md` (Codex), and `~/.grok/AGENTS.md` (Grok) — "AGENT-OS" section. User cheatsheet: `~/code/AGENT-OS.md`.

## Known gotchas
- (root causes from 排障 sessions accrue here so the same bug is never debugged twice)
<!-- /ftask:managed -->
