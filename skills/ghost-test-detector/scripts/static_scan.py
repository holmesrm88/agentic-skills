#!/usr/bin/env python3
"""
static_scan.py — deterministic ghost-test detection for Java and Playwright.

Usage:
    python3 static_scan.py --staged            scan staged test files
    python3 static_scan.py FILE [FILE...]      scan specific files
    python3 static_scan.py --staged --json     machine-readable output

Finds tests that cannot fail: no assertion at all, tautological assertions,
mock-only verification, disabled tests, and — for Playwright — assertions
missing `await`, which is the highest-frequency ghost in that framework because
the assertion returns an unchecked promise and the test always passes.

This is the cheap, deterministic layer. It catches blatant cases with no model
call. It cannot tell whether a test checks the RIGHT behaviour; that is the
semantic pass in the skill itself.

Exit: 0 = nothing found, 1 = findings, 2 = bad usage.
"""

import json
import re
import subprocess
import sys

# ---------------------------------------------------------------- Java

JAVA_TEST_ANN = re.compile(r'@(Test|ParameterizedTest|RepeatedTest|TestFactory)\b')
JAVA_DISABLED = re.compile(r'@(Disabled|Ignore)\b')
# NOTE: BDDMockito's `should()` must be matched with its leading dot. A bare
# `should\w*\(` also matches test METHOD NAMES (shouldCreateOrder(...)), which
# made every conventionally-named test look like it contained an assertion.
JAVA_ASSERT = re.compile(
    r'\b(assert[A-Z]\w*|assertThat|assertThatThrownBy|assertThatCode|assertAll|'
    r'fail|verify|verifyNoInteractions|verifyNoMoreInteractions|'
    r'expectThrows|assertThrows)\s*\(|\.\s*should\s*\(|\bthen\s*\(\s*\w+\s*\)\s*\.')
JAVA_REAL_ASSERT = re.compile(
    r'\b(assert[A-Z]\w*|assertThat|assertThatThrownBy|assertThatCode|assertAll|'
    r'fail|assertThrows|expectThrows)\s*\(')
JAVA_VERIFY = re.compile(r'\bverify(NoInteractions|NoMoreInteractions)?\s*\(')

JAVA_TAUTOLOGIES = [
    (re.compile(r'\bassertTrue\s*\(\s*true\s*\)'), "assertTrue(true) can never fail"),
    (re.compile(r'\bassertFalse\s*\(\s*false\s*\)'), "assertFalse(false) can never fail"),
    (re.compile(r'\bassertNotNull\s*\(\s*new\s+\w'), "asserting a freshly constructed object is non-null proves nothing"),
    (re.compile(r'\bassertEquals\s*\(\s*(\w+)\s*,\s*\1\s*\)'), "assertEquals compares a value with itself"),
    (re.compile(r'\bassertThat\s*\(\s*(\w+)\s*\)\s*\.isEqualTo\s*\(\s*\1\s*\)'), "assertThat compares a value with itself"),
    (re.compile(r'\bassertThat\s*\(\s*true\s*\)\s*\.isTrue\s*\(\)'), "tautological assertion"),
    (re.compile(r'\bassertThat\s*\(\s*\w+\s*\)\s*\.isNotNull\s*\(\)\s*;?\s*$'), "isNotNull as the only assertion rarely verifies behaviour"),
]

JAVA_FLAKE = [
    (re.compile(r'\bThread\.sleep\s*\('), "Thread.sleep makes the test slow and flaky; use Awaitility or a deterministic latch"),
    (re.compile(r'\bLocalDate(Time)?\.now\s*\(\s*\)'), "wall-clock time in a test; inject a Clock so boundaries are testable"),
    (re.compile(r'\bnew\s+Random\s*\(\s*\)'), "unseeded Random makes failures unreproducible"),
]

JAVA_SWALLOW = re.compile(r'catch\s*\([^)]*\)\s*\{\s*\}')

# Any method declaration in a test class. Used to find methods that LOOK like
# tests but carry no @Test annotation, so JUnit never runs them.
JAVA_METHOD_DECL = re.compile(
    r'^\s*(?:@\w+(?:\([^)]*\))?\s*)*'
    r'(?:public|protected|private|static|final|\s)*'
    r'(?:void|[\w<>\[\],\s]+?)\s+(\w+)\s*\([^)]*\)\s*(?:throws\s+[\w,\s.]+)?\s*\{')
