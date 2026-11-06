---
spec: spec-clarifier/v1
feature: footage-triage
title: Footage triage: video filter, copied marks, orientation
status: complete
prompt: inline
prompt_sha256: 0b2d2e693490bad1d65c1ac2fd9f683ce3949d559813a3799adb310647f5a6b9
created: 2026-11-06
---

# PRD: Footage triage: video filter, copied marks, orientation

## 0. Source prompt

> Allow me to filter out video only files, label/mark the ones that I've already copied, allow me to see vertical vs horizontal, use @ui-ux-cx-engineer @frontend-design to get this done @spec-clarifier

## 1. Problem

Droplane lists every object on the phone in one Finder-style table. A person who has just shot a mix of clips and stills has to read filenames one by one, remember which footage already went to the Mac, and open a clip before finding out whether it was shot vertically. There is no filter, no copied signal, and no orientation signal in the list. On a PrimeCam folder with dozens of clips this turns a two-minute triage into a scroll-and-guess pass, and it makes a second copy of the same clip likely. The follow-up ask narrows the useful filter further: show only horizontal videos, or only vertical videos, hide every other file, and copy exactly what is shown. The parent PRD explicitly left photo-library import and PrimeCam-specific previews out of scope; this change adds list-level triage signals only and does not import, proxy, or transcode anything.

## 2. Target user

- **Primary:** a creator on a Mac who shot video or photos on an Android phone and is deciding what to copy before an edit.
- **Secondary:** any Droplane user browsing a large Camera or Pictures folder who wants to see media types and orientation without opening files.
- **Explicitly not for:** users who want library import, sync, ratings, keywords, or a persistent archive of what was copied; those needs stay outside this release.
- **Job-to-be-done:** When I am looking at a phone folder full of clips and stills, I want to show only the horizontal or only the vertical videos, see which files already reached my Mac, and copy the visible ones, so I can finish triage without opening or re-copying anything.

## 3. Outcome and success metric

- **Outcome this moves:** triage confidence: fewer repeat copies, no accidental copy of the wrong orientation, and fewer surprises about clip orientation after the copy.
- **Primary KPI:** a manual QA rubric over 10 phone folders and at least 100 files on the Demo Phone and one physical Android phone. Each folder is scored on four checks: every video is classified as a video and every photo as a photo; Horizontal videos and Vertical videos show exactly the matching files plus subfolders and hide every other file; every successfully copied file shows a check and no failed or skipped file does; every file with phone-provided dimensions shows the correct Vertical, Horizontal, or Square label.
- **Baseline:** 0 of 4 checks exist in the shipped app on 2026-11-06; the list has no filter, no copied mark, and no orientation.
- **Target:** 10 of 10 folders pass all four checks by 2026-11-13, recorded in the QA notes for this change.
- **Guardrail metrics:** first paint of a phone folder stays unchanged because orientation loads after the list is visible; copy throughput on the same file stays within 5 percent of the pre-change build; no network connection, telemetry event, or new permission is added.

## 4. Goals and non-goals

**Goals**
1. Filter the phone list from one Show menu with five modes: All, Videos, Photos, Horizontal videos, and Vertical videos.
2. In Horizontal videos or Vertical videos, hide every file that does not match and keep only subfolders plus matching videos.
3. Copy exactly the rows shown with a Copy All Shown button that never enqueues a hidden file.
4. Mark a phone file in the list after Droplane successfully copies it to the Mac during the current app session.
5. Show Vertical, Horizontal, or Square for photos and videos using dimensions read from the phone, without delaying the unfiltered file list.
6. Keep the Mac pane, copy queue, conflict handling, and existing keyboard behavior unchanged.
7. Keep all signals readable in light and dark appearance and with VoiceOver.

