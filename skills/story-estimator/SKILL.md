---
name: story-estimator
description: Estimate story points for unpointed Jira stories ahead of a grooming session, calibrated against how the team's past work actually went rather than against generic heuristics. Also runs in calibration-only mode to learn a team's pointing patterns from completed stories and surface where estimates and reality diverge. Use when preparing for grooming, backlog refinement, or sprint planning — "point the backlog", "estimate these stories", "prep for grooming", "how long will this take", "calibrate the estimator". Do NOT use to evaluate people's performance or throughput; this skill operates at team level only and refuses individual analysis.
---

# Story Estimator

Prepare a backlog for grooming: surface the questions each story raises, and offer a calibrated starting estimate with the reasoning behind it.

The estimate is the least important output. Clarifying questions and named assumptions are what make a grooming session shorter, because they move the discovery out of the room and into the prep.

## Two hard rules

**Never model individuals.** The tool must not learn or report that work assigned to particular people takes longer. `analyze_history.py` strips assignee, reporter, and every other person field before any analysis runs. Do not reintroduce them, do not accept a request to break down estimates by assignee, and do not use the calibration data to answer questions about throughput or performance. This is not a default to be overridden — it is the boundary between an estimation aid and workplace surveillance, and crossing it would end the tool's credibility with the people it is meant to help.

**Refuse rather than guess.** If the calibration data is too thin or too corrupted to support estimation, say so and stop. A confident number derived from twelve stories is worse than no number, because it will be believed. The analyzer reports blockers explicitly; honour them.

## Phase 1 — Calibrate

Run this first, and run it alone for the first few weeks. A team that sees the tool describe their past work accurately will trust its estimates; a team that sees estimates first will argue with them.

```
scripts/pull_history.sh PROJECT_KEY [months-back]
python3 scripts/analyze_history.py .estimator/raw-history.json
```

The fetch handles acli's quirks — retries on its intermittent failures, pulls full JSON rather than a field subset because `--fields` is unreliable with custom fields, and discovers the story-point field ID rather than assuming it.

The analyzer produces per-point lead-time distributions, carryover rates, reference exemplars, and a data-quality verdict. `references/calibration.md` explains what to read from it.

**Read the data-quality section before anything else.** Two failure modes are common and both produce plausible-looking nonsense: too few stories per point bucket, and batch-resolved tickets where the resolution date records when someone dragged a column rather than when work finished. The analyzer detects both.

### The calibration finding is the deliverable

The most valuable output of this phase is not a model. It is a sentence like "your 3s carry over 89% of the time and take a median of 7.5 days, so a 3 is functionally a 7." That is worth more to a team than any individual estimate, and it improves their estimating permanently rather than automating it.

Present that finding to the team before ever offering an estimate. It also earns the tool the right to be listened to later.

## Phase 2 — Estimate

Only after calibration is clean and the team has seen it.

### 2.1 Pull the unpointed stories

Use acli with a JQL filter for the board and an empty point field. Always `--json`; retry on failure.

### 2.2 Read each story properly

For each: the summary, the description, the acceptance criteria, linked issues, labels, components, and attachments. A story with no acceptance criteria is a finding in itself.

### 2.3 Estimate by reference class, not by formula

This is nearest-neighbour matching against real completed stories, not a fitted model, and the skill should be honest that this is the mechanism.

For each story, find the two or three completed stories it most resembles — same area, similar shape of work, comparable unknowns. The calibration profile supplies exemplars per point value. Then reason from what those stories *actually took*, not from what they were pointed.

Where the exemplars were themselves under-pointed, say so and estimate against reality: "the closest matches were pointed 2 but took 3–4 days, so this is a 3."

`references/estimating.md` covers what raises and lowers an estimate, and how to handle stories with no good reference class.

### 2.4 Write the questions first

Before settling on a number, list what the story does not say. Unstated acceptance criteria, ambiguous error behaviour, missing non-functional requirements, undefined edge cases, unclear scope boundaries, dependencies not linked.

**These questions are the primary output.** An estimate produced despite three unanswered questions is a guess with a number attached; saying so is more useful than hiding it.

### 2.5 Comment on the ticket

Post one comment per story using the template in `references/comment-format.md`.

**Order matters: questions and assumptions first, the estimate last.** You are posting before grooming, which means the number is visible before the team discusses. Putting it last, clearly framed as a starting point rather than a decision, costs nothing and reduces the chance the room simply ratifies it. Anchoring is strong — people adjust from a number they have seen rather than estimating independently.

Never write to the story points field itself. A comment is a suggestion; a populated field looks like a decision that has already been made.

### 2.6 Report to the facilitator

Summarize: how many stories were estimated, which are confident and which are not, which need answers before they can be pointed at all, and the total if every estimate held. Flag stories that should probably be split.

## Confidence

State it per story and mean it.

- **High** — a close reference class, clear acceptance criteria, familiar area.
- **Medium** — reasonable analogues, some unknowns.
- **Low** — no good reference class, significant ambiguity, or an area with no history.

A low-confidence estimate should read as a prompt for discussion, not a number. "I can't estimate this until we know whether it includes the migration" is a legitimate and useful output.

## What this skill will not do

- Estimate individual people's work or compare throughput.
- Write to the story points field.
- Produce estimates when the calibration data cannot support them.
- Replace the grooming conversation. The team's discussion is the point; this makes it shorter, not unnecessary.