# JUnit lifecycle and helper annotations — annotated, intentionally not tests.
JAVA_LIFECYCLE = re.compile(
    r'@(BeforeEach|AfterEach|BeforeAll|AfterAll|Before|After|BeforeClass|AfterClass|'
    r'Nested|Provide|MethodSource|ParameterizedTest|RepeatedTest|TestFactory|TestTemplate|'
    r'Override|Bean|Configuration)\b')
# JUnit 3: classes extending TestCase run testFoo() by name, with no annotation.
JAVA_JUNIT3 = re.compile(r'\bextends\s+(TestCase|junit\.framework\.TestCase)\b')

# ---------------------------------------------------------- Playwright / TS

PW_TEST = re.compile(r'\b(test|it)\s*(\.\w+)?\s*\(\s*[\'"`]')
PW_SKIP = re.compile(r'\b(test|it|describe)\s*\.\s*(skip|fixme|todo)\b')
PW_EXPECT = re.compile(r'\bexpect\s*\(')
PW_ACTION = re.compile(r'\bpage\s*\.\s*(click|fill|goto|press|check|selectOption|type)\s*\(')

# `expect(...).toBeVisible()` without await never runs. The single most common
# Playwright ghost, and fully detectable statically.
PW_ASYNC_MATCHERS = (
    r'toBeVisible|toBeHidden|toBeEnabled|toBeDisabled|toBeChecked|toBeEditable|'
    r'toBeEmpty|toBeFocused|toBeAttached|toBeInViewport|toHaveText|toContainText|'
    r'toHaveValue|toHaveValues|toHaveAttribute|toHaveClass|toHaveCount|toHaveCSS|'
    r'toHaveId|toHaveJSProperty|toHaveScreenshot|toHaveTitle|toHaveURL|toBeOK'
)
PW_MISSING_AWAIT = re.compile(
    r'(?<!await\s)(?<!return\s)(?<!\.)\bexpect\s*\([^;]*?\)\s*(\.not)?\s*\.\s*(' + PW_ASYNC_MATCHERS + r')\s*\(')

PW_TAUTOLOGIES = [
    (re.compile(r'\bexpect\s*\(\s*true\s*\)\s*\.\s*toBe(Truthy)?\s*\(\s*true\s*\)?\s*\)'), "tautological assertion"),
    (re.compile(r'\bexpect\s*\(\s*true\s*\)\s*\.\s*toBeTruthy\s*\(\)'), "expect(true).toBeTruthy() can never fail"),
    (re.compile(r'\bexpect\s*\(\s*(\w+)\s*\)\s*\.\s*toBe\s*\(\s*\1\s*\)'), "expect compares a value with itself"),
    (re.compile(r'\bexpect\s*\(\s*page\s*\)\s*\.\s*toBeTruthy\s*\(\)'), "asserting the page object is truthy proves nothing"),
    (re.compile(r'\bexpect\s*\(\s*\w+\s*\)\s*\.\s*toBeDefined\s*\(\)\s*;?\s*$'), "toBeDefined as the only assertion rarely verifies behaviour"),
]

PW_FLAKE = [
    (re.compile(r'\bpage\s*\.\s*waitForTimeout\s*\('), "waitForTimeout is a fixed sleep; use a web-first assertion that retries"),
    (re.compile(r'\.\s*catch\s*\(\s*\(\s*\)\s*=>\s*\{\s*\}\s*\)'), "swallowed rejection hides failures"),
]

PW_SOFT = re.compile(r'\bexpect\s*\.\s*soft\s*\(')
PW_SOFT_CHECK = re.compile(r'expectsToFail|test\.info\(\)\.errors')


def staged_files():
    try:
        out = subprocess.run(
            ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
            capture_output=True, text=True, check=True).stdout
    except Exception:
        return []
    files = []
    for f in out.splitlines():
        if re.search(r'(^|/)(src/test|tests?|e2e|spec|__tests__)/', f) or \
           re.search(r'([._-](test|spec)\.[jt]sx?|Test[s]?\.java|Tests?\.kt)$', f):
            files.append(f)
    return files