**Non-goals**
1. Persistent copy history across launches, a copied database, or checking whether the Mac copy still exists (DL-002).
2. Applying the filter, marks, or orientation to the Mac pane (DL-004).
3. Filename search, date or size filters, ratings, keywords, or a media library.
4. Video playback, generated thumbnails, proxies, transcoding, or PrimeCam sidecar parsing.
5. Detecting orientation by downloading a full file before the user copies it.
6. Marking a phone file as copied when the copy was skipped, cancelled, or failed.
7. Recursive scans that collect matching videos from subfolders into a flat list.
8. Any network request, analytics event, account, or new macOS permission.

## 5. User stories and acceptance criteria

- **[P0]** As a person triaging a phone folder, I want one Show menu with five modes, so that I can isolate the media I care about.
  - [ ] Given a phone folder with 3 horizontal videos, 2 vertical videos, 5 photos, 2 PDFs, and 2 subfolders, when I choose Videos, then the list shows the 5 videos and the 2 subfolders, hides the 5 photos and 2 PDFs, and the status strip reads "5 of 14 items".
  - [ ] Given the same folder, when I choose Photos, then the list shows the 5 photos and the 2 subfolders and the status strip reads "5 of 14 items"; when I choose All, all 14 items show and the status strip reads "14 items".
  - [ ] Given the same folder, when I choose Horizontal videos, then the list shows the 3 horizontal videos and the 2 subfolders, hides the 2 vertical videos, 5 photos, and 2 PDFs, and the status strip reads "3 of 14 items".
  - [ ] Given the same folder, when I choose Vertical videos, then the list shows the 2 vertical videos and the 2 subfolders and the status strip reads "2 of 14 items".
  - [ ] Given any filter mode, when I switch modes, then the current selection is cleared so a hidden file cannot be copied by accident.
  - [ ] Given a folder with subfolders and no matching media, then the subfolders still show; when the folder has no subfolders and no matching media, then an empty state reads "No videos in this folder", "No photos in this folder", "No horizontal videos in this folder", or "No vertical videos in this folder" and a "Show All" button returns the menu to All.
  - [ ] Given the Mac pane is open, then the Show menu is hidden and the Mac list is unchanged.
- **[P0]** As a person filtering by orientation, I want every video checked and revealed when its orientation is known, so that a matching clip is never silently missing.
  - [ ] Given Horizontal videos is chosen in a folder of 20 videos, then the list appears immediately with subfolders, the strip reads "Checking orientation 0 of 20", and matching videos appear as each check completes; the progress count reaches 20 of 20.
  - [ ] Given a file whose orientation was already checked in this session, when I switch to Horizontal videos, then it appears without another phone request.
  - [ ] Given a phone that cannot report dimensions for 3 videos, then those files are hidden, the strip reads "3 videos could not be checked" with a "Show All" button, and no file is counted as matching.
  - [ ] Given the phone disconnects while checks run, then checking stops, no orientation alert is raised, and the existing phone-disconnected flow takes over.
- **[P0]** As a person filtering by orientation, I want to copy only the rows shown, so that hidden videos and photos never enter the queue.
  - [ ] Given Horizontal videos shows 3 videos and 2 subfolders, when I press Copy All Shown, then the queue receives exactly 3 files and no folder, photo, PDF, or hidden video.
  - [ ] Given Horizontal videos is checking orientation and 2 matches are visible so far, then Copy All Shown says "Copy 2 Shown" and enqueues those 2 files only.
  - [ ] Given no matching file is visible, then Copy All Shown is disabled and its help text reads "No shown videos to copy".
  - [ ] Given the usual copy destination has a name conflict, then the existing conflict sheet appears for each file and the existing Skip, Replace, and Keep Both rules apply unchanged.
