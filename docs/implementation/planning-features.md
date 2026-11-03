# Petals planning features — implementation and verification

## Current delivery status
The user explicitly requested committing and pushing the current implementation before the remaining interactive verification is finished. This is a source delivery, not a claim that all completion gates passed or an App Store release.

Build, local persistence/migration regressions, search render checks, export checks, and Development CloudKit transport between independent stores have passed. Full interactive user journeys remain unverified because the Mac was locked at the last check. A second Mac is unavailable; physical cross-device and production CloudKit behavior are not established. The checkpoints below preserve the evidence and earlier findings chronologically.

## Accepted scope
- PDF / PNG / print of current period and selected calendars. Decoration switch defaults on; theme/grid/events always retained. Notes excluded from exports in v1.
- Search current visible event titles in place. Preserve colors/layout/nonmatches. Theme-aware outlines; clear/Escape resets. No results list, filters, or automatic navigation.
- Replace Calendar Sets with named, year-independent planning boards. Board owns calendar selection, theme, yearly decoration, dated notes. Source events are never copied.
- Toolbar board picker, creation/settings; rename/duplicate/delete. Switching boards preserves year/view. Whiteboards remain separate.
- Right inspector Calendar / Notes tabs. Calendar choices save automatically per board.
- Single-date text notes: one marker per date; all years of current board in date-grouped sidebar. Preview, expand/edit/delete, sidebar body search. Bidirectional calendar/list navigation.
- No event drag editing.
- Sync all user-created planning data, selections, and image originals. Preserve legacy sets/documents and offline data.

## Completion gates (unchecked until evidenced)
- [ ] Schema migration preserves old documents/images/sets and is repeatable.
- [ ] Planning board create/rename/duplicate/delete; independent data; no source event duplication.
- [ ] Cross-device calendar resolution and user data synchronization, including images.
- [ ] Notes CRUD, large list, searches, navigation across years and view changes.
- [ ] In-place title highlighting in all themes/views; clear and Escape.
- [ ] PDF/PNG/print fidelity with and without decorations, no notes/UI overlays.
- [ ] App build and launch; end-to-end user journeys.
- [ ] Korean and English localization review and runtime layout checks.
- [ ] Data migration/persistence regressions and actual sync evidence.

## Baseline
2026-11-03: clean repository at c691d48; actual path /Users/jmlee/ones/Petals.
Legacy Calendar Sets live in UserDefaults. YearDocument has no board owner.
Canvas images use iCloud Drive with a local-directory fallback. Existing CloudKit initialization silently falls back to local mode.

## Progress checkpoint — 2026-11-03
- Added CloudKit-compatible PlanningBoard / CalendarNote models, board ownership on YearDocument, deterministic legacy migration, and isolated persistence checks.
- Replaced Calendar Set UI with board picker/settings and per-board calendar selection. Added duplicate/delete paths. EventKit selection references include source metadata for cross-device resolution; ambiguous fallback matches are not selected.
- Added in-place event-title search and contrasting outlines without rearranging event bars.
- Added Calendar / Notes inspector, text note CRUD/search, date markers, cross-year navigation. New strings have en/ko entries.
- Debug build passed after these changes; log /tmp/Petals-planning-build.log.
- Standalone persistence checks passed: legacy data reassignment, decoration/theme retention, idempotency, bilingual text/date storage, reopened SQLite store. This does NOT test old compiled schema migration or actual iCloud propagation.
- Runtime launch confirmed for an isolated ad-hoc copy /tmp/PetalsValidation.app (bundle com.onessa.Petals.validation), PETALS_SHOT=1. Screenshot /tmp/Petals-validation-ko.png confirms new picker/search and Korean year view. Existing installed app was not modified or terminated.
- UI automation via System Events currently reports accessibility not allowed (-25211). First capture by app name captured the installed old app; DO NOT use /tmp/Petals-planning-ko.png as new-build evidence. Capture by process ID instead.

## Remaining work / risks
- Export/print not yet implemented.
- Image original synchronization/recovery and explicit sync error reporting remain. Existing silent local fallback is not acceptable evidence of sync.
- End-to-end journeys, English/runtime theme/size checks, large note lists, export fidelity remain.
- True old-schema migration fixture and board duplicate/delete persistence tests remain.
- CloudKit duplicate logical IDs from independently migrating devices need reconciliation; default boards must not reappear after tombstones. Cross-device deletion/change behavior needs verification.
- Review initial Query loading, unresolved calendar selections, note indicator hit area/overflow overlap, note focus after filtering, runtime empty states.
- Add missing-event search indication for events hidden in overflow without expanding layout.
- Review screenshot mode preference isolation: @AppStorage currently uses bundle preferences (validation bundle is isolated).
- No commit/push/deployment performed.