def java_blocks(text):
    """Yield (start_line, block_text) per @Test method, via brace matching."""
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if not JAVA_TEST_ANN.search(re.sub(r'//.*$', '', line)):
            continue
        # Annotations stack in any order, so @Disabled may sit above @Test.
        # Walk back over CONSECUTIVE annotation/blank lines only — going further
        # drags the previous test's body in and misattributes its findings.
        ann = []
        k = i - 1
        while k >= 0:
            stripped = lines[k].strip()
            if stripped.startswith("@") or stripped == "" or stripped.startswith("//"):
                ann.insert(0, lines[k])
                k -= 1
            else:
                break
        depth, started, buf = 0, False, []
        for j in range(i, min(len(lines), i + 400)):
            buf.append(lines[j])
            depth += lines[j].count("{") - lines[j].count("}")
            if "{" in lines[j]:
                started = True
            if started and depth <= 0:
                break
        yield i + 1, "\n".join(ann), "\n".join(buf)


def ts_blocks(text):
    """Yield (start_line, block_text) per test()/it() call."""
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if not PW_TEST.search(line):
            continue
        depth, started, buf = 0, False, []
        for j in range(i, min(len(lines), i + 400)):
            buf.append(lines[j])
            depth += lines[j].count("{") - lines[j].count("}")
            if "{" in lines[j]:
                started = True
            if started and depth <= 0:
                break
        yield i + 1, "\n".join(buf)


def strip_signature(block):
    """Drop the declaration line; a method named shouldDoX() is not an assertion."""
    lines = block.split("\n")
    for i, ln in enumerate(lines):
        if "{" in ln:
            return "\n".join(lines[i:])
    return block


def strip_noise(block):
    """Remove comments and string literals so patterns don't match inside them."""
    b = re.sub(r'/\*.*?\*/', '', block, flags=re.S)
    b = re.sub(r'//[^\n]*', '', b)
    b = re.sub(r'"(?:[^"\\]|\\.)*"', '""', b)
    b = re.sub(r"'(?:[^'\\]|\\.)*'", "''", b)
    return b


def name_of(block, java):
    if java:
        m = re.search(r'(?:public|private|protected|\s)\s*(?:void|[\w<>\[\]]+)\s+(\w+)\s*\(', block)
        return m.group(1) if m else "<unnamed>"
    m = re.search(r'\b(?:test|it)\s*(?:\.\w+)?\s*\(\s*[\'"`]([^\'"`]{0,80})', block)
    return m.group(1) if m else "<unnamed>"


def java_unannotated_tests(text, findings, path):
    """Methods with assertions but no @Test. JUnit silently never runs these."""
    junit3 = bool(JAVA_JUNIT3.search(text))
    lines = text.split("\n")
    for i, line in enumerate(lines):
        m = JAVA_METHOD_DECL.match(line)
        if not m:
            continue
        name = m.group(1)
        if name in ("if", "for", "while", "switch", "catch", "try", "synchronized", "return"):
            continue

        # Look back over consecutive annotation lines. Strip comments first:
        # an "@Test" mentioned in a comment would otherwise make this method
        # look annotated and be silently skipped.
        ann, k = [], i - 1
        while k >= 0:
            st = lines[k].strip()
            if st.startswith("@") or st == "" or st.startswith("//"):
                ann.insert(0, re.sub(r'//.*$', '', st)); k -= 1
            else:
                break
        annotations = "\n".join(ann) + "\n" + re.sub(r'//.*$', '', line)

        if JAVA_TEST_ANN.search(annotations):
            continue                      # properly annotated; handled elsewhere
        if JAVA_LIFECYCLE.search(annotations):
            continue                      # setup, teardown, factories, sources
        if junit3 and name.startswith("test"):
            continue                      # JUnit 3 runs these by name

        # Body
        depth, started, buf = 0, False, []
        for j in range(i, min(len(lines), i + 400)):
            buf.append(lines[j])
            depth += lines[j].count("{") - lines[j].count("}")
            if "{" in lines[j]:
                started = True
            if started and depth <= 0:
                break
        body = strip_noise(strip_signature("\n".join(buf)))

        if not JAVA_REAL_ASSERT.search(body):
            continue                      # a plain helper method; fine

        # Helpers called BY tests also contain assertions. Only flag methods that
        # nothing else calls — an uncalled, unannotated, asserting method is dead.
        called = len(re.findall(r'\b' + re.escape(name) + r'\s*\(', text))
        if called > 1:
            continue                      # referenced elsewhere: a shared helper

        findings.append({
            "file": path, "line": i + 1, "test": name, "severity": "high",
            "message": "contains assertions but has no @Test annotation and is never "
                       "called — JUnit does not run it, so it protects nothing"})