- **[P0]** As a person copying footage, I want a check beside files that already reached my Mac in this session, so that I do not copy them twice.
  - [ ] Given a phone file copy finishes with Done, when the list refreshes, then its Copied cell shows a green check with the accessibility label "Copied" within one second.
  - [ ] Given a copy is skipped, cancelled, or failed, then its Copied cell stays empty.
  - [ ] Given a folder copy, then each child file that finishes gets a check and the folder row stays unmarked.
  - [ ] Given a file was marked and I copy it again, then the check stays present and no duplicate mark appears.
  - [ ] Given I quit and relaunch Droplane, then every Copied cell is empty because the marks are session-only.
  - [ ] Given I click the Copied column header, then marked files sort before unmarked files, and a second click reverses the order.
- **[P0]** As a person deciding which clip to copy, I want to see whether a photo or video is vertical or horizontal, so that I can pick the right take without opening it.
  - [ ] Given a 1080 by 1920 video, when its orientation resolves, then the Orientation cell reads "Vertical" with a portrait rectangle icon and the accessibility label "Vertical, 1080 by 1920".
  - [ ] Given a video encoded as 3840 by 2160 with a 90-degree MP4 `tkhd` rotation matrix, then the cell reads "Vertical", because the encoded frame size is not the display orientation.
  - [ ] Given a 3840 by 2160 photo or video, then the cell reads "Horizontal" with a landscape rectangle icon.
  - [ ] Given a 1000 by 1000 file, then the cell reads "Square" with a square icon.
  - [ ] Given a phone that returns no sample or thumbnail for a file, then the cell reads an em dash and its help text reads "Orientation not available from this phone"; the app does not retry that file in the same session.
  - [ ] Given All, Videos, or Photos is active, then the file rows appear before any orientation value resolves, and scrolling stays interactive while values fill in.
- **[P1]** As a keyboard or VoiceOver user, I want the new controls to be reachable and named, so that the feature is usable without a mouse.
  - [ ] Given the phone pane is focused, when I reach the toolbar with the keyboard, then the Show menu is focusable and announces "Show, All" and each of the five modes.
  - [ ] Given VoiceOver reads a row, then it announces the name and, when present, "Copied", "Vertical", "Horizontal", or "Square".
- **[P1]** As a person scanning a folder, I want the list to stay stable while orientation loads, so that rows do not jump under the pointer.
  - [ ] Given orientation values arrive in All, Videos, or Photos, then only the affected cells redraw; row order and scroll position do not change unless I applied a sort.
  - [ ] Given orientation checks run in Horizontal videos or Vertical videos, then rows are inserted only for files that match and only after their check completes, with at most one list update every 150 milliseconds.

Priorities: **P0** release fails without it · **P1** ship-blocking unless waived · **P2** follow-up.

## 6. Experience notes

