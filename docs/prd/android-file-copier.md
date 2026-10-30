---
spec: spec-clarifier/v1
feature: android-file-copier
title: Android to Mac File Copier
status: complete
prompt: inline
prompt_sha256: c569265de2ef7229dbf52e5a08a1e728c83fe78a129939163a088e135e16212a
created: 2026-10-30
---

# PRD: Android to Mac File Copier

## 0. Source prompt

> I want to build a file copier from android to mac, using mac native UIs, it will be open source use stdio to find any skills that would help, i want to have a signed app so people could easily install the app on their macs, and it will be linked from https://primecam.app/ to help copy the files /spec-clarifier show it to me running locally before we push it remotely

## 1. Problem

People who record video and photos with PrimeCam (https://primecam.app/) end up with large files on an Android phone and no good way to move them to a Mac. Apple ships no Android transfer tool, and Google's Android File Transfer is no longer maintained. The request is a free, open-source, native macOS app, modeled on OpenMTP (https://openmtp.ganeshrvel.com/): two panes (Mac and phone), drag-and-drop, a transfer queue, USB MTP only. It is linked from primecam.app so PrimeCam users can copy their files. Source: the prompt in section 0 plus DL-001 and DL-002.

## 2. Target user

- **Primary:** PrimeCam users on a Mac who copy recorded video and photos off an Android phone over USB.
- **Secondary:** any Android owner with a Mac who wants an open-source alternative to OpenMTP with a native look.
- **Explicitly not for:** Windows and Linux users, and users who want wireless transfer (non-goal 1).
- **Job-to-be-done:** When I finish shooting on my phone, I want to drag my clips to a Mac folder, so I can edit them without hunting for a tool.

## 3. Outcome and success metric

- **Outcome this moves:** PrimeCam users can get files off the phone without third-party help.
- **Primary KPI:** total downloads of the notarized DMG from GitHub Releases, read from the GitHub release assets API (A-001).
- **Baseline:** 0 on 2026-10-30 (not yet released).
- **Target:** 500 downloads within 90 days of the first public release (A-001).
- **Guardrail metrics:** open GitHub issues labeled crash stay below 5 at any time; no telemetry is added to measure either (DL-008).

## 4. Goals and non-goals

**Goals**
1. Browse the phone's internal storage and SD card in a native macOS window beside a Mac folder pane.
2. Copy files and folders Android to Mac and Mac to Android by drag-and-drop or Cmd+C / Cmd+V, with a visible queue and progress (DL-005).
3. Rename, delete, and create folders on the phone (DL-005).
4. Install with one drag of a Developer ID signed, notarized, stapled DMG and no Gatekeeper warning (DL-004).
5. Be shown running locally before anything is pushed to a remote (prompt).

**Non-goals**
1. Wireless transfer (Wi-Fi or a companion Android app): USB MTP only, as in OpenMTP (DL-001).
2. adb or any use of USB debugging: the app uses MTP only (DL-001).
3. Windows, Linux, iOS, and Mac App Store distribution (DL-004).
4. Syncing, backup schedules, photo library import, and PrimeCam-specific metadata or previews.
5. Multiple phones connected at the same time (A-004).
6. Any telemetry, accounts, or cloud service (DL-008).

## 5. User stories and acceptance criteria

- **[P0]** As a PrimeCam user, I want the phone to appear when I plug it in, so that I can browse it.
  - [ ] Given an unlocked Android phone in File transfer mode, when I connect it by USB, then within 5 seconds the phone pane lists its storages and its top-level folders.
  - [ ] Error: given the phone is locked or in charge-only mode, then the app shows "Unlock your phone and choose File transfer (MTP) in the USB notification" and a Refresh button, and lists nothing.
  - [ ] Error: given another app holds the USB interface, then the app shows "Another app is using your phone. Quit Android File Transfer, Samsung Smart Switch, or any other phone manager, then press Refresh".
- **[P0]** As a user, I want to copy files and folders from the phone to a Mac folder, so that I can edit them.
  - [ ] Given a phone file selected and a Mac folder open, when I drag it to the Mac pane or press Cmd+C then Cmd+V, then the file appears in the queue with percent and MB/s, and a byte-identical copy (matching SHA-256) exists in the Mac folder when the queue item reads Done.
  - [ ] Given a file larger than 4 GB, when I copy it, then it completes with a matching SHA-256.
  - [ ] Given a folder is selected, when I copy it, then its whole subtree is copied with the same names and structure.
  - [ ] Error: given the Mac volume has less free space than the queue needs, then the copy does not start and the app shows "Not enough space on the Mac: needs X GB, has Y GB".
- **[P0]** As a user, I want to decide what happens on a name clash, so that I never lose a clip.
  - [ ] Given the destination already has a file with the same name, when the copy reaches it, then a sheet offers Replace, Keep Both, and Skip with an Apply to All checkbox, and nothing is overwritten before I choose (DL-006).
  - [ ] Given I choose Keep Both, then the new file is named "name 2.ext" and the original is unchanged.
- **[P0]** As a user, I want a failed or cancelled copy to be clear, so that I trust the files I have.
  - [ ] Given a copy is running, when I click Cancel on its queue row, then the transfer stops within 2 seconds and the partial destination file is deleted.
  - [ ] Error: given the cable is unplugged mid-copy, then every unfinished queue item shows Failed with "Phone disconnected", partial destination files are deleted, and a Retry button re-queues them once the phone returns.
- **[P0]** As a user, I want to install the app by dragging it from a DMG, so that I do not fight Gatekeeper.
  - [ ] Given a clean Mac running macOS 14 or later with no developer tools, when I open the downloaded DMG and drag the app to Applications, then it launches with no security warning; `spctl --assess --type execute` reports accepted with source Notarized Developer ID, and `stapler validate` succeeds on the DMG.
  - [ ] Given the app is on Apple Silicon or Intel, then the same universal binary launches on both.
- **[P0]** As the maintainer, I want to see the app running locally before any push, so that I can approve it.
  - [ ] Given a built app on the maintainer's Mac, when launched with the Demo Device menu item enabled, then an in-memory fake phone with sample folders and files appears and all P0 stories above can be exercised without hardware (A-005).
  - [ ] Given no `git remote` is configured, then no command in the build or release scripts pushes anywhere; the first push happens only after the maintainer says so.
- **[P1]** As a user, I want to copy files from the Mac to the phone, so that I can put files on it.
  - [ ] Given a Mac file selected and a phone folder open, when I drag it to the phone pane, then it is copied with the same progress, conflict sheet, and cancel behavior, and its size on the phone equals its size on the Mac.
  - [ ] Error: given the phone storage is full, then the item shows Failed with "Not enough space on the phone".
- **[P1]** As a user, I want to rename, delete, and create folders on the phone, so that I can tidy it.
  - [ ] Given a phone item selected, when I press Return and type a new name, then the phone shows the new name after Refresh.
  - [ ] Given a phone item selected, when I press Cmd+Delete, then a confirmation says "Delete N items from your phone? This cannot be undone" with Delete and Cancel, and nothing is removed until I press Delete (A-003).
  - [ ] Given a phone folder open, when I press Cmd+Shift+N and type a name, then the folder exists on the phone.
- **[P1]** As a user, I want list and icon views, hidden-file toggle, and keyboard navigation, so that it feels like a Mac app.
  - [ ] Given either pane, when I switch between list and icon view, then the choice is remembered per pane after relaunch.
  - [ ] Given hidden files are off (default), then names starting with a dot are not listed in either pane.
- **[P1]** As a user, I want the app to update itself, so that I get fixes.
  - [ ] Given a newer signed version in the appcast, when I launch the app, then Sparkle offers the update and installs it after I accept (DL-007).

Priorities: **P0** release fails without it · **P1** ship-blocking unless waived · **P2** follow-up.

## 6. Experience notes

- **Surface:** one macOS app window (SwiftUI with AppKit where needed), macOS 14 or later (DL-007). Two panes: Mac on the left, phone on the right, each with a path bar, list and icon views, and a toolbar item that switches the phone between internal storage and SD card. A transfer queue panel sits at the bottom and can be collapsed. Standard menu bar, Settings window (Cmd+comma), and an About window with the license and a link to https://primecam.app/.
- **Native look:** system controls, SF Symbols, vibrancy sidebar and toolbar, Finder-style selection, and automatic light and dark appearance. No custom-drawn chrome.
- **Empty state, no phone:** illustration, "Connect your Android phone with a USB cable", and a three-step checklist (unlock, tap the USB notification, choose File transfer).
- **Loading state:** a spinner in the phone pane while a folder lists; the pane stays interactive.
- **Error states:** the messages in section 5, shown inline in the affected pane or queue row, never as a modal except destructive confirmation and the conflict sheet.
- **Shortcuts:** Cmd+C, Cmd+V, Cmd+Shift+C (copy to queue), Cmd+Delete, Cmd+Shift+N, Return (rename), Cmd+R (refresh), Cmd+Up (parent folder), Cmd+A, Tab (switch pane), arrow keys, matching OpenMTP.
- **Accessibility bar:** WCAG 2.2 AA contrast in light and dark, every control labeled for VoiceOver, every action reachable by keyboard, queue progress announced at 25 percent steps (A-006).

## 7. Scope

**In scope:** device detection, storage and folder browsing, copy both directions with queue, progress, cancel, retry, conflict handling, rename, delete, new folder, list and icon views, hidden-file toggle, Sparkle updates, Demo Device, signed notarized universal DMG, GitHub repository with MIT license, README, and a download link on primecam.app (the link change itself ships through the primecam.app repository after approval).
**Out of scope:** the non-goals in section 4.
**Dependencies:** libmtp and libusb bundled as dynamic libraries (DL-003); Sparkle; an Apple Developer ID Application certificate and notarization credentials (DL-010); a physical Android phone for hardware verification (DL-009).
**Constraints:** Swift, SwiftUI, and AppKit only for app code; macOS 14 or later; MIT license (DL-008); Developer ID outside the Mac App Store, hardened runtime, not sandboxed (DL-004, A-007); no remote push before approval (prompt); all changes reach main by pull request (global rule).

## 8. Risks and open questions

| ID | Risk or question | Type | Owner | Resolve by |
|---|---|---|---|---|
| R-001 | The Developer ID Application certificate and notarytool profile do not exist yet (keychain holds only Apple Distribution and Apple Development); until the maintainer creates them, builds are ad-hoc signed and release is blocked (DL-010). | Risk | Maintainer | 2026-11-13 |
| R-002 | MTP behavior differs by phone maker, so some models may list slowly or fail on large files. | Risk | Maintainer | 2026-12-15 |

## 9. Instrumentation

| Event | Trigger | Properties | Purpose |
|---|---|---|---|
| none | The app emits no events and makes no network call except the Sparkle update check | none | Success is read from GitHub release download counts (DL-008) |

## 10. Rollout and rollback

- **Strategy:** version 0.1.0 as a GitHub pre-release, then 1.0.0 after 14 days with no open crash issue; DMG and Sparkle appcast hosted on GitHub Releases (A-008).
- **Rollback trigger:** `spctl` rejects the published DMG, or 3 or more distinct crash issues are opened within 7 days of a release; the release is unpublished and the appcast points at the previous version.
- **Migration or backfill:** none; this is a new app.

## 11. Compliance gates

- [ ] Hardened runtime enabled, app and DMG notarized and stapled by Apple notarytool (DL-004).
- [ ] libmtp (LGPL-2.1) is linked dynamically; its license text and a source link ship in the app's Acknowledgements and the repository.
- [ ] Sparkle EdDSA key is stored outside the repository.
- [ ] No secrets, certificates, or personal paths are committed; run the open-source-release audit before the first push.

## 12. Data and integrations

- **Stored:** user preferences only (view mode per pane, hidden-file toggle, last Mac folder, window frame) in UserDefaults on the user's Mac. No file contents, file names, or device identifiers leave the Mac. Logs go to the unified logging system and exclude file names (A-009).
- **Migration:** none.
- **Integrations:** libmtp and libusb for the phone, accessed through a Swift wrapper that sits behind a protocol so tests substitute a fake device (DL-003). Sparkle for updates, authenticated by an EdDSA signature on the appcast. Apple notarytool for release. Tests never touch real USB hardware; hardware checks run manually per DL-009.

## 13. Non-functional requirements

- Cold launch to a visible window: at most 2 seconds on an M1 Mac, measured with Instruments (A-006).
- Listing a phone folder of 1,000 entries: at most 2 seconds from selection to rendered rows.
- UI stays responsive while copying: no main-thread stall longer than 100 ms, measured with Instruments during a 4 GB copy.
- Copy throughput is within 10 percent of OpenMTP copying the same file with the same phone and cable.
- DMG size at most 50 MB.
- Supported OS: macOS 14 or later, Apple Silicon and Intel (DL-007).
- Security: no network access other than the Sparkle check; updates and DMG are signed (section 11).

## 14. Assumptions

| ID | Dimension | Assumption | Why this default | Overturn if |
|---|---|---|---|---|
| A-001 | purpose | Success is 500 DMG downloads in 90 days, with no telemetry. | The user gave no metric; zero telemetry (DL-008) leaves download counts as the only free signal. | The maintainer wants a different number or an opt-in measure. |
| A-002 | actors | Any Android phone that exposes MTP is supported equally; PrimeCam is the audience, not a requirement. | The prompt says the app helps copy files and mirrors OpenMTP. | PrimeCam-specific features are wanted (see non-goal 4). |
| A-003 | permissions | There are no accounts or roles. Delete on the phone is permanent (MTP has no trash) and always needs a confirmation. The app never deletes files on the Mac. | MTP offers no trash; Finder handles Mac deletion. | The user wants Mac-side delete or a trash. |
| A-004 | triggers | Every action is started by the user. The app detects plug-in and unplug automatically and handles one phone at a time. | OpenMTP does the same. | Multi-device is requested. |
| A-005 | triggers | A Demo Device (in-memory fake phone) is selectable from the Device menu so the app can be shown without hardware. | The emulator lacks MTP (DL-009) and the user wants a local demo first. | A physical phone is on hand for every demo. |
| A-006 | interface | Accessibility, performance, and queue behavior are as written in sections 5, 6, and 13: queue runs one transfer at a time because an MTP session is serial; progress is announced every 25 percent. | MTP allows one operation per session; WCAG 2.2 AA is the repo-wide default bar. | A phone proves to support parallel streams. |
| A-007 | constraints | The app is not sandboxed and uses hardened runtime; USB access needs no sandbox entitlement. | App Store is a non-goal (DL-004) and sandboxed USB access complicates libmtp. | App Store distribution is added later. |
| A-008 | rollout | Hosting is GitHub Releases under the maintainer's GitHub account; the app is named "PrimeCam Transfer" with bundle ID app.primecam.transfer. | Keeps one brand with primecam.app; no hosting cost. | The maintainer prefers another name or owner. |
| A-009 | data | Preferences live in UserDefaults and are not synced; logs omit file names. | Zero telemetry (DL-008) and privacy of personal footage. | Diagnostic exports are wanted. |
| A-010 | errors | There is no automatic retry; failed items show a Retry button. A copy that fails is never partially kept. | Silent retries on a flaky cable hide problems and can duplicate data. | Users ask for automatic retry. |
| A-011 | inputs | There is no file size or count limit; file types are not filtered. Names that macOS forbids (a colon in a name) are replaced with an underscore on the Mac side and the change is shown in the queue row. | MTP and APFS differ in allowed characters. | Another sanitizing rule is preferred. |

## 15. Decision log

| ID | Dimension | Question | Options offered | Answer | Applied in |
|---|---|---|---|---|---|
| DL-001 | purpose | Which reading of the prompt? | A. Native app over adb. B. Native app over MTP, no adb. C. Android companion app plus Mac app, wireless. D. PrimeCam-only importer | B | §1, §4, §7 |
| DL-002 | interface | How should it look and behave (user message)? | A. Like OpenMTP in function with a native Mac UI. B. Finder-clone single pane. | A (user wrote: similar to OpenMTP but using beautiful mac native UI) | §1, §6 |
| DL-003 | integrations | Which MTP engine? | A. libmtp plus libusb bundled. B. OpenMTP Kalam helper. C. Swift MTP stack on IOKit | A | §7, §12 |
| DL-004 | constraints | How is the signed app distributed? | A. Developer ID notarized DMG. B. Mac App Store. C. Both, DMG first | A | §4, §5, §11 |
| DL-005 | non_goals | Which OpenMTP features are in v1? | A. Dual panes and browsing. B. Android to Mac copy with progress. C. Mac to Android copy. D. Rename, delete, new folder | A, B, C, D (all) | §4, §5 |
| DL-006 | states | What happens on a name clash? | A. Ask per conflict. B. Always keep both. C. Always skip | A | §5 |
| DL-007 | constraints | Minimum macOS and updates? | A. macOS 14 plus Sparkle. B. macOS 13 plus Sparkle. C. macOS 14, no updater | A | §6, §7, §13 |
| DL-008 | data | License and telemetry? | A. MIT, zero telemetry. B. GPL-3.0, zero telemetry. C. MIT with opt-in crash reports | A | §3, §9, §12 |
| DL-009 | acceptance | Is a physical Android phone available for testing? | A. Yes, user plugs one in. B. No, Demo Device only | A | §5, §7, §8 |
| DL-010 | constraints | Signing credentials? | A. User creates Developer ID cert; build unsigned first. B. Cert exists elsewhere. C. Use Apple Distribution cert | A | §7, §8, §11 |
| DL-011 | rollout | What is the app named and which bundle ID prefix, superseding the A-008 name? | A. Droplane. B. PhoneBridge. C. MTP Commander. D. Keep code name; and com.ryabinskilabs / app.primecam / io.github | Droplane, com.ryabinskilabs.droplane; not PrimeCam-branded, primecam.app links to it | §10 |
| DL-012 | interface | Which layout should the app use, superseding the two-pane layout from DL-002? | A. Finder-style window: sidebar with phone storages and Mac places, list view with Name/Date Modified/Size/Kind, phone items drag into Finder like any folder. B. Keep OpenMTP two panes | A; user approved the running build | §6 |

## Coverage

| Dimension | Status | Ref |
|---|---|---|
| purpose | specified | §1, §3, A-001 |
| actors | specified | §2, A-002 |
| permissions | assumed | A-003 |
| triggers | assumed | A-004, A-005 |
| inputs | assumed | A-011, §5 |
| outputs | specified | §5 |
| states | specified | §5, DL-006 |
| errors | specified | §5, A-010 |
| interface | specified | §6, A-006 |
| data | specified | §12, DL-008, A-009 |
| integrations | specified | §12, DL-003 |
| non_functional | specified | §13 |
| constraints | specified | §7, DL-004, DL-010, A-007 |
| non_goals | specified | §4, DL-005 |
| acceptance | specified | §5 |
| rollout | specified | §10, A-008, DL-011 |
