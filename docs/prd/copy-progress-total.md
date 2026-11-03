---
spec: spec-clarifier/v1
feature: copy-progress-total
title: Copy bar total progress
status: complete
prompt: inline
prompt_sha256: 1b5ef4a4b514f14b50edb453e535624e88db006b7b9dc8667f14e01987fd97ec
created: 2026-11-03
---

# PRD: Copy bar total progress

## 0. Source prompt

> when we show how much progress is made we should show total progress, plz fix use @ui-ux-cx-engineer @frontend-design @qa-agent prove to me that it's not working the way I've asked for then pr

## 1. Problem

Droplane's bottom copy bar shows a single byte line. In the attached screenshot, a two-file PrimeCam copy reads "28.2 MB of 204.7 MB" while the bar is about 9% full and the header says "1 of 2". The bar and text disagree, and neither tells the user how much of the whole copy is done. Separately, `AppModel.activeProgress` drops a batch from the denominator when its last item finishes, so when the first of two files completes the bar resets toward 0% for the second file instead of carrying the first file's bytes forward. The cost is that a person copying several large clips cannot estimate the remaining time or confirm that both clips are part of one job.

## 2. Target user

- **Primary:** PrimeCam users on a Mac who copy two or more recorded clips from an Android phone in one drag.
- **Secondary:** any Droplane user copying a queue of files or folders in either direction.
- **Explicitly not for:** Windows and Linux users (the app is macOS only), and users who want a history of past copy sessions.
- **Job-to-be-done:** When I copy several clips, I want one bar that shows both the current clip and the whole job, so I can tell how much is left and trust that both clips are included.

## 3. Outcome and success metric

- **Outcome this moves:** Copy confidence: the user can see the whole job's progress and does not mistake a per-file bar for the total.
- **Primary KPI:** In 10 manual two-file copies on the Demo Device and one physical Android phone, the total line equals the sum of the selected files' sizes and the bar equals overall done divided by overall total; 0 of 10 runs may mismatch.
- **Baseline:** 1 observed mismatch on 2026-11-02: the screenshot's bar is about 9% while "28.2 MB of 204.7 MB" is 13.8%, and no total line exists.
- **Target:** 10 of 10 runs match by 2026-11-10, checked in the QA report for this change.
- **Guardrail metrics:** The Transfers window still shows each row's own byte progress; the toolbar ring and the bottom bar show the same overall fraction; no new telemetry or network calls.

## 4. Goals and non-goals

**Goals**
1. Show one overall progress bar in the bottom copy bar.
2. Show the current file's bytes and the whole queue's bytes as two labeled lines when more than one file is in the queue.
3. Keep finished files in the whole-queue total until the queue is empty, so the bar never drops backward when a file finishes.
4. Make the bar, the text lines, the toolbar ring, and VoiceOver report the same overall fraction.

**Non-goals**
1. Changing the per-row progress in the Transfers window; each row keeps its own file bar and bytes.
2. Changing the Dock badge; it keeps the count of unfinished items.
3. Keeping progress history across app launches or after the queue empties; the next copy starts a new total.
4. Adding telemetry, analytics, or a time-remaining estimate.
5. Implementing the parent PRD's 25% VoiceOver progress announcements; this change exposes a current percentage but does not add timed announcements.

## 5. User stories and acceptance criteria

- **[P0]** As a person copying two or more files, I want the bar to show the whole job, so that I can tell how much is left.
  - [ ] Given two files of 204.7 MB and 112.3 MB, when the first file has copied 28.2 MB and the second is queued, then the bar is 8.9% full, the header reads "1 of 2", line one reads "28.2 MB of 204.7 MB this file", and line two reads "28.2 MB of 317 MB total".
  - [ ] Given the first file has finished and the second is running, when the bar updates, then line two includes the first file's 204.7 MB and the bar does not drop below its previous value.
  - [ ] Given a second drag starts while the first copy is still running, when both are in the queue, then the total line includes both drags until the queue is empty.
- **[P0]** As a person copying one file, I want a clear byte line without duplicate labels, so that the bar stays easy to read.
  - [ ] Given one file of 204.7 MB with 28.2 MB copied, when the bar is visible, then it shows one line "28.2 MB of 204.7 MB" and no "1 of 1" text.