- **Surface:** the main browser window's phone pane only. The Mac pane keeps its current columns and behavior (DL-004).
- **Show control:** a toolbar pop-up button labelled "Show" with five items: All, Videos, Photos, Horizontal videos, Vertical videos. The toolbar uses compact labels (All, Videos, Photos, Horizontal, Vertical) so the control fits beside the copy buttons; the View menu uses the full names. Default All. The same five modes appear in the View menu with keyboard shortcuts Command-1 through Command-5. The control is hidden when the Mac pane is active. The chosen mode stays active while navigating between phone folders in that window and resets to All when the app launches (A-003, A-014, A-016).
- **Filtering rule:** All shows every item. Videos shows folders and video files. Photos shows folders and photo files. Horizontal videos and Vertical videos show folders plus only the videos whose width is greater than height, or height greater than width, respectively. Every other file is hidden, including square videos, photos, documents, and unknown orientations (DL-008, DL-011).
- **Orientation checking:** choosing Horizontal videos or Vertical videos starts a background check of every video in the current folder, one phone request at a time, using the session cache first. For videos, Droplane reads the MP4 `moov`/`tkhd` rotation matrix from a 256 KB head or tail fetch through `LIBMTP_GetPartialObject` and applies it before falling back to the thumbnail; Android often stores a portrait clip as a landscape frame plus a 90-degree matrix. A slim strip above the path bar shows a small spinner and "Checking orientation 12 of 40" while checks run. Matching rows appear as their checks complete, with list updates batched at most every 150 milliseconds. When checks finish with failures, the strip reads "3 videos could not be checked" with a Show All button. The strip is hidden in All, Videos, and Photos, and when checking finishes without failures.
- **Copy All Shown:** in Horizontal videos and Vertical videos, a toolbar button labelled "Copy 3 Shown" sits next to the main copy control. It enqueues exactly the visible video rows, never folders or hidden rows, and uses the same destination and conflict rules as the main copy command. It is disabled when no video row is visible (A-013).
- **Columns:** two new list columns to the right of Kind. Copied is 44 points wide and shows a green `checkmark.circle.fill` or nothing. Orientation is 100 points wide and shows an SF Symbol plus text: `rectangle.portrait` with "Vertical", `rectangle.landscape` with "Horizontal", or `square` with "Square". Unknown values show an em dash in secondary color. Both columns are hidden on the Mac pane. The existing Name, Date Modified, Size, and Kind columns keep their order and widths.
- **Loading:** in All, Videos, and Photos the folder lists immediately as today; orientation cells start as an em dash and are replaced in place, with no full-list spinner and no modal. Copied marks read from memory, so they appear on the same refresh as a finished download.
- **Empty and filtered states:** a filter that matches no media still shows subfolders. When nothing at all remains, the pane shows the media-specific empty state from section 5 with a Show All button.
- **Visual system:** native macOS 14 controls, SF Symbols, system label colors, a green check that meets WCAG 2.2 AA against both light and dark row backgrounds, and secondary text for orientation. No custom-drawn chrome.
- **Accessibility bar:** WCAG 2.2 AA contrast; the Show menu has the label "Show"; every meaningful icon has an accessibility label; empty-state actions are keyboard reachable; rows announce the new signals only when they carry information; the checking strip announces its progress at start and completion.

## 7. Scope

**In scope:** media classification by uniform type; the five-mode Show menu in the toolbar and View menu; phone-only Copied and Orientation columns; the session-only copied set updated on successful downloads; orientation checks for all videos in Horizontal and Vertical modes; a Copy All Shown toolbar action; a phone media-dimension reader in MTPBridge using MP4 `tkhd` rotation matrices, libmtp representative samples, or thumbnails; a JPEG dimension parser; an MP4 rotation parser; deterministic dimensions and a mix of orientations in the Demo Phone; row-level background updates; unit tests for classification, orientation math, the copied set, and filter selection; README and CHANGELOG notes.
**Out of scope:** persistent copy history; checking the Mac destination; filter, marks, or orientation on the Mac pane; search; recursive scans; sorting that triggers a full orientation preload; thumbnails, playback, proxies, transcoding; PrimeCam sidecar parsing; network, telemetry, accounts, and new permissions.
**Dependencies:** libmtp and libusb already bundled; the libmtp calls `LIBMTP_GetPartialObject`, `LIBMTP_Get_Representative_Sample`, and `LIBMTP_Get_Thumbnail`; one physical Android phone for hardware verification; the Demo Phone for automated and visual checks.
**Constraints:** Swift 5.9, SwiftUI and AppKit, macOS 14 or later, MIT license, no new third-party packages, no sandbox entitlement change, no remote push before maintainer approval.

## 8. Risks and open questions

| ID | Risk or question | Type | Owner | Resolve by |
|---|---|---|---|---|
| R-001 | Some Android phones return neither a representative sample nor a thumbnail for video files, so those rows show an em dash. The fallback and the failure count are covered by acceptance criteria; verify on a Pixel and one Samsung device. | Risk | Maintainer | 2026-11-20 |
| R-002 | A folder with hundreds of videos means hundreds of USB sample requests in Horizontal or Vertical mode. Sequential checks and a session cache limit the work, but the first check of a 500-video folder will take a visible amount of time; verify that the app stays interactive and the progress strip keeps updating. | Risk | Maintainer | 2026-11-20 |
| R-003 | A file replaced on the phone with the same name, byte size, and modification time inside one session could inherit a copied mark. Test the copied key against a re-recorded file. | Risk | Maintainer | 2026-11-20 |
| R-004 | Rows appearing as orientation checks complete could disturb a selection or scroll position in Horizontal or Vertical mode. Batch updates every 150 milliseconds and keep inserted rows in the existing sort order; verify with a 200-video folder. | Risk | Maintainer | 2026-11-20 |