## Progress checkpoint 2 — 2026-11-03
- Implemented CalendarExportView / CalendarExporter: current-period PDF/PNG/print, decoration switch, no notes/search overlays. Period/year heading added. Uses ImageRenderer vector PDF, 3x PNG; loads original images or reports a missing-original error. Print operation created but no paper print performed.
- Added externalStorage originalImageData to CanvasItem and VisionBoardItem, import/factory/snapshot paths, original-data display and export. ImageSyncMigration copies originals from iCloud Drive/local fallback into synced records on launch/foreground, without removing legacy files. Actual cross-device sync still unverified.
- Added SyncStatus event observer and Settings iCloud status; local-only fallback is now disclosed in Settings. This does not establish successful remote propagation.
- Tests/LegacyStoreSeed.swift + extended PlanningPersistenceChecks.swift passed using the actual old model sources compiled as PetalsMigrationFixture. Verified old SQLite schema migration, content/geometry/whiteboard preservation; board duplicate/edit isolation/delete; 200 KB external image persistence and reopen.
- Tests/CalendarExportChecks.swift passed 6 combinations (12/3/1 months x decoration on/off): 1-page PDF with year/event/decor text, 3600x2496 PNG, original image pixel comparison in sRGB, nonnil print operation. Actual files /tmp/Petals-export-checks; log /tmp/Petals-export-checks.log. Original pixel check using deviceRGB had a false failure due to color conversion; replaced with source/output sRGB comparison and passed.
- English isolated runtime /tmp/PetalsValidationEN.app with 300 notes and in-place Trip search launched. Screenshot /tmp/Petals-validation-en-notes.png showed marker/date overlap and unnecessary Sidebar label; fixed to corner marker and labelsHidden; these final visual fixes built but need fresh screenshots.
- Added PETALS_SHOT_NOTES / PETALS_SHOT_SEARCH fixture options, only in existing in-memory screenshot mode.
- Latest build and git diff --check passed.

## Approval limitation and next work
- An automatic approval review REJECTED a proposed automatic duplicate-record deletion/reparenting reconciliation as potentially losing user data. That command was never applied and PlanningSyncReconciliation.swift DOES NOT EXIST. Do not resubmit or indirectly execute that code. Safer alternative: retain original records and reconcile their presentation/logical ownership without automatic physical deletion; still to implement/test.
- Pending asynchronous user questions: allow Codex accessibility for UI journey automation; availability of a second Mac on same Apple account for real sync verification. No reply yet.
- Still required: non-destructive duplicate/import handling and remote refresh, missing-calendar UX, full CRUD/navigation/print-save panel journeys, Korean/English and small-window/theme screenshots after fixes, overflow search behavior, actual iCloud sync (including images/deletions) and remaining localization audit.
- Running isolated demo processes at last check: /tmp/PetalsValidation.app PID 70222; /tmp/PetalsValidationEN.app PID 70885; earlier same-bundle temporary build PID 70193 may remain. Recheck process identity before stopping only our test apps. Installed /Applications/Petals.app must be left untouched.

## Progress checkpoint 3 — 2026-11-03
- Implemented the safer alternative to rejected automatic deletion: PlanningBoardProjection is read-only. It groups logical board IDs, selects latest settings via updatedAt, honors any deletion tombstone, and aggregates decorations from all matching yearly documents. Original records and relationships remain intact. Canvas display/edit/export now consume all projected documents; explicit user item deletion targets its actual owner.
- Added stable per-record recordID and settings timestamp; selected-calendar/name/theme edits update settings timestamps.
- Persistence checks extended and passed: both duplicate source records and their decorations survive projection, newest settings are shown, tombstone hides logical board without automatic deletion. Fresh old-schema fixture v3 also passed after new fields (log /tmp/Petals-persistence-v3.log).
- @Query now tracks year documents for incoming changes; changing view preserves selected-note month/current year instead of jumping to today.
- Missing calendars retain selection and show concise translated explanation in Calendar sidebar.
- Note Add defaults to selected note date / currently displayed period. Whiteboard mode hides calendar inspector.
- Root error wording and OK translation corrected. Catalogue review: existing source-language fallback entries need not have explicit en units; OK was genuinely missing and added.
- Long SwiftUI modifier expression hit compiler limit; split presentation/lifecycle/observation boundaries and extracted zoom calculation; latest build passes.
- Latest Korean 300-note screenshot /tmp/Petals-validation-ko2.png confirms non-overlapping corner markers, no redundant sidebar label, and initial scroll toward latest available note date. /tmp/PetalsValidationKO2.app PID 71458 at capture; revalidate before any process action.
- Both outstanding user questions (accessibility and second Mac) still unanswered. No end-to-end clicking or real two-device sync claimed.

