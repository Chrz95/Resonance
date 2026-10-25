# Batch recognition — Resonance 1.6.0

Batch recognition is already merged into this complete source package. Rebuild the app with the standard bootstrap/build instructions in README.md. Standalone Windows and Android engines, saved sessions, alternate sources and existing edits are preserved.

1. Import songs with the file picker, then check individual cards or **Select all**. **Recognize selected** uses checked songs; **Recognize all** processes the whole session in import order. Dropped Windows songs are imported first, then start a recognition queue automatically.
2. Each card shows **Not checked**, **Queued**, **Recognizing**, **Matches ready**, **No match**, **Failed**, **Canceled** or **Interrupted**. The panel shows progress, the current filename and outcome counts. Errors appear in the card tooltip and selected song's recognition panel.
3. **Pause queue** and **Cancel remaining** take effect after the current song finishes or fails. Resume continues in order. A queued card's skip icon cancels just that song, keeping its draft. These controls do not force-abort a decoder or HTTP request; the current call can take until its timeout.
4. **Retry failed** retries failures. **Retry unfinished** also includes canceled, skipped and interrupted songs. When any checkboxes are selected, retry applies only to checked songs. Clear selection to retry across the session. No match is a completed lookup; use ordinary recognition to check again.
5. After finishing/stopping the batch, review candidates and choose **Use match**, inspect the draft, then **Save tagged copy** for each song. Recognition never applies metadata or exports files automatically. Existing tags, lyrics, artwork and previously chosen matches remain intact.

Recognition is serial and retains the existing provider throttling. One failure does not stop subsequent songs. Other cards can be opened for inspection during recognition; editing, settings, imports, removal and export wait until the batch stops. Candidate lyric/cover availability checks resume for the selected track after the batch.

Checkbox selection, status, error details and attempts are saved with each draft. On restart, running/queued work becomes **Interrupted** and waits for an explicit retry. Completed results remain available. The in-memory batch summary is cleared when switching workspaces. Autosave has a short delay, so a force-stop can lose the latest unsaved transition.

A missing AcoustID key permits fingerprint extraction but marks matching failed with its setup message. Add the free application key and retry. Updated local clients/backend supply `lookup_performed` to distinguish configuration from a completed empty lookup; older backends still work but cannot provide this distinction.