## 9. Instrumentation

| Event | Trigger | Properties | Purpose |
|---|---|---|---|
| none | The app emits no events and makes no network call for this feature | none | The KPI is read from the manual QA rubric in section 3 |

## 10. Rollout and rollback

- **Strategy:** ship to all users in the next signed release; no feature flag, because the feature is local, read-only, and defaults to the current All view.
- **Rollback trigger:** revert the commit if any of 20 manual checks shows a hidden file entering the copy queue, if a matching video stays hidden after checking finishes in 5 separate folder runs, if any of 20 manual copies marks a failed or skipped file, or if opening the 500-file Demo Phone folder shows a blank list for more than 2 seconds.
- **Migration or backfill:** none; all new state is in memory and is discarded on quit.

## 11. Compliance gates

- [x] None apply. The feature adds no account, payment, personal-data collection, network call, or third-party code, and the bundled LGPL notices are unchanged. MIT licensing and the existing privacy statement still hold.

## 12. Data and integrations

- **Stored:** no files and no defaults keys. `AppModel` holds a session-only set of copied keys built from the phone file name, byte size, and modification time (A-004). Each browser window holds a session-only orientation cache keyed by the same tuple plus the folder path. Both are cleared when the app or window closes. No filenames are written to disk.
- **Migration:** none, because nothing is persisted and no schema exists.
- **Integrations:** libmtp through the existing `MTPDevice` abstraction. `LibMTPDevice` reads the MP4 `moov`/`tkhd` rotation matrix from a 256 KB head or tail fetch with `LIBMTP_GetPartialObject` for videos, then tries `LIBMTP_Get_Representative_Sample` for width and height, then falls back to `LIBMTP_Get_Thumbnail` plus a JPEG SOF parser. No authentication and no external service. Tests replace the phone with `DemoDevice`, which returns deterministic dimensions, and with MP4 and JPEG fixtures for the parsers.

## 13. Non-functional requirements

- Switching any Show mode over 1,000 rows completes in at most 100 milliseconds on an Apple Silicon Mac, measured with a manual stopwatch over 10 runs.
- The first paint of a phone folder is not blocked by orientation: in All, Videos, and Photos the outline view receives its rows within 1 frame of the folder load and before sample request 1 starts, measured by logging timestamps in a debug build.
- Orientation requests run off the main thread, at most one in flight per file and at most one request per file per session; a cached value renders in at most 16 milliseconds.
- Choosing Horizontal videos or Vertical videos starts the first orientation check within 200 milliseconds and updates the checking progress strip at least every 500 milliseconds.
- Filtered row insertions are batched so the list redraws at most once per 150 milliseconds while checks run.
- A completed copy updates the Copied set and the visible row within 1 second of the queue reporting Done.
- The copied set and orientation cache use at most 2 megabytes for 10,000 files each, measured with a debug memory read.
- 0 new network calls and 0 telemetry events, verified with a network monitor and by reading the diff for URLSession, analytics, or update code.
- WCAG 2.2 AA contrast for the green check, the orientation text, the checking strip, and the Show menu in light and dark appearance, checked with a contrast analyzer.
- Existing copy throughput stays within 5 percent of the pre-change build on the same 1 GB file and phone, measured over 3 runs.
- Existing columns, sorting, drag and drop, copy, rename, delete, and conflict behavior remain unchanged in the regression tests and 10 manual checks.

## 14. Assumptions

