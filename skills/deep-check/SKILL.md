---
name: deep-check
description: >-
  Evidence-first verification of anything: a claim, a fix, a config, a deployment, a dataset, a
  piece of content, another AI's output. Produces a verdict (CONFIRMED / PLAUSIBLE / UNVERIFIED /
  REFUTED) backed by primary evidence gathered with tools, plus an explicit list of what was NOT
  checked. Use whenever the user says "check this", "verify", "double-check", "is this actually
  working", "audit this", "make sure", "did it really", or before telling the user that something
  works, is fixed, is deployed, or is done. Also use to review work done by subagents, scripts, or
  earlier sessions before trusting it.
---

# Deep Check

The core rule: **a claim is unverified until you have seen primary evidence through your own tools in this session.** Names, comments, docs, commit messages, agent reports, and your own memory of earlier turns are all testimony, not evidence.

## Method

Work through these five steps for each claim being checked. For a batch of claims, triage first: verify the load-bearing ones deeply, spot-check the rest.

### 1. State the claim precisely

"The site works" is not checkable. "GET https://example.com/sitemap.xml returns 200 with ≥40 URLs" is. Rewrite vague claims into observable statements before checking anything — often the rewrite alone exposes that nobody knows what was actually promised.

### 2. Enumerate how it could be false

Spend a moment listing the 2–4 most likely failure modes. This decides *what* to observe. A fix can be false because: the code path never executes, an edge case bypasses it, it works locally but not where it's deployed, it broke something adjacent, or the observed success was cached/stale.

### 3. Choose the cheapest discriminating observation

Pick the observation that would distinguish true from false, not the one that merely feels related. Reading the code that *should* produce behavior X is weaker than triggering behavior X and watching it happen. Prefer, in order:

1. **Exercise the real flow** — run the command, hit the endpoint, open the file the user will open, run the app end to end.
2. **Inspect the actual artifact** — read the deployed file, the generated output, the DB row (not the source that supposedly produces it).
3. **Read the code/config** — weakest; acceptable only when execution is impossible.

### 4. Observe, with traps in mind

- File exists ≠ file has correct content. Read it.
- Exit code 0 ≠ success. Read the output; many tools fail politely.
- Tests pass ≠ feature works. Tests check what tests check. Drive the real flow for anything user-facing.
- "It worked earlier in this conversation" ≠ it works now, if anything changed since.
- Docs and comments describe intent at time of writing, not current reality.
- Memory files and CLAUDE.md describe what was true when written — re-verify paths, flags, and URLs before relying on them.
- A signal that pattern-matches a known failure may have a different cause; check that evidence supports the *specific* diagnosis before acting on it.

### 5. Assign a verdict

- **CONFIRMED** — primary evidence observed in this session directly supports the claim.
- **PLAUSIBLE** — code/config reading supports it but the flow was not exercised. Say what would upgrade it.
- **UNVERIFIED** — could not gather discriminating evidence (missing access, env, credentials). Never round this up to "probably fine".
- **REFUTED** — evidence contradicts the claim. Quote the evidence.

## Independent verification

When the stakes are high or you produced the work yourself, spawn a `verifier` agent (or general-purpose agent) to check it *without telling it the expected answer*. Give it the claim and the paths, not your reasoning. Confirmation from an agent that was told "confirm this works" is worthless; confirmation from one asked "determine whether X is true" is signal.

## Report format

Lead with the verdict, then evidence, then gaps:

```
**Verdict:** CONFIRMED (2 of 3 claims) / REFUTED (1)

1. <claim> — CONFIRMED. <one line of evidence: command run + relevant output, or file + line>
2. <claim> — REFUTED. <quoted evidence>
3. <claim> — PLAUSIBLE. <what was read; what real-flow test would confirm it>

**Not checked:** <anything in scope you didn't verify, and why>
```

The "Not checked" section is mandatory. Silent scope-shrinking — verifying the easy 80% and letting the reader assume 100% — is the most common way verification lies.
