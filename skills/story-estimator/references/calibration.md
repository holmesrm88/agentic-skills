# Reading the Calibration

What the analyzer output means and what to do with it.

## The point of calibrating against reality

If the tool learns from the points a team assigned, it learns their bias — including whatever systematic under-pointing produces carryover. Learning from what stories *actually took* gives you something better: the gap between the two becomes its own finding.

That gap is usually the most valuable thing calibration produces. "Your 3s take a median of 7.5 days and carry over 89% of the time" tells a team something actionable about how they estimate. No individual estimate matches that value.

## The two measures, and their limits

**Carryover** — a story belonging to more than one sprint was carried. Binary, reliable, and unaffected by how tidily people move tickets. It is the strongest signal available that a story was larger than its points claimed.

**Lead time** — created to resolved. Continuous and more informative, but it measures wall-clock elapsed time, not effort. A story created in March and picked up in June shows a 90-day lead time and tells you nothing. Treat it as a distribution, never as a per-story truth, and prefer the median over the mean.

True cycle time — first transition to In Progress through Done — would be better than either. It requires the Jira changelog, which the CLI may not expose. If you can obtain it, use it; the analyzer's structure accommodates it. Do not fabricate it from what is available.

## Data quality

Two failure modes produce confident nonsense. Both are detected, and both should stop you.

**Thin buckets.** Fewer than about eight stories at a point value means the median is one or two stories' worth of noise. Fewer than thirty pointed stories overall means calibration is not supportable at all. The analyzer treats the second as a blocker and marks the first `THIN`.

A thin bucket never produces a confident verdict, even when it looks dramatic. Six stories at 50% carryover is three stories. That is not evidence of under-pointing.

**Batch resolution.** If many stories share a resolution timestamp, someone dragged a column at the end of a sprint. The resolution date records bookkeeping, not completion. When the analyzer reports a high share of same-minute batches, lead-time numbers are unusable — fall back to carryover, which survives it, and say clearly which measure you are relying on.

## Reading the per-point table

```
  pts    n  lead: p25     med     p75  carried  verdict
  1.0   40        1.2     1.5     1.7       5%  ok
  3.0   18        5.7     7.5     9.5      89%  UNDER-POINTED
```

**n** — sample size. Everything else is only as good as this.

**p25 / median / p75** — the spread matters as much as the middle. A tight spread means the team estimates that size consistently. A wide one means the point value covers genuinely different kinds of work, which is usually a sign the bucket should be split.

**carried** — share that spanned multiple sprints. Above roughly 40% means the point value is systematically too low.

**verdict** — `THIN` takes precedence over everything. An under-pointing conclusion from a small sample is exactly the overconfidence this tool should avoid.

## Reference stories

The exemplars per point value are the working artifact. The estimation method is nearest-neighbour matching against real completed work — reference-class forecasting — not a fitted model, and being honest about that is what makes the output correctable.

A good estimate names its references: "this resembles PROJ-1180 and PROJ-1244, both pointed 2, both actually took 3–4 days." A reader can then disagree with the *comparison*, which is a productive argument. Nobody can argue productively with a number.

Refresh the exemplars every few months. Teams change, codebases change, and a reference class from a year ago may no longer describe the same work.

## Re-calibrating

Re-run when: the team composition changes substantially, the codebase changes shape (a major migration, a new service), the team consciously changes how they point, or roughly quarterly.

Keep the previous profile. Movement between profiles is itself a finding — if carryover on 3s drops from 89% to 30%, the team's estimation improved, and that is worth telling them.

## The boundary

Every person field is stripped before analysis. The tool measures *work*, not *people*.

This will be tested. Someone will ask for estimates broken down by assignee, or whether certain stories take longer for certain people. The answer is no, and the reason is worth stating plainly: a tool that answers that question stops being an estimation aid and becomes a performance monitor, and the team will — correctly — stop trusting anything it produces.