## Remaining completion evidence
1. Interactive user journeys: board create/calendar choose/theme/rename/duplicate/delete; note create/edit/delete/search/click navigation; Escape and clear search; save panel PDF/PNG and print preview; mode/view switching. Accessibility remains unavailable.
2. Theme and narrow-window render coverage, updated English screenshot, search behavior for hidden/overflow events.
3. Actual CloudKit transfer and second-device arrival/edits/deletions for boards, calendar references, notes, yearly decorations, and originals. Current local SQLite tests and screenshot mode cannot prove this.
4. Verify schema provisioning/release compatibility before any deployment. Nothing was committed, pushed, or deployed.

## Progress checkpoint 4 — 2026-11-03
- Revalidated current worktree and build logs. Debug build succeeds. Added title-match day counts for lane-hidden events; overflow badges distinguish hidden matches while retaining event colors and search-independent placement.
- Actual English runtime with 300 notes and tokyo-night theme exposed yearly overflow counts overlapping date labels and low contrast. Moved annual counts into a reserved footer, with theme-derived foreground. Very short annual cells can display only the overflow count rather than overlapping bars and labels.
- Rebuilt and reran SearchThemeChecks: all 18 theme/scheme combinations pass; includes matching-day and exclusive-end-date checks. CalendarExportChecks still passes all 6 year/quarter/month decoration combinations. These are rendered/local checks, not interactive journey or remote sync evidence.
- Fresh actual app screenshot /tmp/Petals-validation-overflow-fixed.png (isolated process 72158 at capture) confirms separated dates/counts and visible hidden-search matches. English note list remains readable with 300 notes.
- All 43 newly added catalog keys have nonempty translated English and Korean units. git diff --check passes.
- Requested 1100pt screenshot window is constrained by native toolbar minimum width to about 1520pt. Narrow-window responsiveness is NOT verified and needs follow-up; do not describe this capture as an 1100pt pass. App chrome remains light while the calendar uses tokyo-night; this does not prove OS-dark runtime coverage.
- Rechecked automation: System Events returns accessibility denied (-25211). Renewed concise questions about enabling Codex accessibility and a second Mac on the same Apple account. No reply at this checkpoint.
- Outstanding gates remain: interactive CRUD/navigation/save/print journeys, narrow-window layout, OS-dark runtime, and actual signed CloudKit/two-device propagation including image originals and deletions. No commit/push/deployment.

## Progress checkpoint 5 — 2026-11-03
- Fixed actual narrow-window sizing in ScreenshotWindowSizer: run when its NSView attaches to a window. Previously early sizing could silently do nothing; prior 1520pt captures were not evidence of a toolbar minimum alone.
- Calendar content minimum width is 580pt with a 900pt minimum applied around the complete inspector layout. Native toolbar controls are individually grouped; compact windows use a menu for year/quarter/month; search is a separate toolbar item.
- Actual smaller captures exposed crowded annual day/weekday labels and all event lanes disappearing with a footer. Annual labels omit weekday text when it does not fit; adaptive top inset preserves one event lane and overflow footer at the default font in short windows. Export shares the same inset calculation.
- Debug build and 6 export checks pass after these layout fixes. /tmp/Petals-validation-journey-ko.png shows the latest Korean 1100pt window with 300 notes, visible search, readable date numbers, event lane and overflow counts. /tmp/Petals-validation-narrow3.png is an earlier English narrow capture before the compact view-picker change; not the final English toolbar evidence.
- User enabled Codex accessibility but current tool host is actually /Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex, parent ChatGPT. System Events still returned -25211. At user request opened x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility for ChatGPT permission. Pending recheck after user changes it.
- User corrected second-device availability: second Mac is NOT available. Do not ask as though it is available. Physical two-device checks remain unverified.
- Signed Debug build succeeded in /tmp/Petals-signed-validation with existing Development certificate/profile; app not launched against the normal store.
- Separate signed read-only account probe explicitly entitled Development reported CloudKit account available=true.
- Added Tests/CloudSyncChecks.swift, separately compiled/signed test bundle /tmp/PetalsCloudSyncProbe.app (explicit Development entitlement). Stores are under Application Support/PetalsSyncChecks/<UUID>/writer.store and reader.store, independent of the app's normal store. No production record changes.
- Run ID fe4de5dd-5857-4784-904f-6336b760dfad, recorded in /tmp/Petals-cloud-sync-run-id. Seed writer exported, separate reader successfully imported and matched board theme, calendar reference, bilingual date note, geometry/rotation and exact 256KiB originalImageData payload. Logs /tmp/Petals-cloud-sync-writer.log and /tmp/Petals-cloud-sync-reader.log; reader ends PASS. This proves development CloudKit transport between independent stores on one Mac, not physical multi-device/production behavior.
- Reverse update test running (/tmp/Petals-cloud-sync-update.log); read-back, delete propagation and fixture cleanup still pending. Test only targets its generated sync-check UUID.