- **[P1]** As a person copying a folder, I want the folder's contents counted, so that the total matches the bytes that will move.
  - [ ] Given a folder that contains two files, when the folder is listed and its children are queued, then the folder itself is not an item and the two child files are counted in the total.
- **[P1]** As a person using VoiceOver, I want the bar to announce the same totals, so that I can follow the copy without sight.
  - [ ] Given the two-file copy above, when VoiceOver focuses the copy bar, then it announces "Copying the current file", "File 1 of 2", "9 percent", "28.2 MB of 204.7 MB for this file", and "28.2 MB of 317 MB overall".
- **[P0]** As a person whose copy fails or is cancelled, I want the remaining work to reach 100%, so that a dead item does not leave the bar stuck.
  - [ ] Error: given one file fails or is cancelled with 50 MB of 100 MB copied and a second file is still running, then the failed file's 100 MB is excluded from the total, the header still counts it in "2 of 2", and the bar represents the second file's remaining bytes.
  - [ ] Error: given every file in the queue has an unknown size of 0 bytes, then the bar is indeterminate and the byte line reads "Preparing…" instead of "0 bytes of 0 bytes".

Priorities: **P0** release fails without it · **P1** ship-blocking unless waived · **P2** follow-up.

## 6. Experience notes

- **Surface:** the bottom strip of the main Droplane window, shown while `model.activeCount > 0`; the same overall fraction feeds the circular toolbar ring.
- **Layout:** a direction icon, a header line with the current item name and "N of M", one overall linear bar, and up to two caption lines. Line one is the current file's bytes and is hidden when only one file is in the queue. Line two is the whole queue's bytes.
- **States:** preparing (unknown sizes, indeterminate bar, "Preparing…"), running (determinate bar and both lines), finished (the bar disappears when the queue is empty), failed/cancelled (failed bytes leave the total; the Transfers row keeps the error and Retry).
- **Accessibility bar:** WCAG 2.2 AA contrast in light and dark; the bar is one focusable element with a label, a value, a button trait, a "Show Transfers" hint, and an activation action; the stop button keeps its "Stop all copies" label.

## 7. Scope

**In scope:** the bottom copy bar's headline, bar, two byte lines, accessibility label and value; the `AppModel` overall progress math and queue-cycle tracking; the toolbar ring's use of the same overall fraction; unit tests for the aggregate math and the queue cycle.
**Out of scope:** per-row progress in the Transfers window; the Dock badge; session history; time-remaining estimates; 25% VoiceOver announcements; any change to copy speed or MTP behavior.
**Dependencies:** SwiftUI on macOS 14 or later; the existing `ByteCountFormatter` file-style output; `swift test` with the existing libmtp Homebrew dependency.
**Constraints:** no new third-party packages; no new persisted state; the change must keep the copy queue serial and must not alter transfer order.

## 8. Risks and open questions

| ID | Risk or question | Mitigation |
|---|---|---|
| R-001 | The queue-cycle batch set is not cleared when the queue empties, so a later copy inherits earlier finished bytes. | Clear the set at the end of `startQueue` and cover the two-file transition with a unit test. |
| R-002 | A folder's children are added after the folder item is queued, so the denominator grows mid-copy. | Exclude folder items from the count and add child files before their transfer starts; the bar changes once when the folder is listed, not during a file's bytes. |
| R-003 | "Clear Finished" during an active copy removes bytes from the total and makes the bar jump. | Keep finished items that belong to the current queue cycle; remove only older finished rows. |

## 9. Instrumentation

