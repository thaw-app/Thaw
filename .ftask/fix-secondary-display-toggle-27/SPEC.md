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
- 

## What sunke wants (plain language)  [Objective]
- 

## Out of scope (what we will NOT do)  [Scope]
- 

## 拷问(写 Done 前) — 运行 /grilling 与 sunke 对齐到共识;共识即落 Done。(T0/T1 可跳过)

## How will I know it works (Karpathy gate — required to approve)

### Surface (which user-facing surface — pick one or more)
- [ ] web — Interceptor / agent-browser harness
- [ ] cli — fresh shell + actual command
- [ ] api — curl against real endpoint
- [ ] lib — 5-line consumer script
- [ ] none — pure doc/config change (no simulate step)

### Visual target (web surface only — 钉死"长成什么样才算对")
> 仅 web surface 任务需填: 参考图路径 / 设计稿 URL / 一句可视判定(如"侧边栏宽 240px、企业名居中")。
> 这是前端视觉验收的对比基准 — 没有它,"看着对"无法机器核验。
- 

### Acceptance scenarios (each = observable user action + observable outcome)
Format: 'user does X → observe Y' (use → to separate action from outcome)
- 

### Regression guards (what must NOT break — list things to recheck)
- 

### Targeted tests (repo-relative paths; one per bullet, or `full-suite`)
> The direction model lists only tests affected by this task. Invalid/missing targets safely fall back to the full suite.
- 

## Plan (long tasks only — ordered route + live progress; T1/short may leave empty)
> Steps DERIVED from the Done line (not a chat-plan). Tick `[ ]`→`[x]` as you go.
> This is the compaction-survival anchor: after an auto-compact, read this to see
> exactly which steps are done and what's next — never re-run finished steps.
- [ ] 

## Dead ends (filled DURING work — approaches tried & rejected, don't retry)
> Append one line per rejected approach: `approach → why it failed`. Read
> this before each new attempt so the same wrong path isn't tried twice.
- 