## CloudKit transport result — 2026-11-03
- The same isolated Development run also passed reverse update (reader writes, writer imports) and delete propagation (writer tombstones only its fixture board and removes its notes/year document, reader observes tombstone plus absence of notes/documents). Logs: /tmp/Petals-cloud-sync-read-update.log and /tmp/Petals-cloud-sync-read-delete.log both end PASS.
- The seed and update observer processes were intentionally terminated only after the corresponding reader assertion passed; their shell exit 143 is observation cleanup, not a failed sync assertion. The final delete observer is likewise stopped after reader PASS.
- Fixture content has been removed through the tested deletion; its logical-board tombstone remains intentionally, matching app behavior. No production records or normal app store were touched.
- Limitations: one physical Mac, development CloudKit environment; this does not establish production schema deployment, push timing on another Mac, or account/calendar matching on another device. The 256KiB image-field fixture tests byte transport; rendering valid originals is covered separately by export tests.
- Narrow annual labels now consistently omit weekday letters for the whole grid when insufficient space, rather than showing them only on single-digit dates. Latest Debug build passes; latest actual capture predates this consistency-only adjustment.
- Remaining primary blocker is interactive user-journey verification. User requested the Accessibility Settings page; it was opened. Awaiting ChatGPT permission application. Second Mac is unavailable per user's correction.

## Final local checks / current UI gate — 2026-11-03
- User explicitly requested committing and pushing ALL changes when implementation/verification finishes. Current branch main; origin https://github.com/jake-simple/Petals.git. Not yet committed or pushed.
- Added scripts/test-planning.sh to reproduce old compiled schema migration, board/note/image persistence and duplicate projection, 18 search theme combinations, and 6 export combinations. Full run passed (/tmp/Petals-final-planning-checks.log). Initial script omitted CalendarSet.swift; fixed the script and full run passed.
- scripts/test-regressions.sh passes 514 assertions each in Asia/Seoul, America/Los_Angeles, UTC (/tmp/Petals-final-regressions.log).
- CloudSyncChecks now checks its actual code-signing entitlements before touching CloudKit; it refuses access unless explicitly signed Development. Unsigned check correctly exits 1; signed check-environment passes without accessing records.
- Direct AXIsProcessTrustedWithOptions reports true: accessibility permission is granted. System Events still returns -25211. Direct AX tree exposes menus but window children are malformed while locked. Crucial evidence: NSRunningApplication.activate returns false and NSWorkspace.frontmostApplication is loginwindow. UI input helper deliberately refuses to post events unless the intended test app is frontmost. No actual board/note click journey was performed.
- Asked user to unlock the Mac; response pending. Do not request accessibility permission again as though it is missing. Do not try to unlock the OS or bypass the frontmost-target guard.
- Temporary direct AX helper: /tmp/PetalsAX; guarded input helper: /tmp/PetalsInput; target fixture process 72664 at last check (revalidate before use). Current target /tmp/PetalsValidationJourney.app, screenshot mode/in-memory only, Korean; source has a later consistency-only weekday display change not in this binary. For final journeys launch the latest build in a new isolated bundle.
- /tmp/capture-petals-pid.swift now prints target window bounds as well as saving a 2x image. Last target bounds (730,391,1100,688); requery before coordinate actions.
