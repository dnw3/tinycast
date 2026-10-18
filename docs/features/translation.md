# Translation

## Invariants

- `AppCore` owns the state, settings and coordinator. Views receive `TranslationCoordinator` through
  their environment. There is one translation window, independent of AI Chat and Quick Actions.
- `command:translate` is the stable launcher and hotkey entry. Translation has its own settings pane
  and enable switch. Manual input works without Accessibility; a hotkey never requests that grant.
- Selection queries open in an unpinned Mini window. They close on focus loss, except during
  validated delivery. Capture queries open expanded and follow the same unpinned dismissal rule.
  Expanding changes presentation only; it does not pin or restart the query.
- Capture the external application and original editable field before presenting the window. Read
  selection through Accessibility or the captured text range. Empty or unconfirmed selection opens
  the editor. Secure input and missing permission leave manual input available.
- The original text, selection range and focused AX element must still match before delivery, after
  activation and queueing. If the field cannot be verified, offer Copy. Do not paste into a new focus.
- Editing, changing languages or engines, opening a new query and closing invalidate the previous
  revision. Late deltas and completions cannot enable actions or replace newer text.
- Committed nonblank input automatically translates after 800 ms without edits. Marked text never
  starts a request; committing it restarts the delay. Explicit submission cancels the pending timer.
- Streamed output is a preview. Copy and Insert/Replace require a complete current response; a failed,
  cancelled, empty or explicitly truncated response cannot be delivered.
- Apple is the default engine and uses downloaded system languages. AI requires an independently
  selected model through the existing provider factory. There is no automatic provider fallback.
  The request has translation instructions and source text only, with no chat history, tools or search.
- No source text or translation history is persisted. Translation preferences and model routes are
  excluded from settings backups. The AI provider retains its own documented transport behavior.

## Window and keyboard

The floating, non-activating `TranslationPanel` hosts SwiftUI and a plain TextKit 2 input view.
The default Mini window opens at the top-right of the display under the cursor, at 420 pt wide.
Placement uses the visible frame to avoid the menu bar and Dock. Its result grows with content up to
220 pt, then scrolls; an idle editor does not reserve an empty result area. Expand provides a
640 × 540 pt editing surface, and Collapse returns to Mini without replacing the editor or request.
Pin keeps either size open when switching applications. Unpinned windows close on focus loss.
Delivery temporarily suppresses that dismissal while the original application receives focus;
success closes the window, and failure refocuses it with the result intact.

The title is draggable; input retains native selection and editing. Resizing preserves the current
top-right and clamps to the window's display, including after dragging onto another monitor.
This also keeps the right edge stable across expanding and collapsing. Each new query resets placement.
`TranslationWindowGeometry` owns this pure frame calculation. The controller owns the AppKit frame;
SwiftUI reports content size, and `NSHostingView.sizingOptions` stays empty. The window uses `Theme`
and scaled `InterfaceMetrics`, including light and dark appearances. Window modes are not persisted.
The `TranslationWindow` log category records geometry and focus lifecycle without source or output text.

The panel rounds with `radius.panel`, like Notes and the palette, and its controls are Tinycast's own:
the engine and language selectors are `HeaderMenuButton`s, the window actions are compact
`BarButton`s in a frosted capsule, and hover labels use `.tooltip`, since a non-activating panel
never shows `.help`. The selectors and the actions menu open `TranslationMenuWindowController`, a
child window copying `PopoverMenuRow`'s look as Notes' heading menu does, because `PopoverMenu`
reads palette state. Any press in the panel, Escape, focus loss or a resize closes it.

The completed result has a Copy icon at its top-right, changing to a checkmark after copying; it stays
outside the scrolling text. The adjacent actions menu holds Translate Again and Insert/Replace,
listing Insert/Replace only while the original target is verifiable. There is no persistent
Translate or Replace button row. The input takes `formFieldChrome`; its length note appears only
near the 12,000-byte limit. A notice appears only when there is something to act on: missing
Accessibility, a password field, or a selection that cannot be replaced. An empty selection says nothing.

| Gesture | Result |
| --- | --- |
| Translate command or its configured global shortcut | Read selection and translate, or focus an empty editor |
| Pin / Unpin | Keep visible on focus loss / restore automatic dismissal |
| Expand / Use Mini Window | Change size while preserving input, languages and the active response |
| Pause typing or pasting for 800 ms | Detect language and translate automatically |
| Return in the input | Translate immediately, cancelling the pending automatic request |
| Shift-Return | Insert a newline |
| Command-C / Command-V / Command-A | Native editing in the focused text view |
| Command-Shift-C | Copy the completed translation |
| Command-Return | Insert at the captured caret, or replace the captured selection |
| Escape | Close and cancel, except while the input method owns marked text |

The panel handles editing chords because a non-activating window cannot depend on the foreground
application's menu. Input-method composition keeps Return and Escape until its text is committed.
`TranslationTextView` reports text and composition changes after TextKit finishes marking or committing
text, including a commit without a text change. `TranslationInputSession` owns the cancellable delay;
the coordinator cancels it on explicit submission, input invalidation and window dismissal.