| ID | Dimension | Assumption | Why this default | Overturn if |
|---|---|---|---|---|
| A-001 | inputs | A file counts as video when its extension resolves to a uniform type conforming to movie or video, and as photo when it conforms to image. Unknown extensions are neither. | Matches how macOS classifies media and avoids a hard-coded extension list. | A supported phone codec is classified as neither video nor photo. |
| A-002 | states | Subfolders remain visible in all five modes, including Horizontal videos and Vertical videos. | Navigation must stay possible while a filter is active. | The user wants folders hidden under an orientation filter. |
| A-003 | states | The filter mode is per window, survives folder navigation, and resets to All at launch. | Keeps the choice while triaging one shoot without persisting a mode the next session may not expect. | The user wants the mode remembered across launches or reset per folder. |
| A-004 | data | A copied key is the phone file name, byte size, and modification time, not the object id or folder path. | Object ids change on reconnect and the same clip should stay marked after navigating away. | Two different clips in different folders collide on all three fields. |
| A-005 | states | Only a successful download marks a file; a folder row is never marked. | The mark answers "did these bytes reach my Mac", which a skipped or failed copy does not. | The user wants queued items marked optimistically or folders marked when all children finish. |
| A-006 | interface | In All, Videos, and Photos, orientation loads lazily for visible rows and is cached for the window session; in Horizontal videos and Vertical videos, every video in the folder is checked so the filter is complete. | Keeps the normal list immediate while making the orientation filter correct. | The user wants a blocking preload in every mode, or no checking for hidden rows. |
| A-007 | interface | The Orientation column is not sortable; the Copied column is sortable. | Orientation values arrive progressively, so sorting them would produce an order that changes under the user. | The user wants sorting that triggers a full fetch and re-sorts as values arrive. |
| A-008 | interface | A folder with no matching media shows a mode-specific empty state with a Show All button. | The filtered list must explain why it is empty and offer one-click recovery. | The user prefers an empty table with no explanation. |
| A-009 | states | Equal width and height reads "Square" and does not match Horizontal videos or Vertical videos. | The label must be true for square crops and screen recordings, and an orientation filter must not guess. | The user wants square files grouped with one of the two orientations. |
| A-010 | integrations | The Demo Phone returns deterministic dimensions and a mix of horizontal, vertical, and square media so every filter state can be exercised without hardware. | The project's existing Demo Phone is the only repeatable UI test device. | A hardware-only verification becomes mandatory for release. |
| A-011 | interface | The status strip reports the filtered count and the total when a filter is active. | The user needs to know how much the filter is hiding. | The user wants the status strip to report only the unfiltered total. |
| A-012 | states | In Horizontal videos or Vertical videos, a video is hidden until its orientation check completes, then inserted if it matches; failures are counted and surfaced with Show All. | The user asked for only matching videos to be visible and for failures not to be silent. | The user prefers showing unchecked videos first and removing mismatches later. |
| A-013 | outputs | Copy All Shown is available only in Horizontal videos and Vertical videos, copies the currently visible video rows, and never includes folders or hidden rows. | Those are the modes where copying "only them" is the user's stated job. | The user wants the button in Videos or Photos too. |
| A-014 | interface | The five Show modes also appear in the View menu with Command-1 through Command-5. | Gives keyboard users a discoverable path and matches macOS menu conventions. | Those shortcuts conflict with an existing command or the menu becomes cluttered. |
| A-015 | interface | The orientation checking progress uses a slim strip above the path bar, hidden when there is nothing to report. | Progress belongs next to the list without taking a permanent row. | The user wants progress in the toolbar instead. |
| A-016 | interface | The toolbar Show picker uses compact labels (All, Videos, Photos, Horizontal, Vertical); the View menu uses the full mode names. | The full names overflow the default window width and push the primary copy button into an icon-only state. | The user wants the full names in the toolbar and accepts a wider window or a second row. |
| A-017 | integrations | Video orientation reads up to 256 KB from the file tail, then the head, with `LIBMTP_GetPartialObject` and parses the MP4 `tkhd` matrix; if that fails it falls back to the thumbnail. | A portrait clip can be encoded as a landscape frame with a rotation matrix, so the thumbnail may be the wrong orientation. The matrix is authoritative and the tail is small. | The phone does not support partial objects, or the video container is not MP4/QuickTime. |