The app ships no telemetry (the parent PRD's DL-008). The KPI is read from `swift test --filter ProgressTests` and from the QA report's 10 manual two-file runs; no event leaves the Mac. The event table is intentionally empty.

## 10. Rollout and rollback

- **Rollout:** ships in the next patch release after v0.1.0, with no feature flag; the change is local UI math and a test target.
- **Rollback trigger:** if three consecutive manual two-file runs show the total line smaller than the current file's total, or the bar moves backward while both files are unfinished, revert the commit and restore the previous single-line bar.
- **Migration:** none; no stored data or schema changes.

## 11. Compliance gates

None apply: the change collects no personal data, adds no accounts, payments, ads, or third-party services, and does not change the app's MIT license or its existing WCAG 2.2 AA target.

## 12. Data and integrations

- **Stored data:** none. The progress totals live in `AppModel` memory and are discarded when the app quits; no queue or history is persisted.
- **Integrations:** none. The change reads only in-process transfer state and does not call the phone, the network, or any external service. Local tests use the existing `DemoDevice`; the app-level tests use temporary files and no device.

## 13. Non-functional requirements

- The bar, both text lines, and the toolbar ring must use the same overall fraction on every render; they may differ by at most 1 percentage point due to rounding.
- A state change (file done, file failed, new file queued) must update the visible fraction within one display frame (16 ms at 60 Hz) after the main-actor state change.
- The two-file regression test must fail on the old math and pass on the new math; `swift test` must finish with 0 failures.
- The change must add no new runtime dependency and no more than 5 MB to the app bundle; it adds only Swift source and one test target.
- The bar must remain usable at the window's 760-point minimum width, with both caption lines visible and the stop button reachable.

## 14. Assumptions

| ID | Dimension | Assumption | Why this default | Overturn if |
|---|---|---|---|---|
| A-001 | interface | When the queue has exactly one file, the bar shows one byte line and hides the duplicate "this file" line. | The two lines would be identical; one line is easier to scan. | The user wants the "this file" label even for a single file. |
| A-002 | states | Failed, skipped, and cancelled files are excluded from the overall done and total but still count in "N of M". | Their bytes will not move, so including them would leave the bar stuck below 100%. | The user wants attempted bytes included in the total. |
| A-003 | states | Folder items are excluded from the item count and total; their child files are counted once listed. | A folder's own size is 0; the children carry the bytes that move. | The phone reports a folder size that should be counted. |
| A-004 | states | The overall total resets when the queue becomes empty; a later copy starts a new total. | Mixing unrelated copy sessions would make the bar start above 0%. | The user wants a session-wide total. |
| A-005 | interface | The toolbar ring uses the same overall fraction as the bottom bar. | Two progress surfaces that disagree would repeat the original defect. | The ring is meant to show only the current file. |

## 15. Decision log

| ID | Dimension | Question | Options offered | Answer | Applied in |
|---|---|---|---|---|---|
| DL-001 | permissions | Does this feature need a permission model? | A. No permissions; local single-user app (recommended) B. macOS file-access prompts C. Account roles | A | §5, §7 |
| DL-002 | data | Should progress survive an app relaunch? | A. No, in-memory only (recommended) B. Persist the queue C. Write a progress log | A | §12 |
| DL-003 | integrations | Does this feature call an external service? | A. None (recommended) B. Telemetry C. Crash reporting | A | §12 |
| DL-004 | interface | What should the copy bar show for bytes? | A. Both the current file and the overall total (chosen) B. Current file only C. Overall total only | A | §5, §6 |
| DL-005 | states | Which transfers belong in the overall total? | A. All active queue work, with finished bytes kept until the queue is empty (chosen) B. One copy batch only C. The whole session | A | §5, §6 |
| DL-006 | interface | How should the two byte views be arranged? | A. One overall bar with two text lines (chosen) B. Two bars C. One bar with one combined line | A | §6 |

## Coverage

| Dimension | Status | Ref |
|---|---|---|
| purpose | specified | §1, §3 |
| actors | specified | §2 |
| permissions | out-of-scope | DL-001 |
| triggers | specified | §5 |
| inputs | specified | §5 |
| outputs | specified | §5 |
| states | specified | §5, §6, A-002, A-003, A-004 |
| errors | specified | §5 |
| interface | specified | §6, A-001, A-005 |
| data | out-of-scope | DL-002 |
| integrations | out-of-scope | DL-003 |
| non_functional | specified | §13 |
| constraints | specified | §7, §11 |
| non_goals | specified | §4, §7 |
| acceptance | specified | §5 |
| rollout | specified | §9, §10 |
