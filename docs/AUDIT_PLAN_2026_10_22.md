# Power Games audit plan — 22 October 2026

Status: started on 22 October 2026 by the maintainer's explicit instruction.
Work autonomously without clarification questions; leave material changes to
rules, behavior, architecture or external APIs as decisions in the report.
Improvements and cleanup that change maintained sources also restart the
full-pass completion condition. Progress and evidence belong in ignored
`tmp/audit-20261022/`, separate from this scope document. Preserve the earlier
plan and its recorded stopping decision rather than rewriting that history.

This is a new review of the current main Power Games sources, based on
[section 7 of the 18 October plan](FIXES_PLAN_2026_10_18.md#7-whole-project-audit-correctness-performance-and-maintainability).
It does not restart the earlier feature implementation or all of its test
campaigns. Deathmatch and other separate experiments remain outside the scope.

## 1. Source review and baseline

- At execution start, record the revision, working changes, host source and
  available test environment. Preserve unrelated work.
- Inventory maintained application code, all games and bots, shared UI and
  presentation, transport, randomness and private state, persistence,
  tournaments, statistics, settings, notifications, content loaders, tooling,
  tests, fixtures, packaging and CI.
- Read the maintained sources in full and trace their dependencies. A search
  hit or passing test does not mean that a file has been reviewed. Track file
  hashes, reviewed sections, findings and remaining coverage in ignored `tmp/`.
- Review generated code through its maintained inputs and generators. Do not
  describe binary assets as line-by-line reviewed source, or rewrite question
  sets, rules, translations and recordings without a relevant finding.
- Start with high-risk shared mechanisms, then cover the remaining inventory.
  A later change invalidates its affected earlier review and evidence. The
  additional final defect-free whole-project pass is defined in section 7;
  targeted revalidation alone does not satisfy that completion condition.

## 2. Three review tracks

1. Correctness: validation, authority, privacy, rules and scoring, defaults,
   bounds, optional state, encoding, concurrency, stale callbacks, replay,
   uncertain writes, saves, host changes and resource lifetime. Include usable
   controls, focus, concise feedback, speech/audio and background operation.
2. Performance: repeated requests, reads, parsing, projections and replay;
   unnecessary copying, allocations, large payloads, growing queues/caches,
   retained resources, lock contention and blocking work on the UI thread.
3. Maintainability: proven dead code, duplicated logic, obsolete workarounds,
   unnecessary wrappers, unclear ownership and helpers that hide real product
   behavior. Prefer the existing framework over parallel per-game mechanisms.

Dawid Pieper's cleanup (`f2f6ae6`, integrated through PR 28 in `2a3b36d`)
remains an example of useful simplification, not a diff to apply again.
Check dynamic registration, callbacks, reflection, packaging and supported
historical formats before removing apparently unused code.

## 3. Finding, repair and regression tests

- Record the location, expected and observed behavior, reproduction, cause,
  risk and affected consumers. Separate demonstrated defects from hypotheses.
- Fix confirmed in-scope defects in coherent batches. Material changes to
  rules, behavior, architecture or external APIs remain unimplemented proposals
  for the maintainer, not silently accepted audit improvements.
- Find dependent existing tests and fixtures before making the change. Update
  and run them in the same batch, including assumptions about defaults, time,
  controls, result policies and historical inputs. A newly added regression
  alone is not sufficient.
- Where practical, show that the regression fails against the faulty behavior
  in an isolated local process. Diagnose a failing assertion before changing
  its expectation; preserve original historical corpora and their guarantees.
- Check normal behavior, boundaries and recovery for the affected contract.
  Recheck the integrated change and its callers, not just its edited lines.
  Repeat affected tests after fixes, not every unrelated suite after each edit.
- Reuse valid evidence for unchanged code. Keep initial failures, corrected
  fixture mistakes, final results and any missing coverage distinguishable.

## 4. Live trials cover changed places and actual dependencies

This is the controlling test-scope rule. A whole-project source review does
**not** require replaying every game or repeating a universal live-test matrix.

- For each production change, identify the user path it changes and the
  contracts that can genuinely be affected. Derive the live scenarios from
  that impact analysis and state why each scenario is needed.
- Reproduce the changed runtime behavior on real accounts through normal game
  flows and native controls, as close to ordinary use as practical. Do not
  replace a necessary live trial with a fabricated state or a helper that
  manufactures the expected acknowledgement.
- Ordinary games, tournaments, bots, saves, private hands, reconnects and host
  changes are **possible dependencies, not a mandatory checklist for every
  fix**. Include only the modes and transitions that the change can affect.
  For example, correcting a local button label does not by itself require a
  private-deck confidentiality campaign or a saved-game migration trial.
- A shared framework change can require representative consumers from more
  than one game family. Trace the actual dependencies and differences before
  choosing those consumers. Do not test only the reporting game, but do not
  automatically test every game either.
- A complete affected match is required when a change concerns completion,
  results or behavior that emerges over a match. A short, decisive interaction
  is sufficient for a genuinely local path; do not extend it into an unrelated
  campaign. Runtime cleanup/refactoring still needs relevant behavior checks.
- Test-only, documentation, generator and CI changes use their actual local
  execution paths. Do not invent live-game trials for code that never runs in
  a client. Package-specific changes require a relevant binary/package check
  when a package is built, not an unrelated set of live matches.
- After a correction, repeat the failed scenario and any affected checks.
  Unchanged, already verified paths do not become unverified merely because
  another finding was repaired.
- Clearly distinguish local models, native-contract fixtures, real-account
  API use, native control callbacks and actual speech/audio observations.
  Do not claim listening or physical keyboard coverage that was not performed.

## 5. Optimization and controlled verification

- Compare the old and proposed implementations with the same copied inputs,
  recorded events, options, participants, clocks and random receipts. Check
  legal actions, state, scores, ownership, event order and subsequent RNG state.
  Compare cold/full replay with warm/incremental replay where relevant.
- Verify useful invariants after transitions, not only at match end. Include
  exact-once actions, authorized actors, physical-card identities, private
  ownership, deterministic replay and bounded resource lifetime as applicable.
- Use bounded reproducible sequences and controlled event order for suspected
  races. Keep failing seeds/schedules; run high-volume experiments locally,
  not by flooding the public server.
- Measure relevant request counts, repeated calculations, resource growth and
  cold/warm behavior before and after optimization. Prefer repeatable counts
  and growth budgets to brittle universal millisecond thresholds.
- Retain a replacement algorithm or removed layer only for a demonstrated
  correction, repeatable performance gain or concrete maintainability benefit.
  Fewer lines alone are not evidence. Preserve privacy, validation, freshness,
  ordering, acknowledgements and diagnostics.
- Never run the old and new implementation as two real writers for comparison,
  inject intentionally faulty code into live clients or leave test probes and
  unsuccessful experiments in production.

## 6. Staffing and coordination

The agreed setup is one primary auditor and **one additional independent
reviewer**, two agents in total. The reviewer checks both code and verification;
there is no separate third agent for tests. This supersedes the earlier
single-agent proposal. The maintainer has now started this audit and approved
this division. Do not add further supporting agents without a new instruction.

### 6.1. Primary auditor

- Own the complete maintained-source inventory and review all three tracks
  in section 2, including dependencies between games and shared mechanisms.
- Reproduce findings, identify their causes and make coherent fixes. Be the
  sole writer of maintained code, tests, fixtures, generators and documentation;
  update affected tests with each behavior change, not after a CI failure.
- Select targeted local tests and changed-path live trials through the impact
  analysis in section 4. Run the trials, capture evidence and repeat failed or
  affected checks after corrections. Do not substitute state inspection for
  testing the actual changed user path.
- Verify the reviewer's findings against the sources and evidence, integrate
  justified corrections, resolve disagreements and maintain the consolidated
  findings, coverage and completion record. Retain responsibility for the
  integrated result rather than treating delegation as acceptance.

### 6.2. Independent code and test reviewer

- Perform bounded, read-only reviews of high-risk shared contracts and every
  change batch, including affected callers, tests and fixtures. The primary
  auditor still owns whole-project coverage; do not mislabel this focused
  second review as another independent full audit.
- Establish expected behavior independently from the maintainer's requirements,
  project contracts and real execution paths before assessing the proposed
  fix. Do not use the primary auditor's explanation or a passing test as proof
  that the implementation is correct.
- Check correctness, authority and private state, concurrency and stale work,
  replay, recovery and resource lifetime where relevant. Check whether an
  optimization preserves behavior and has measurements, and whether cleanup
  preserves dynamic callers and supported historical inputs.
- Review the verification itself: does a regression reach the faulty path,
  would it detect the original failure, are dependent existing tests updated,
  and do fixtures preserve historical inputs? Check that necessary live trials
  exercise native user paths rather than manufacturing their expected result.
  Flag missing coverage without demanding unrelated campaigns.
- Return concise findings with severity, file/symbol/line, the broken contract,
  evidence or reproducible steps, affected consumers and missing checks.
  Separate confirmed defects, hypotheses and non-actionable preferences.
  Report reviewed source hashes and evidence references, including gaps;
  silence or an unfinished task is not approval.
- Do not edit maintained files, change expectations to obtain a pass, operate
  live accounts independently or mutate server data. If reproduction is needed,
  use an agreed isolated local check and an assigned ignored `tmp/` directory,
  or ask the primary auditor to run the required live scenario.

### 6.3. Handoffs and acceptance

- Give the reviewer an explicit bounded brief: source revision/hashes, scope,
  relevant requirements and contracts, entry points, risks, verification to
  inspect, prohibited mutations and the required output. Provide enough context
  to reason independently, without prescribing the expected verdict.
- Hand off stable batches. The reviewer can examine unchanged areas while the
  primary works elsewhere, but must not approve a moving source snapshot.
  Recheck affected review conclusions after later edits.
- For every actionable review item, record either a verified correction or
  an evidence-backed rejection. Material changes requiring a maintainer
  decision remain explicit unresolved/deferred items, not silent redesigns.
  Resolve disagreements using contracts, reproductions and measurements, not
  agreement counts. Agreement between agents is not a correctness guarantee.
- Request re-review of corrected findings and their affected tests. Wait for
  every required review result and close verification gaps before declaring
  the batch or audit complete. Keep self-review and independent evidence
  distinguishable, and do not count the same test twice.
- Use one live-test schedule controlled by the primary auditor, with explicit
  ownership of accounts, clients, tables and temporary resources. Preserve the
  user's active work; cleanup targets only trial-owned resources. Neither role
  is authorized to change server protection, schema, quota, host code or
  unrelated data by this planning step.

This division applies the official [Codex subagent guidance](https://learn.chatgpt.com/docs/agent-configuration/subagents):
give agents focused roles and clear handoffs, prefer read-heavy supporting
work, return concise evidence and avoid conflicting parallel edits. The choice
of exactly one reviewer is this project's agreed budget/quality decision, not
a claim that the documentation mandates two agents. Read-only task instructions
are not a separate sandbox or additional permission boundary.

## 7. Completion and delivery

- Account for the maintained-source review and every finding: fixed and
  verified, disproved with evidence, or explicitly deferred with its reason.
  Do not call unread code reviewed or a partial pass complete.
- After the repair batches and their affected checks, complete **one full
  whole-project audit pass without discovering a new defect** before ending
  the audit. Cover the entire maintained-source inventory and all three review
  tracks, not only the diff, earlier findings or files chosen by searches.
  One clean full pass is required, not two consecutive clean passes.
- Record each pass's source manifest/hashes, complete coverage, findings and
  reviewer results. A pass that finds a confirmed in-scope defect does not
  become clean because that defect is fixed before the pass ends. Collect the
  remaining findings where practical, repair and verify them, then conduct a
  new full pass on the integrated sources. Apply the same rule to a demonstrated
  optimization or cleanup finding that requires further maintained-source edits;
  do not manufacture stylistic work to keep the audit running.
- The final pass must close on the reviewed source snapshot with no unresolved
  in-scope defects, outstanding required reviews or unverified suspicions that
  could change that conclusion. A failed, interrupted or incomplete pass is
  not clean. A known defect left for a maintainer decision must be reported as
  a limitation/blocker, not relabeled as a defect-free result.
- Revisit changed code and genuine dependencies after corrections, but retain
  valid evidence for unchanged paths. Full source passes do not require
  repeating every local suite or live-game campaign: section 4 still controls
  testing of changed runtime places and their actual dependencies.
- Verify current affected tests and applicable generators/catalogs. Inspect
  existing CI failures when relevant rather than assuming all failures are
  stale expectations. Any unobserved remote CI result remains unconfirmed.
- Summarize actual fixes, measured improvements, cleanup, affected live paths
  tested, limitations and major decisions left for the maintainer. Neither an
  audit nor passing tests guarantees the absence of every possible defect.
- Keep detailed evidence in ignored `tmp/`. Update relevant technical contracts
  and player documentation in all supported languages when behavior changes.
- This planning step does not authorize a version bump, package build,
  installation or GitHub publication. Follow the maintainer's subsequent
  delivery instruction; requested packages remain signed by default.
