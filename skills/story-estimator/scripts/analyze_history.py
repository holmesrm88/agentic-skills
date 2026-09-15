#!/usr/bin/env python3
"""
analyze_history.py — build a calibration profile from completed Jira stories.

Usage: python3 analyze_history.py .estimator/raw-history.json

Produces .estimator/calibration.json plus a readable summary.

Two things this does that matter more than the statistics:

1. Strips every person-identifying field before any analysis runs. The tool must
   not learn that work assigned to particular people takes longer — that is
   performance surveillance wearing an estimation costume, and it is out of
   scope permanently, not just by default.

2. Judges whether the data can support estimation at all, and says so. Thin
   buckets and batch-resolved tickets produce confident nonsense; refusing is
   the correct output in those cases.
"""

import json
import sys
import os
import re
from collections import defaultdict
from datetime import datetime

PII_FIELDS = {
    "assignee", "reporter", "creator", "watcher", "watches",
    "author", "updateAuthor", "displayName", "emailAddress",
    "accountId", "votes", "voter",
}


def strip_pii(obj):
    """Remove person-identifying fields recursively, before anything reads them."""
    if isinstance(obj, dict):
        return {k: strip_pii(v) for k, v in obj.items() if k not in PII_FIELDS}
    if isinstance(obj, list):
        return [strip_pii(v) for v in obj]
    return obj


def load_items(path):
    with open(path) as f:
        data = json.load(f)
    if isinstance(data, list):
        items = data
    else:
        items = (data.get("issues") or data.get("values")
                 or data.get("workItems") or data.get("results") or [])
    return [strip_pii(i) for i in items]


def parse_dt(s):
    if not s:
        return None
    s = str(s).strip()
    # Jira: 2026-03-14T09:12:33.000+0000
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z",
                "%Y-%m-%dT%H:%M:%S.%f", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def find_points(fields):
    """Story points live in a per-instance custom field. Find it by shape."""
    for key in ("storyPoints", "story_points", "points", "estimate"):
        v = fields.get(key)
        if isinstance(v, (int, float)):
            return float(v)
    # Custom fields: a bare small number is almost certainly points.
    for k, v in fields.items():
        if not k.startswith("customfield"):
            continue
        if isinstance(v, (int, float)) and 0 < float(v) <= 100:
            return float(v)
    return None


def find_sprints(fields):
    """Sprint membership. Length > 1 means the story was carried over."""
    for k, v in fields.items():
        if "sprint" not in k.lower() and not k.startswith("customfield"):
            continue
        if isinstance(v, list) and v:
            names = []
            for entry in v:
                if isinstance(entry, dict) and ("name" in entry or "id" in entry):
                    names.append(str(entry.get("name") or entry.get("id")))
                elif isinstance(entry, str) and ("name=" in entry or "sprint" in entry.lower()):
                    m = re.search(r"name=([^,\]]+)", entry)
                    names.append(m.group(1) if m else entry[:40])
            if names:
                return names
    return []