## 15. Decision log

| ID | Dimension | Question | Options offered | Answer | Applied in |
|---|---|---|---|---|---|
| DL-001 | triggers | What did "filter out video only files" mean? | A. All / Videos / Photos control B. Hide videos behind a toggle C. A single Videos-only switch D. Only inside the PrimeCam folder | A (superseded by DL-008) | §4, §5, §6 |
| DL-002 | data | What should "already copied" mean and where should the memory live? | A. Persistent copy history B. Persistent history plus Mac file check C. Session-only marks D. Check destination folder contents | C | §5, §12 |
| DL-003 | integrations | How should Droplane learn whether a clip is vertical or horizontal when MTP listings carry no dimensions? | A. Read thumbnails from the phone B. Only after copy, read locally C. PrimeCam sidecar only D. Leave orientation out | A | §5, §12, §13 |
| DL-004 | interface | Should the three signals apply to the phone pane, the Mac pane, or both? | A. Phone pane only B. Both panes C. Mixed, marks everywhere | A | §2, §6 |
| DL-005 | interface | How should the copied mark and vertical or horizontal show up in the list? | A. Two new columns B. Badges inline with the name C. One combined Status column D. Inline check plus Orientation column | A | §5, §6 |
| DL-006 | interface | Where should the media filter control live? | A. Toolbar segmented control B. Bar above the file list C. View menu only D. Bottom path bar | A (superseded by DL-009) | §6 |
| DL-007 | outputs | Which files should show a Vertical or Horizontal label? | A. Photos and videos B. Videos only | A | §5, §6 |
| DL-008 | triggers | After the follow-up ask, what should the filter show? | A. Add a Horizontal-only toggle B. Replace with All / Horizontal videos C. Add a fourth segment D. One Show menu with five modes | D (supersedes DL-001) | §4, §5, §6 |
| DL-009 | interface | How should the five filter modes fit in the toolbar? | A. One Show menu with five modes B. Media control plus orientation control C. Segmented control plus orientation cycle button | A (supersedes DL-006) | §6 |
| DL-010 | states | When Horizontal or Vertical is selected, what happens to files whose orientation cannot be checked? | A. Reveal as checked and report failures B. Show all, then hide mismatches C. Wait for every check D. Hide unknown silently | A | §5, §6, A-012 |
| DL-011 | states | When Horizontal or Vertical is selected, should subfolders still show? | A. Keep only subfolders B. Hide folders as well C. Recursive flat list | A | §5, §6, A-002 |
| DL-012 | outputs | How should "copy only them" work? | A. Add Copy All Shown B. Rely on Select All and Copy C. Recursive copy button | A | §5, §6, A-013 |

## Coverage

| Dimension | Status | Ref |
|---|---|---|
| purpose | specified | §1, §3 |
| actors | specified | §2 |
| permissions | specified | §5, §6 |
| triggers | specified | §5, DL-008 |
| inputs | specified | §5, A-001 |
| outputs | specified | §5, §12, A-013 |
| states | specified | §5, §6, A-002, A-003, A-005, A-009, A-012 |
| errors | specified | §5 |
| interface | specified | §6, A-006, A-007, A-008, A-011, A-014, A-015, A-016 |
| data | specified | §12, A-004 |
| integrations | specified | §12, A-010, A-017 |
| non_functional | specified | §13 |
| constraints | specified | §7 |
| non_goals | specified | §4 |
| acceptance | specified | §5 |
| rollout | specified | §10 |
