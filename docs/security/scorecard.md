# OpenSSF Scorecard findings

The Code scanning tab shows OpenSSF Scorecard results, not Dependabot package alerts.
Last reviewed: 2026-11-06. Alerts: <https://github.com/ryabinski-labs/droplane/security/code-scanning>.

| Check | Status | Evidence and next step |
|---|---|---|
| Branch-Protection | Applied; alert stays partial until the Scorecard token is added | `main` requires a pull request, one approving review, code-owner review, approval of the latest push, stale review dismissal, up-to-date branches, and the `Quality checks`, `Repository compliance`, and `Workflow security (zizmor)` checks. Force pushes and deletions are blocked; linear history and conversation resolution are required. The sole maintainer can use the admin bypass because `enforce_admins` is false. Scorecard still reads some settings as disabled because the workflow has no admin-read token; add a fine-grained `SCORECARD_TOKEN` with Administration: read. The maximum tier also asks for two reviewers, which waits for a second maintainer. |
| Fuzzing | Added; closes after this PR merges | `Fuzz/JPEGDimensionsFuzz.swift` exports `LLVMFuzzerTestOneInput` and mutates filenames and JPEG/thumbnail bytes through `JPEGDimensions`, `MediaClassifier`, and `NameSanitizer`. `./scripts/fuzz.sh 60` runs it locally; the Fuzz workflow runs weekly and when TransferCore or Fuzz files change. Scorecard scans `main`, so the alert closes after the PR merges and the next Scorecard run completes. |
| Code-Review | Blocked on a second human | The organization has one member, and Scorecard does not count self-approval or bot approval. Invite a maintainer or reviewer, then require their approval on `main`. The branch is already configured to require code-owner review. |
| Maintained | Time-based; no code change | The repository was created 2026-10-30. Scorecard cannot pass this check until 2027-01-28, regardless of commit activity. Re-run Scorecard after that date. |
| CII-Best-Practices | Blocked on external registration | Register the project at <https://www.bestpractices.dev/> and add the resulting badge to the README. This needs a human login and answers to the badge questionnaire. |
