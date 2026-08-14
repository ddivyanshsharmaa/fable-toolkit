---
name: deep-check
description: >-
  Evidence first verification of anything: a claim, a fix, a config, a deployment, a dataset, a
  piece of content, another AI's output. Produces a verdict (CONFIRMED / PLAUSIBLE / UNVERIFIED /
  REFUTED) backed by primary evidence gathered with tools, plus an explicit list of what was NOT
  checked. Use whenever the user says "check this", "verify", "double-check", "is this actually
  working", "audit this", "make sure", "did it really", or before telling the user that something
  works, is fixed, is deployed, or is done. Also use to review work done by subagents, scripts, or
  earlier sessions before trusting it.
---

# Deep Check

The core rule: **a claim is unverified until you have seen primary evidence through your own tools
in this session.** Names, comments, docs, commit messages, agent reports, and your own memory of
earlier turns are all testimony, not evidence.

## Method

Work through these five steps for each claim being checked. For a batch of claims, triage first:
verify the load bearing ones deeply and spot check the rest.

### 1. State the claim precisely

"The site works" is not checkable. "GET https://example.com/sitemap.xml returns 200 with at least 40
URLs" is. Rewrite vague claims into observable statements before checking anything. Often the
rewrite alone exposes that nobody knows what was actually promised.

### 2. Enumerate how it could be false

Spend a moment listing the two to four most likely failure modes, because that decides *what* to
observe. A fix can be false because the code path never executes, an edge case bypasses it, it works
locally but not where it is deployed, it broke something adjacent, or the observed success was
cached and stale.

### 3. Choose the cheapest discriminating observation

Pick the observation that would distinguish true from false, not the one that merely feels related.
Reading the code that *should* produce behaviour X is weaker than triggering behaviour X and
watching it happen. Prefer, in order:

1. **Exercise the real flow.** Run the command, hit the endpoint, open the file the user will open,
   run the app end to end.
2. **Inspect the actual artifact.** Read the deployed file, the generated output, the database row,
   rather than the source that supposedly produces it.
3. **Read the code or config.** Weakest, and acceptable only when execution is impossible.

### 4. Observe, with the traps in mind

- A file existing is not the same as a file having the correct content. Read it.
- Exit code 0 is not success. Read the output, because many tools fail politely.
- Tests passing is not the same as the feature working. Tests check what tests check, so drive the
  real flow for anything user facing.
- "It worked earlier in this conversation" is not "it works now", if anything changed since.
- Docs and comments describe intent at the time of writing, not current reality.
- Memory files and CLAUDE.md describe what was true when written, so re-verify paths, flags, and
  URLs before relying on them.
- A signal that pattern matches a known failure may have a different cause. Check that the evidence
  supports the *specific* diagnosis before acting on it.

### 5. Assign a verdict

- **CONFIRMED.** Primary evidence observed in this session directly supports the claim.
- **PLAUSIBLE.** Code or config reading supports it, but the flow was not exercised. Say what would
  upgrade it.
- **UNVERIFIED.** Could not gather discriminating evidence, for example missing access, environment
  or credentials. Never round this up to "probably fine".
- **REFUTED.** Evidence contradicts the claim. Quote the evidence.

## Independent verification

When the stakes are high, or when you produced the work yourself, spawn a `verifier` agent (or a
general-purpose agent) to check it *without telling it the expected answer*. Give it the claim and
the paths, not your reasoning. Confirmation from an agent that was told "confirm this works" is
worthless. Confirmation from one asked "determine whether X is true" is signal.

## Report format

Lead with the verdict, then the evidence, then the gaps:

```
**Verdict:** CONFIRMED (2 of 3 claims) / REFUTED (1)

1. <claim> = CONFIRMED. <one line of evidence: command run plus relevant output, or file and line>
2. <claim> = REFUTED. <quoted evidence>
3. <claim> = PLAUSIBLE. <what was read, and what real flow test would confirm it>

**Not checked:** <anything in scope you did not verify, and why>
```

The "Not checked" section is mandatory. Silent scope shrinking, meaning verifying the easy 80
percent and letting the reader assume 100 percent, is the most common way verification lies.