## Language policy

The default preferred pair is Simplified Chinese and English. A source in the primary language
family goes to the secondary language; other languages go to the primary language. Manual source
and target choices take precedence for the current query. Chinese script variants count as one
language family for automatic direction.

`NLLanguageRecognizer` supplies hypotheses. `TranslationLanguagePolicy` considers script evidence,
mixed Chinese/Latin text and the preferred pair for ambiguous short text. It cannot make ambiguous
words certain, so the detected source remains visible and overridable. Numeric and punctuation-only
input stays unchanged. Detection and translation run together after the input debounce; selected text
and explicit submissions start immediately. Changing the language or engine also submits immediately,
unless the editor still contains marked text.

The menu combines Apple's supported languages with common AI choices. The Apple service checks the
actual source/target pair. A missing pack leaves the input visible and links to Language & Region.
Pin before switching to settings to retain the query, or reopen Translate after downloading the pack.
Unsupported pairs offer a clear error.

## Delivery and providers

`TranslationTarget` captures an editable AX element, its full value and UTF-16 selection range.
`TranslationTargetPolicy` checks unchanged text and selection. `TextInjector` accepts an optional
validation closure, checked inside the queued delivery, at the AX write and before event insertion.
Existing snippet and Quick Action callers retain their delivery behavior.

Read-only pages and editors without sufficient AX information remain usable for selection and
translation, but expose Copy instead of guessing where to write. A failed delivery keeps the result
in the window and does not overwrite the clipboard without an explicit Copy.

Translation first reads Accessibility selection attributes and browser text-marker ranges. If neither
returns text and no editable target was captured, it invokes the source application's enabled Copy
menu command, identified by its Command-C equivalent rather than a localized title. This supports
read-only content in applications such as ChatGPT that may not expose their selection over AX.
It does not synthesize Command-C or copy from a confirmed empty editable target.

The shared `TextInjector` snapshots the clipboard, waits for its change count to advance and restores
all original formats after reading. Old clipboard content is never used as selected text. Only one
copy borrow runs at a time — a translation read refuses while a quicklink or snippet holds one — and
clipboard history is paused for its duration, so the borrowed copy is never recorded. The Copy
command is revalidated against the original foreground application immediately before execution;
switching applications or cancelling invalidates pending selection work. The translation panel is
presented only after selection reading, so its editor cannot steal the source's focus. Missing
permission, secure input, a disabled Copy command or a failed read leaves manual input available.

Input is limited to 12,000 UTF-8 bytes. AI requests allow up to 8,192 output tokens and require a
finished event. The shared HTTP decoder reports OpenAI `length`/`content_filter` and Anthropic
`max_tokens` as errors. This detects explicit truncation; it does not certify a model's semantic
completeness or translation quality.

Installed provider catalogs are loaded when the Translation settings pane is visible or an open
translation window uses AI. The Apple path does not start installed AI providers on its own.

## Verification

`translation-test` compiles shipped language policies, state, settings, language detection and the AI
translation service, input session and native TextKit editor. It covers 50 fixed language samples, configurable direction, manual overrides,
settings persistence, stale output, unchanged delivery targets, request isolation, cancellation,
incomplete streams, explicit provider truncation, window-mode resets, delivery focus protection and
window placement on secondary displays, debounce coalescing, cancellation on clear/close/manual submit,
and marked-text commit notifications. The debounce tests control the wait with continuations instead
of relying on wall-clock sleeps. It uses deterministic provider fixtures; it does
not claim live translation quality or cross-application delivery from unit results.

`snippets-test` exercises the shared menu-copy hook with a private pasteboard: a newly copied
selection is returned, plain text and HTML are restored, a refused action cannot return stale
clipboard content, and cancellation does not invoke Copy. These fixtures do not replace a native
ChatGPT selection check. `TranslationSelection` logs only the source bundle ID, retrieval route and
success or permission state, never the source text or translation.

Before shipping, check a writable native editor, a browser input, a read-only browser selection,
Chinese input-method composition, a changed target, a missing language pack and a configured live
provider. Current implementation and verification evidence are recorded in
[the implementation plan](../plans/translation-plan.md).

## Screenshot text sessions

Capture calls `open(text:source:translate:notice:retaining:preview:)` after OCR; Translation does not
capture a screen or run Vision itself. The source records a document ID/revision, retains the source
lease and shows a bounded preview of the composited image. Opening it clears any prior writable target.
Insert/Replace is absent for screenshots. Copy Source respects the selected input text, and Translate
uses the existing engine configuration. Input above 12,000 UTF-8 bytes is preserved and cannot be silently
truncated for a provider request. The user can select a smaller passage or edit it explicitly.

Screenshot edits invalidate the old translation but wait for an explicit Translate action. Unpinned
screenshot sessions close on focus loss, cancelling the task and releasing the image lease just like
explicit closing. Pin keeps the source, result and request available while switching applications.
Existing selection input keeps automatic debounce and focus-safe delivery.

Speech, translation history, mouse-selection popups and simultaneous engine comparisons remain outside
this version. Capture's integration acceptance is tracked [separately](../plans/capture-acceptance.md).