def pct(values, p):
    if not values:
        return None
    s = sorted(values)
    i = max(0, min(len(s) - 1, int(round((p / 100.0) * (len(s) - 1)))))
    return s[i]


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    path = sys.argv[1]
    if not os.path.exists(path):
        print(f"Not found: {path}")
        sys.exit(1)

    items = load_items(path)
    if not items:
        print("No work items in the file. Check the fetch step.")
        sys.exit(2)

    records = []
    for it in items:
        f = it.get("fields", it)
        pts = find_points(f)
        created = parse_dt(f.get("created"))
        resolved = parse_dt(f.get("resolutiondate") or f.get("resolutionDate"))
        sprints = find_sprints(f)
        lead = None
        if created and resolved:
            try:
                lead = (resolved - created).total_seconds() / 86400.0
            except TypeError:
                lead = None
        itype = ((f.get("issuetype") or f.get("issueType") or {}) or {})
        itype = itype.get("name") if isinstance(itype, dict) else str(itype)
        desc = f.get("description")
        desc_len = len(json.dumps(desc)) if desc else 0
        records.append({
            "key": it.get("key"),
            "summary": (f.get("summary") or "")[:120],
            "type": itype,
            "points": pts,
            "lead_days": lead,
            "sprints": len(sprints),
            "carried": len(sprints) > 1,
            "desc_len": desc_len,
            "labels": f.get("labels") or [],
            "resolved": resolved.isoformat() if resolved else None,
            "resolved_raw": resolved,
        })

    total = len(records)
    pointed = [r for r in records if r["points"] is not None]
    with_lead = [r for r in pointed if r["lead_days"] is not None]
    with_sprint = [r for r in pointed if r["sprints"] > 0]

    print("=" * 62)
    print("CALIBRATION DATA QUALITY")
    print("=" * 62)
    print(f"  Work items fetched:        {total}")
    print(f"  With a point value:        {len(pointed)}")
    print(f"  With usable dates:         {len(with_lead)}")
    print(f"  With sprint membership:    {len(with_sprint)}")
    print("  Person fields:             STRIPPED before analysis")

    blockers = []
    warnings = []

    if len(pointed) < 30:
        blockers.append(
            f"Only {len(pointed)} pointed stories. Below ~30 the per-point "
            "buckets are noise. Widen the date range or accept that estimation "
            "is not yet supportable.")

    # Batch-resolution detection. If many stories share a resolution minute,
    # someone dragged a column and the elapsed times mean nothing.
    stamps = defaultdict(int)
    for r in with_lead:
        if r["resolved_raw"]:
            stamps[r["resolved_raw"].strftime("%Y-%m-%d %H:%M")] += 1
    if stamps:
        biggest = max(stamps.values())
        clustered = sum(v for v in stamps.values() if v >= 5)
        share = clustered / max(1, len(with_lead))
        print(f"  Largest same-minute batch: {biggest}")
        if share > 0.3:
            warnings.append(
                f"{share:.0%} of stories were resolved in batches of 5+ within the "
                "same minute. Resolution dates are bookkeeping, not completion "
                "times — treat lead-time numbers as unreliable and lean on "
                "carryover instead.")

    if with_sprint:
        print(f"  Carryover rate (overall):  "
              f"{sum(1 for r in with_sprint if r['carried']) / len(with_sprint):.0%}")
    else:
        warnings.append(
            "No sprint membership found. Carryover cannot be detected, which "
            "removes the most reliable signal that a story was under-pointed.")

    print()
    print("=" * 62)
    print("PER-POINT DISTRIBUTION")
    print("=" * 62)
    buckets = defaultdict(list)
    for r in pointed:
        buckets[r["points"]].append(r)

    profile = {}
    print(f"  {'pts':>5} {'n':>4} {'lead: p25':>10} {'med':>7} {'p75':>7} "
          f"{'carried':>8}  verdict")
    for p in sorted(buckets):
        rs = buckets[p]
        leads = [r["lead_days"] for r in rs if r["lead_days"] is not None]
        sp = [r for r in rs if r["sprints"] > 0]
        carry = (sum(1 for r in sp if r["carried"]) / len(sp)) if sp else None
        med = pct(leads, 50)
        # Precedence matters: a thin bucket must never yield a confident verdict.
        # Six samples showing high carryover is not evidence of under-pointing.
        if len(rs) < 8:
            verdict = "THIN — do not rely on"
        elif carry is not None and carry > 0.4:
            verdict = "UNDER-POINTED"
        else:
            verdict = "ok"
        print(f"  {p:>5} {len(rs):>4} "
              f"{(f'{pct(leads,25):.1f}' if leads else '-'):>10} "
              f"{(f'{med:.1f}' if med else '-'):>7} "
              f"{(f'{pct(leads,75):.1f}' if leads else '-'):>7} "
              f"{(f'{carry:.0%}' if carry is not None else '-'):>8}  {verdict}")
        profile[str(p)] = {
            "n": len(rs),
            "lead_p25": pct(leads, 25), "lead_median": med, "lead_p75": pct(leads, 75),
            "carryover_rate": carry,
            "sufficient": len(rs) >= 8,
        }

    # Reference exemplars: the method is nearest-neighbour against real stories,
    # not a fitted model, so the examples are the useful artifact.
    print()
    print("=" * 62)
    print("REFERENCE STORIES (exemplars per point value)")
    print("=" * 62)
    refs = {}
    for p in sorted(buckets):
        rs = [r for r in buckets[p] if r["lead_days"] is not None]
        rs.sort(key=lambda r: abs((r["lead_days"] or 0) - (profile[str(p)]["lead_median"] or 0)))
        chosen = rs[:4]
        refs[str(p)] = [{"key": r["key"], "summary": r["summary"], "type": r["type"],
                         "lead_days": round(r["lead_days"], 1) if r["lead_days"] else None,
                         "carried": r["carried"]} for r in chosen]
        if chosen:
            print(f"  {p} point(s):")
            for r in chosen:
                flag = " [carried]" if r["carried"] else ""
                print(f"    {r['key']:<12} {r['lead_days']:>5.1f}d{flag}  {r['summary'][:60]}")

    print()
    if blockers:
        print("BLOCKERS — do not estimate from this data:")
        for b in blockers:
            print(f"  ! {b}")
    if warnings:
        print("WARNINGS:")
        for w in warnings:
            print(f"  ~ {w}")
    if not blockers and not warnings:
        print("No data-quality problems detected.")

    out = os.path.join(os.path.dirname(path) or ".", "calibration.json")
    with open(out, "w") as fh:
        json.dump({
            "generated": datetime.now().isoformat(timespec="seconds"),
            "source_items": total,
            "pointed_items": len(pointed),
            "per_point": profile,
            "reference_stories": refs,
            "blockers": blockers,
            "warnings": warnings,
            "pii_stripped": True,
        }, fh, indent=2)
    print(f"\nProfile written: {out}")


if __name__ == "__main__":
    main()
