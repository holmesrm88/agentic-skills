# Semantic Review

What to look for that a pattern scan cannot see. The static pass finds tests that obviously cannot fail; this finds tests that can fail but do not test the right thing.

## The mutation thought experiment

The most reliable method, and worth doing explicitly rather than by intuition.

For each test, identify the production code it covers. Then imagine breaking that code:

- Replace the method body with `return null`, `return 0`, or `return true`.
- Delete the conditional branch the test is meant to exercise.
- Invert a comparison — `>` to `>=`, `==` to `!=`.
- Remove the validation entirely.
- Return an empty collection instead of the real one.

**If the test still passes under any of these, it does not protect that behaviour.** Write down which mutation survives; that is the finding, and it is far more convincing than "this test looks weak."

This is manual mutation testing. Real mutation testing does it exhaustively and is the ground truth — see `ci-integration.md`. Doing it by hand on the changed code is a good approximation at a fraction of the cost.

## Java (JUnit 5, Mockito, AssertJ)

**Methods that are never run.** The static scan flags a method with assertions and no `@Test`, but check the related cases it cannot: a `@Test` method that is `static` or `private` may not be executed depending on the JUnit version and configuration, and a `@Nested` inner class without the annotation is skipped wholesale along with every test inside it. Note that the `testFoo()` naming convention means nothing in JUnit 4 and 5 — only the annotation does — so a method named `testSomething` with no annotation is dead code, not a test.

**Mock verification standing in for assertion.** `verify(repository).save(any())` proves a call occurred. It does not prove the saved object was right, or that the method returned what the caller needs. Look for an `ArgumentCaptor` asserting the captured value, or an assertion on the return. Without one, the test is coupled to the mechanism and blind to the outcome.

**`any()` everywhere.** `verify(service).process(any(), any(), any())` passes for any arguments at all, including wrong ones. Specific matchers or a captor are what make verification mean something.

**Stub-then-assert-the-stub.** `when(repo.find(1)).thenReturn(order)` followed by an assertion that `find(1)` returns `order` tests Mockito, not the code.

**Over-mocking.** If the class under test is a spy with the method under test stubbed, nothing real is exercised. Mocked value objects and DTOs are a related smell — they have no behaviour to mock.

**`assertThat(x).isNotNull()` as the whole test.** Rarely meaningful. Something existing is not something being correct.

**Exception tests without message or type checks.** `assertThrows(Exception.class, ...)` passes for a `NullPointerException` raised by a typo in the test fixture. Assert the specific type, and the message when it carries information.

**Parameterized tests with only passing cases.** `@ValueSource` listing five valid inputs and no invalid ones is a happy-path test with extra ceremony.

**Missing transactional or persistence reality.** A repository test against a mocked `EntityManager` verifies almost nothing about whether the query works. Note when a test's abstraction level makes it incapable of catching the class of bug it appears to target.

## Playwright

**Missing `await` — caught by the static scan, but understand why it matters.** `expect(locator).toBeVisible()` without `await` returns a promise nobody checks. The test always passes. This is the single most common Playwright ghost and it is invisible in review because the line looks correct.

**Assertions on the page object rather than content.** `expect(page).toBeTruthy()` is always true. So is asserting a locator exists without asserting anything about it.

**`toBeVisible()` as the only check.** An element being visible says nothing about it containing the right thing. Pair visibility with `toHaveText`, `toHaveValue`, or `toHaveCount`.

**Navigation without verification.** `await page.goto('/orders')` followed by assertions that would pass on any page — the error page included. Assert something specific to the expected page.

**`waitForTimeout` instead of web-first assertions.** A fixed sleep is both slow and flaky. Playwright's assertions retry by design; use them.

**Soft assertions never checked.** `expect.soft()` records a failure without stopping the test. If nothing checks `test.info().errors`, the test can pass with failed expectations inside it.

**Selectors so loose they match anything.** `page.locator('div')` with `toBeVisible()` passes on nearly any page. Test-ids or roles make the assertion mean something.

**No negative assertion after an action.** Filling a form and asserting success without asserting the error is absent — or asserting the error without confirming the record was not created — tests half the behaviour.

## Coverage against acceptance criteria

Map each criterion to assertions. Then check the shape of the coverage:

**Each criterion needs at least one assertion.** A criterion with none means the story is unverified. High severity — that is the definition of done going unchecked.

**Each criterion implying rejection needs both directions.** "Only admins can delete" needs an admin succeeding and a non-admin being denied. Testing only the permitted case is the most common gap in authorization code, and the failure mode is a security bug.

**Criteria with implicit boundaries need boundary tests.** "At least 1" needs 0, 1, and ideally 2. "Up to 100" needs 100 and 101.

**Criteria describing error behaviour need the error asserted**, not just that an exception occurred.

## Edge cases worth naming

Enumerate against what the code actually does rather than reciting a list. The ones that most often matter:

- **Null and empty** — null input, empty string, empty collection, whitespace-only.
- **Boundaries** — the exact value on every comparison, and one either side.
- **Zero and negative** — for anything numeric, particularly quantities and money.
- **Collection sizes** — 0 and 1 behave differently from n in most code.
- **Duplicates** — where uniqueness is assumed but not enforced.
- **Long and unicode strings** — where fields have limits or get rendered.
- **Concurrency** — where shared state is reachable from more than one thread.
- **The error path** — every `throw` should have a test reaching it.

Report the ones that matter for this change and say why. A generic list is noise and gets skimmed.

## Calibration

**Do not flag** an untested trivial getter, tests that are simple because the code is simple, a convention used consistently across the suite, or a missing edge case that the type system already prevents.

**Do flag** any test that cannot fail, any acceptance criterion with no assertion, any changed behaviour no test reaches, and positive-only testing of anything that rejects, filters, or authorizes.

**State uncertainty.** "If `OrderService.create` is called concurrently this test would not catch the race, but I cannot see the callers from this diff" is more useful than either silence or a confident claim.
