# Execution Modes

Three ways to verify behavior in the dev environment. Most stories need a mix, and the choice is dictated by where the behavior is observable — not by which repo the change landed in.

## Mode 1 — UI

Drive the deployed frontend through the browser.

**Use for** anything a user does: forms, navigation, rendered data, validation messages, visible state changes.

**Practical notes**

- Prefer stable selectors — a test id, a role, a label. Text content and CSS classes drift, and a check that breaks on a copy change is noise.
- Wait for the condition, not for a duration. A fixed sleep is the same flakiness in verification that it is in a test suite.
- Check the browser console. A page can render correctly while throwing errors that indicate the feature is half-working.
- Screenshot the specific element, not the whole page. A full-page screenshot as evidence for "the error message appeared" makes a reviewer hunt for it.

**Watch for**: a page that renders from cached assets after a redeploy. A hard reload confirms you are testing the current build.

## Mode 2 — API from the page context

Run authenticated requests as `fetch` from within the already-logged-in page, using the session cookie the browser already holds.

**Use for** backend behavior with no UI surface, response-shape assertions, status codes, and setting up or inspecting data for a UI check.

**This is the method that keeps credentials out of scope entirely** — the session already exists in the browser, and no token passes through the skill. `curl` from a terminal would require a credential, so it is not an option here.

**Practical notes**

- Include credentials in the request so the session cookie is sent.
- Assert on the status code *and* the body. A 200 with an empty or wrong payload is a failure.
- Read responses as text before parsing — an HTML error page parsed as JSON produces a confusing error that hides the real one.
- Note the exact endpoint and method in the evidence, so a reader can repeat it.

**Never** use this mode to call an endpoint that changes state without confirming first. See the safety rules in the skill.

## Mode 3 — Logs and data

For behavior with no observable surface at all: background jobs, audit records, retry logic, emitted events.

**Use sparingly.** Reaching for logs often means the behavior is not really observable, which is worth reporting in itself — untestable behavior is a design finding.

**Practical notes**

- Know where the logs are before you need them. If retrieval is not established, say so rather than guessing at a path or a command.
- Match on a specific, recent event. Log searches that match historical entries produce false passes, which is the worst kind.
- Note the timestamp in the evidence so the entry is tied to your action rather than someone else's.

**Direct database inspection** is a last resort. It is read-only by default, it may not be available, and a behavior only verifiable by querying the database is usually a gap in the feature rather than a gap in the test.

## Choosing

| Behavior | Mode |
|---|---|
| User-visible change | UI |
| Response shape or status | API |
| Validation message | UI (the message is the behavior) |
| Authorization rule | API — call it as a user who should be denied |
| Data written correctly | API read-back, or UI if it is displayed |
| Background or async work | Logs |
| Nothing observable anywhere | Report it as unverifiable |

## Setup and teardown

Checks needing specific data have two options, and the choice matters in a shared environment.

**Create it as part of the check.** Better, because it exercises the real path and is self-contained. Use obviously-labelled test values — the kind nobody mistakes for real data.

**Use existing data.** Faster, but it may be gone or changed next week, and someone else's edit can silently invalidate the result. If a check depends on pre-existing data, say which record, so a later failure is diagnosable.

**Clean up what you can, report what you cannot.** Records left behind are visible to teammates. Listing them in the report is the minimum; a dev environment slowly filling with a verification run's debris is a real cost that nobody attributes correctly.
