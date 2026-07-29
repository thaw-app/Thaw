# SPEC — fix-secondary-display-toggle-27

> The agent fills this by running the BOUNDED dimensional clarifier (see the
> Spec-first protocol: score Objective/Metric/Target/Scope, ask one question
> per round at the weakest, exit at ambiguity ≤20%), reads it back, and only
> runs `ftask spec fix-secondary-display-toggle-27 --approve` once sunke says OK. No code until
> approved. This is the non-coder's real review gate.
>
> The 'How will I know it works' section is the Karpathy gate — `--approve`
> parses it and refuses to flip status if Surface / Acceptance scenarios /
> Regression guards are empty or placeholder. Filling this section honestly
> is what lets the LLM LOOP toward done instead of guessing.

## Done — ONE measurable sentence (fill LAST, after the interview)
> The crisp goal the interview converges to. Must be checkable, not vague —
> it doubles as the future drive-to-green stop condition.
> e.g. 'subscribe-v3 import maps all 7 fields; imported row count = source ±0'.
- On macOS 27 with two displays, clicking Dot on the secondary display 10 consecutive times alternates the section state every time, keeps Dot on that display, and emits no `cgsGetScreenRectForWindow error 1000` from the interaction.

## What sunke wants (plain language)  [Objective]
- Fix Thaw's secondary-display Dot toggle so repeated open/close actions remain reliable on macOS 27.

## Out of scope (what we will NOT do)  [Scope]
- Do not redesign menu-bar layout, change control-item appearance, or alter single-display behavior.
- Do not expand the fix beyond the shared display/window-resolution path responsible for this failure.

## 拷问(写 Done 前) — 运行 /grilling 与 sunke 对齐到共识;共识即落 Done。(T0/T1 可跳过)

## How will I know it works (Karpathy gate — required to approve)

### Surface (which user-facing surface — pick one or more)
- [ ] web — Interceptor / agent-browser harness
- [x] cli — fresh shell + actual command
- [ ] api — curl against real endpoint
- [ ] lib — 5-line consumer script
- [ ] none — pure doc/config change (no simulate step)

### Visual target (web surface only — 钉死"长成什么样才算对")
> 仅 web surface 任务需填: 参考图路径 / 设计稿 URL / 一句可视判定(如"侧边栏宽 240px、企业名居中")。
> 这是前端视觉验收的对比基准 — 没有它,"看着对"无法机器核验。
- User clicks Dot 10 consecutive times on the secondary display → the hidden section alternates open/closed on every click and Dot remains on that display.
- User repeats the interaction while unified logging is captured → no `cgsGetScreenRectForWindow error 1000` is emitted by the interaction.

### Acceptance scenarios (each = observable user action + observable outcome)
Format: 'user does X → observe Y' (use → to separate action from outcome)
- User toggles a section on one display → existing reveal/rehide behavior remains unchanged.
- Test suite resolves menu-bar geometry and screens → existing geometry and screen-resolution checks continue to pass.

### Regression guards (what must NOT break — list things to recheck)
- full-suite

### Targeted tests (repo-relative paths; one per bullet, or `full-suite`)
> The direction model lists only tests affected by this task. Invalid/missing targets safely fall back to the full suite.
- 

## Plan (long tasks only — ordered route + live progress; T1/short may leave empty)
> Steps DERIVED from the Done line (not a chat-plan). Tick `[ ]`→`[x]` as you go.
> This is the compaction-survival anchor: after an auto-compact, read this to see
> exactly which steps are done and what's next — never re-run finished steps.
- [x] Verify the latest macOS 27 branch still reproduces the Preview 5 defect.
- [x] Trace the control-item click through the shared screen/window-resolution path.
- [x] Add the smallest root-cause fix and one focused regression test.
- [ ] Run the focused and full automated test suites.
- [ ] Install the patched build and perform the 10-click secondary-display acceptance check with logs.
- [ ] Run independent review and submit a Draft PR linked to tracking issue #687.

## Dead ends (filled DURING work — approaches tried & rejected, don't retry)
> Append one line per rejected approach: `approach → why it failed`. Read
> this before each new attempt so the same wrong path isn't tried twice.
- Starting from `development` → wrong baseline because Preview 5/6 is built from `feat/macos-27-experimental`; restarted from the preview branch before editing code.
- Opening a standalone issue → maintainers closed #846 as a duplicate and directed macOS 27 reports to tracking issue #687; the PR will follow that repository policy.