def scan_java(path, text, findings):
    java_unannotated_tests(text, findings, path)
    for line_no, ann, raw in java_blocks(text):
        block = strip_noise(strip_signature(raw))
        name = name_of(raw, True)

        def add(sev, msg):
            findings.append({"file": path, "line": line_no, "test": name,
                             "severity": sev, "message": msg})

        ann_clean = re.sub(r'//.*$', '', ann, flags=re.M)
        first_clean = re.sub(r'//.*$', '', raw.split("\n")[0])
        if JAVA_DISABLED.search(ann_clean) or JAVA_DISABLED.search(first_clean):
            add("medium", "test is disabled — it provides no protection while it stays off")
            continue
        if not JAVA_ASSERT.search(block):
            add("high", "no assertion and no verification — this test cannot fail")
            continue
        if not JAVA_REAL_ASSERT.search(block) and JAVA_VERIFY.search(block):
            add("high", "only verifies mock interactions; asserts nothing about the outcome")
        for pat, msg in JAVA_TAUTOLOGIES:
            if pat.search(block):
                add("high", msg)
        for pat, msg in JAVA_FLAKE:
            if pat.search(block):
                add("medium", msg)
        if JAVA_SWALLOW.search(block):
            add("high", "empty catch block swallows the failure this test should report")


def scan_ts(path, text, findings):
    for line_no, raw in ts_blocks(text):
        block = strip_noise(raw)
        name = name_of(raw, False)

        def add(sev, msg):
            findings.append({"file": path, "line": line_no, "test": name,
                             "severity": sev, "message": msg})

        if PW_SKIP.search(raw.split("\n")[0]):
            add("medium", "test is skipped — it provides no protection while it stays off")
            continue

        missing = PW_MISSING_AWAIT.findall(block)
        if missing:
            add("high", f"assertion missing `await` ({len(missing)} occurrence(s)) — "
                        "the matcher returns a promise that is never checked, so the test always passes")

        if not PW_EXPECT.search(block):
            if PW_ACTION.search(block):
                add("high", "performs page actions but asserts nothing — cannot fail")
            else:
                add("high", "no assertion — this test cannot fail")
            continue

        for pat, msg in PW_TAUTOLOGIES:
            if pat.search(block):
                add("high", msg)
        for pat, msg in PW_FLAKE:
            if pat.search(block):
                add("medium", msg)
        if PW_SOFT.search(block) and not PW_SOFT_CHECK.search(text):
            add("medium", "soft assertions used but failures are never checked; the test can pass with failed expectations")


def main():
    args = sys.argv[1:]
    as_json = "--json" in args
    args = [a for a in args if a != "--json"]

    if args and args[0] == "--staged":
        files = staged_files()
    elif args:
        files = args
    else:
        print(__doc__)
        return 2

    if not files:
        if not as_json:
            print("No staged test files to scan.")
        return 0

    findings = []
    scanned = 0
    for path in files:
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError:
            continue
        scanned += 1
        if path.endswith((".java", ".kt")):
            scan_java(path, text, findings)
        elif path.endswith((".ts", ".tsx", ".js", ".jsx", ".mjs")):
            scan_ts(path, text, findings)

    if as_json:
        print(json.dumps({"scanned": scanned, "findings": findings}, indent=2))
        return 1 if findings else 0

    print(f"Scanned {scanned} test file(s).")
    if not findings:
        print("No ghost-test patterns found by the static scan.")
        print("Note: this checks only that tests CAN fail, not that they test the")
        print("right thing. The semantic pass covers that.")
        return 0

    high = [f for f in findings if f["severity"] == "high"]
    med = [f for f in findings if f["severity"] == "medium"]
    print(f"\n{len(high)} high, {len(med)} medium\n")
    for group, label in ((high, "HIGH"), (med, "MEDIUM")):
        for f in group:
            print(f"  [{label}] {f['file']}:{f['line']}  {f['test']}")
            print(f"          {f['message']}")
    print()
    return 1


if __name__ == "__main__":
    sys.exit(main())
