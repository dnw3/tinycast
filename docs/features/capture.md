# Capture

## Invariants

- `AppCore` owns one `CaptureCoordinator`; views call the coordinator through their environment.
  Commands, settings and clipboard image actions share that owner. Startup never starts capture or requests permission.
- Screen capture uses macOS 26+ ScreenCaptureKit. Tinycast's controls are excluded; ordinary display/region
  screenshots include existing pins as frozen desktop pixels, and every other window Tinycast's process has on
  screen the same way — AI Chat, Settings, Notes, Quick Action and Translation panels with their child windows,
  and what the system draws there for it, such as input-method candidates, tooltips and the menu bar icon —
  which window selection picks like any app's (`screenshotWindowIDs`). The launcher, clipboard history included, is captured
  when a global shortcut starts the capture: it hides only under the overlay, whose frozen desktop shows it; a
  capture run from a launcher row hides it first. HUD toasts and dialogs never are — a toast is often the last
  capture's own, a dialog may be its question still fading out. Scrolling and recording take the same windows
  except pins and the launcher (`contentWindowIDs`), so AI Chat scrolls through or records like any app's
  window; the capture's own controls and region border, made after the filter, never enter a frame.
  Permission is requested
  only after a capture command; granting it does not automatically retry an earlier capture.
- Model contains Foundation value types only. Documents, annotations, geometry, registration decisions,
  revisions and undo contain no decoded images or environment access.
- RGBA tiles use sRGB, straight alpha and top-to-bottom rows. Tiles are at most 1024 × 1024; dimensions
  are at most 30,000 per side and 64,000,000 pixels, including after decoding a stored manifest.
- Published source rasters are immutable; a workspace may add new window rasters. `CaptureSource` keeps the directory alive while an editor,
  pin, renderer or screenshot text session uses it. Closing the last owner removes the temporary source.
- Long screenshots append disk-backed strips. Registration and output never build a full growing bitmap.
  The canvas retains at most four viewport tiles plus a bounded preview; undo retains source references and edits, not pixels.
- Copy, Save, Pin and OCR use a fixed document revision. Late OCR and selection events cannot overwrite
  a newer session. Cover is rendered as opaque black, and OCR reads the composited image, never hidden source pixels.
- PNG is streamed through system zlib, into a temporary sibling file, then atomically replaced. A failed
  or cancelled export preserves the prior destination. ImageIO exports are limited to four million output
  pixels; original-size sRGB PNG stays streamed. The save panel offers PNG/JPEG/HEIC and AVIF when the
  system can encode it, original/1×/half/quarter sizes, lossy quality, and sRGB/Display P3 output profiles.
  Source tiles remain canonical sRGB; choosing Display P3 converts those pixels, without recovering gamut
  that the original import discarded. WebP uses the approved, vendored official libwebp, with lossless
  or lossy output, alpha and ICC. It shares the 4 MP non-streaming export cap and adds the format's
  16,383-pixel side limit. Validation stays in the save panel; it never silently reduces dimensions.
- Clipboard delivery observes `ClipboardManager`'s mutation handshake, enable switch and source exclusions.
  It records the final PNG once. It does not enable clipboard history or index original unredacted images.
- History is flattened by default. Editable originals and explicit drafts contain pre-redaction pixels;
  retaining originals is an explicit setting excluded from backup import. Missing or corrupt draft tiles
  fall back to the flattened result, not a partially recovered original.
- A screenshot text session uses the existing Translation window and its unpinned focus-loss dismissal.
  Pin explicitly keeps it visible. It clears the old delivery target and offers no Insert/Replace action.
- Work is cancellable and owned. File/render work uses `CaptureWork` off the main actor; Vision runs in
  the shared `TextRecognitionHelper`. WebP save uses a short-lived `CaptureWebPHelper`; its bounded input
  contains only final RGBA, ICC and encoding options. Cancellation/deadlines reap it before input cleanup,
  and the app alone atomically publishes the output. No new singleton or actor is introduced. The sole dependency
  exception is official libwebp for WebP export, approved by the user on 2026-09-29.

## Selection presentation

The frozen desktop retains the original ScreenCaptureKit image, rather than a 900px library thumbnail.
A single screenshot is capped at 64MP, and multi-display selection shares that aggregate limit.
These images belong only to the selection workspace and are released on closure; the canvas tile budget stays unchanged.
A fixed image layer displays the original screenshot separately from the interactive selection view.
Panels disable window and layer animations, then lay out and draw before presentation. The idle desktop
keeps its original brightness; only a dragged or completed region dims the area outside the selection.
Display previews preserve window shadows and use local display intent and the target screen color space;
source tiles and exports retain canonical sRGB pixels. Panels are reused by display ID; closing drops
content views, first responders and image references, and removed displays are evicted on the next presentation.
Source tile preparation is owned separately by the coordinator and begins after presentation. Selection
can start immediately; its latest region/window/display choice waits until source files are ready before
creating an editor. Scope changes discard queued choices, closure cancels work, and completion validates
workspace identity. Failed preparation closes the current overlay and reports the error. Source leases
keep unfinished writes alive without exposing incomplete files to editing, OCR or output. Pointer tracking sets the initial crosshair immediately,
uses arrows over controls and outside a completed selection, and restores the arrow when closing.
Before selection, Close/Cancel shares the bottom toolbar surface. After selection, screenshot output actions
use a side column exactly one button plus the shared padding wide. Scrolling, recording and target selection
keep Close/Cancel in their bottom toolbar. Toolbar placement prefers space outside both the selection and
the annotation bar, including narrow regions.
Bars hold only icons and the commit action, so their width stays put as the state changes: instructions
such as Preparing image…, Click a window or Add below ↵ sit in a notice under the bar. Start Recording and
Start Scrolling read like the palette's primary pill, text plus ↵, and ↵ runs the same action. Every bar is
`CaptureChrome.barShape` padded by `xs`, with tools in the concentric `toolShape`; notices and review cards
take the HUD's scrim and glass because they sit on arbitrary screenshots.
Before and while dragging a new region, a pointer loupe shows original pixels, sRGB HEX and top-left pixel coordinates.
It hides over controls and after completing selection and never writes the clipboard.

## Entry points and interaction

The commands are Capture Screenshot, Capture Full Screen, Capture Scrolling Screenshot,
Record Screen, Capture Text, Capture & Translate, Edit Clipboard Image, Pin Clipboard Image and Capture History.
They use the existing command alias and hotkey configuration in the Capture settings pane.

A normal region stays on the desktop after mouse-up. Its icon toolbar edits the shared document in place;
Return or Command-C copies directly. Region, Window and Screen share this workspace, and Space switches
window selection. The separate editor is an explicit Expand Editor action with the same undo state.
The inline host attaches the shared AppKit canvas directly at a fixed scale; only the separate editor
uses `NSScrollView`. Overlay windows use their target display color space for local screenshot presentation.
Export profile choices remain independent of the overlay's color space.
Unedited ordinary images close without confirmation;
new edits or an unsaved scrolling result offer Save Draft, Discard and Cancel. Saved history opens as
already saved and becomes dirty only after another edit.

Capture toolbar actions and menus share square hit areas and centered, bounded glyphs. Native menu
indicators are hidden so split menus cannot widen or shift a toolbar cell; primary actions remain direct.
System symbols retain their font proportions; Arrow, Expand and Close use a smaller optical size without
shrinking their hit areas. Ordered visibility persists in the existing local toolbar preference; old unordered
configurations retain their choices. Desktop annotations stay in one row and excess items remain in All Tools;
excess side actions enter More Actions. Capacity follows the display rather than the selected region, with
space reserved for navigation, undo/redo and Close/Cancel. The separate editor also limits annotations to its width.
The inline and window editors share all annotation tools. The default toolbar keeps Select, Arrow,
Rectangle, Text and Cover; All Tools groups the remaining annotation and image/recognition actions.
It opens a menu rather than adding another row. Right-click a tool to keep it in the toolbar or move it
to All Tools. Customize Toolbar opens an owned panel with live ordered previews, separate annotation/action lists,
Chinese/English/shortcut search, visibility checkboxes, native row drag sorting and Reset. Search temporarily disables sorting;
context menus and VoiceOver actions provide Move Up/Down without persistent arrow buttons.
Capture settings provides the same entry without starting a screenshot. Select remains first
and cannot be hidden or moved. The All Tools menu groups both visible and hidden tools into submenus; choosing one executes it
without changing the layout. Its ellipsis icon stays stable when a hidden annotation tool is active.
Customize Toolbar separates Annotation Toolbar and Action Toolbar. Copy, Save As, Scroll Capture,
Record Screen, Pin, Extract Text, Translate, Share and Upload can be kept in the action bar or left in
All Tools. New defaults keep Copy, Save As, Scroll Capture, Pin, Extract Text and Translate visible.
Scroll Capture and Record Screen only operate on a live desktop selection; imported images and the
expanded editor keep them unavailable. Scroll Capture starts sampling the existing region directly. The original overlay remains visible
until the live controls are ready; selecting a window capture requires adjusting a live region first.
The local layout uses a keyed configuration; old annotation-only sets retain every choice and gain the
initial action defaults. Explicitly hidden actions survive reopening, including when all actions are hidden.
Existing persisted layouts are preserved, and shortcuts still reach hidden tools.
After selection, Capture Area and Mode share one menu. Before selection, scope and mode buttons remain direct.
Inline Style offers color, stroke, font, size, fill, blur and magnification choices without a persistent
property row. Precise properties, custom colors and the emoji picker remain in the expanded editor;
Adjust Image and Beautify open that editor. Both hosts share the same document and undo state.
Copy, Save, Pin, Extract Text and Translate have direct icon actions with accessible names.
Command-S/Quick Save writes the final composite directly to ~/Pictures/Tinycast, creating the default
folder on demand. Capture settings can choose another folder; a missing chosen folder reports an error.
The bundle-scoped capture.quickSaveFolder preference is mirrored in settings.json and excluded from backups.
Time/UUID filenames publish without replacing an existing file; cancellation and failure remove staging files.
Quick Save uses the current format/export options and closes only the unchanged inline session after success.
The expanded editor stays open. The main Save icon and Shift-Command-S open Save As, hide the overlay,
and restore it after completion or cancellation; this does not change the quick-save folder.
Save As suggests a localized Screenshot or Recording name with Quick Save's timestamp.
The save menu retains Quick Save with an actual Command-S binding and Show Quick Save Folder.
Settings can also reveal the folder; successful saves report the tilde-abbreviated destination directory.
If history cannot be saved, only the HUD says so (Copied/Saved, but history couldn't be saved).
Both save shortcuts work while editing annotation text; text copy and undo keep their normal behavior.
Scrolling controls offer Finish and Save As to stop sampling and open the result's save panel in one action.
That action stays disabled until the first valid frame is captured.
Cancelling that panel keeps the captured result in the editor. During sampling, the source application
keeps keyboard focus for scrolling; its save shortcuts are not intercepted globally. Shift-Command-S
also finishes and opens Save As when the scrolling controls themselves have keyboard focus.
Text results dismiss the overlay before opening Translation, so capture cannot cover the result.
Tooltips show shortcuts. Tool groups can wrap for narrow hosts or custom layouts, but More and Style never
expand another toolbar row. Close Capture (Command-W) requests closure directly; Escape retains its
contextual cancel/deselect/tool-reset behavior. Unsaved content still goes through the preservation dialog.
See [the efficiency spec](../plans/capture-efficiency-spec.md) and [implementation plan](../plans/capture-efficiency-plan.md).

QR scanning uses the existing recognition helper with a typed request content kind. It scans the
composited overview and overlapping full-resolution tiles, maps results back into document coordinates,
and deduplicates overlapping detections. Results remain beside the image; Copy (confirmed by the
Copied HUD) and HTTP(S) Open Link are explicit user actions. A document revision change clears old code results. Hidden source pixels
are never passed to QR recognition.

Selection Options includes a 3/5/10-second delayed recapture. It closes the current capture through
the normal preservation policy, restores the source application and shows a cancellable countdown.
At the deadline it takes a fresh frame and restores the selected region, screen or window identity;
it does not reuse the earlier frozen pixels. Cancellation writes no output. Sleep, lock and display
changes cancel the countdown. A disappeared window remains a selection error rather than capturing
a different window under the pointer.

Moving or resizing the capture region reprojects annotations through screen coordinates and creates one
undo step. Region and annotation changes share a bounded undo stack. Independent window capture keeps
its own source reference, so undo can recover the earlier screenshot instead of attaching old marks to
new window content. No decoded images are stored in undo.

The editor's native text view has its own undo and input-method composition. Editing uses the
annotation's ink and hides the prior text until commit. Selection supports
movement, resizing and style changes. New annotations show only their artwork while drawing; Select
shows editing controls. Arrows, curved arrows, lines and rulers expose endpoint handles rather than
rectangular boxes; endpoint movement preserves the other endpoint through rotation/reflection.
Line tools ignore clicks without drawable extent, and filled arrow shafts stop beneath the head. Normal images fit the window, vertical images fit its width and
horizontal images fit its height; Entire Image and 100% remain explicit choices. Command-C/S/Z/W and
Escape are handled after text input. Controls use `InterfaceMetrics`; pixels and annotation geometry do not scale with preferences.

Pins retain a document snapshot and a bounded 2400-pixel preview. There may be three. They float across
Spaces without closing on blur. Dragging the image moves the panel with an open-hand cursor; scroll and
magnify resize around the pointer while preserving aspect ratio. Hover uses the same frosted surface as the capture toolbars, with More and Close plus a
zoom percentage that resets to the initial fitted size. More and the context menu provide Copy, Save As,
Quick Save, Show Quick Save Folder, Edit, Reset Zoom, Opacity and Close. Opacity affects only the image.
With a pin focused, Command-C copies, Command-S quick-saves, Shift-Command-S opens Save As,
Command-0 resets zoom, and Escape/Command-W close that pin. Editing transfers its snapshot/source to
the editor and removes the old pin only after closure is allowed. New pins start slightly offset.
Ordinary capture preserves pins in the frozen desktop and output, while its controls remain excluded;
existing panels stay beneath the selection overlay and reappear unchanged when selection ends.
Scrolling and recording retain their clean-source exclusions. Native drag, menu/gesture routing,
multi-Space, keyboard, Retina quality and VoiceOver behavior remain in the acceptance checklist.

## Scrolling capture

The scrolling icon starts manual vertical capture directly from a selected region. Its menu offers
Vertical, Horizontal and Adjust Region; direction and region preparation remain available before sampling.
A picked window — the scrolling icon on its selection, or a window clicked in scrolling mode — starts at
once with the whole window as its region, as the reader picked it, so the reader only scrolls; its title
bar, sidebar and composer stay put and are matched around rather than cut away. A screen capture first
requires a region inside the scrolling content; the previous selection is hidden so the first drag
creates the new region.
A drawn region that strays past the window under its center is trimmed to that window, rounded inward
(`CaptureGeometry.innerPixels`), rather than reading as outside it at once. Starting refreshes the ScreenCaptureKit filter to exclude
the Dock. The original desktop workspace is retained until a result is accepted or cancellation restores it;
annotations are not baked into scrolling frames.
The result window switches between Screenshot and Scrolling Screenshot with one segmented control in its
title bar, preserving each image and undo stack.
Closing checks both unsaved results. Canceling without keeping a result restores the retained screenshot in its original desktop workspace.

`ScrollCaptureSession` serializes sampling and RGB registration. Strips, once decided, are written in
order behind it (`enqueue`), with their seam and incremental preview, and always complete, since the
tracker has already moved the result's end past them: waited for in the loop, a write of about 50ms on
nearly every sample of a fast terminal scroll slowed sampling to about 165ms and let the scroll outrun the
overlap. A screenshot of the region takes about 30ms. It samples again 10ms after each sample while
anything moves, about every 55ms in all, and every 150ms once ten samples in a row were at rest, reading the captured image in memory (`ScrollFrameReader.sample(_:axis:)`); only strips reach the
disk, each cut from its own frame (`strip(_:rect:to:)`). A frame reaches back two thirds of the region,
and a single trackpad flick moves further than that, which is why the frames in motion are used, not
only the ones at rest. `ScrollTracker` decides which become strips:

- The first strip is a frame at rest, two samples alike, so nothing half-drawn starts the capture.
- Every later sample is matched against the frame matched from, which starts as the last strip's frame
  and follows the reader back and forth, apart from the result's end (`lead`): a frame behind the end
  becomes the one matched from, so scrolling back past the last strip's reach and on again keeps the
  overlap, and only lines past the end are ever added. The newest frame that reaches past the end waits
  as pending, and is written as soon as the content rests or a later frame no longer lines up with it;
  scrolling back a little keeps the furthest pending frame, and finishing writes it.
- A frame that lines up with neither, once a miss has been seen, is matched against up to four earlier
  strips (`historyLimit`), newest first; one that places it makes it the frame matched from.
- After two samples in a row that do not line up, a lasting notice under the bar asks to scroll back a
  little, with Go On from Here beside it; the next frame that lines up clears both and capture carries on
  by itself. Nothing is force-stitched meanwhile. Go On from Here, taken up by the sampling loop rather
  than racing it, adds the latest frame whole after the result's end, less its unreliable trailing lines,
  says that what was scrolled past is missing there, and matching goes on from it (`ScrollTracker.bridge`).
- Two frames in a row above the first strip, before half a frame was added, turn the capture: frames
  reach matching upside down (`Frame.reversed`, travel negated), so scrolling back reads as scrolling on,
  and strips go before the result (`CaptureScrollAppend.plan(atStart:)`), retaking its first lines, which
  hold the title bar and the fade under it. Lines added before the turn lie behind the new end and are
  climbed over, not repeated. A frame above the result's end otherwise shows Scroll forward, or Keep
  scrolling back once turned, for three seconds.

Each strip retakes up to `ScrollFrameReader.seamReach` (48) more lines than it must, so the seam falls on
the line where the two frames agree and nothing is drawn, compared at full resolution: between lines of
text rather than through one. Matching never sees this choice.

A strip beside the region, as tall as it and `captureScrollThumbnail` wide, shows the result so far,
fitted across with its newest end in view: the bottom, or the top once turned
(`CaptureControlPlacement.scrollingPreview`). It goes on whichever side has room clear of the region and
the controls, and is left out when neither has; Show Live Preview in the More menu hides it. The
incremental preview is 256 pixels across, at most 6,000 along, and copies what it had pixel for pixel at a
whole-pixel offset, since redrawing it at fractions blurred it more with every strip and left a faint
line at each seam.

Matching is strict except where the pointer is, or where something sits still over the page. Lanes
stay `edgeMargin` clear of both region edges, where an overlay scroller moves at its own pace. A
leading bar is a run of lines no lane of which moved (`Frame.fixed`): a glass title bar tints with the
page beneath it, so the average may differ up to `barTolerance`, but a line of sparse text that moved in
one lane is no bar, and a leading band taken too deep would narrow the search past the true shift. The
trailing band only needs the average, since one taken too deep only retakes lines. Each sample records
the pointer's line while it is over the region, and the 32-line windows within `hoverReach` (96 lines,
about 48pt at 2×) of it in either frame are hovered, since whatever sits under a resting pointer lights
up as content passes: they still mark an edge band, but count toward the fit only when the scroll events
confirm the shift, and then only where they line up. A window that lines up only at the same line in
both frames is held — a sidebar, a floating button — and so is one part still and part moving beside a
held one, its rim. A wide sidebar holds about seven windows in ten still; past four in five, the windows
that moved are a sliver that happened to line up, and the shift is uncertain. At either end of the
overlap, rows where a third of the lanes that are not held settle in neither frame — an edge fade, a
dimmed band — are left out, out to the last such row within a sixth of the frame, since the deepest fade
often lies over blank and passes. Below them `edgeClearance` (64 lines) is always retaken from the newer
frame, because a fade over a short line can slip between lanes; at the bottom all of it widens the
trailing rows, so each append retakes them and no seam keeps faded lines. Everywhere else a lane may
differ in at most one window — a caret blinking — so a layout that repeats at a different line still
makes the match uncertain: a lane that moved does not line up at the wrong shift, nor at none. A
tolerance spread over the whole region was tried and took a page that repeats every few lines for a
shift it never made, and a part-still window counts only as a held window's rim because a sparse page
otherwise matched a near-repeat. The fit is the 95th-percentile error of the windows that show anything,
since blank ones match at any shift and would hide a line's slip on a sparse page; a best shift within a
window's stride of the end of the search range is uncertain too, because the true one may lie beyond it
and a sliver of overlap that lines up there proves nothing. Recorded AI Chat frames found such a shift
taken 105 lines short.

The session watches scroll-wheel events over the region, through a global monitor and, for Tinycast's
own windows, a local one; neither needs Accessibility. Each sample carries the travel they add up to,
in pixels (`Frame.travel`), until a wheel's notch arrives, whose lines an app sizes as it likes and which
ends the travel for the session. On recorded AI Chat frames the travel ran anywhere from one to six times
the content's move, frame to frame, so its size is a weak witness and its direction a strong one. A best
shift within `slack` of it (a quarter, at least 24 lines, either way) is confirmed, which admits hovered
line-ups and a fit error under 12 rather than 8, and the lines within that slack join the refined search,
since a coarse pass can miss a large shift between sparse lines. Travel said to reach past the search
range confirms nothing. Travel of 200 lines or more the other way rejects a shift; nothing else about the
travel does, so an app scrolling at its own ratio only loses the witness. Fewer than `minimumEvidence`
(12) windows that moved with the page leave a shift uncertain. A frame at rest that no longer matches,
with no travel since the frame it is matched from, replaces that frame (`ScrollTracker`): the picture
changed in place, as a window does turning key a moment into the capture. When the overlap is lost after
travel of half the frame or more, the notice says the scroll was too fast rather than only that it was
lost.

AI Chat holds its hover effects still while a scrolling capture reads it (`chatHoverStill`), so no Copy button the pointer happens to rest on is stitched in.
Duplicate frames do not grow the result. Along-axis fixed headers stay in the first strip;
the previous fixed footer is removed before a new strip and footer are appended. This detection still
needs the real browser/PDF/native-list corpus before AC-04 can pass.

Record Diagnostic Frames, in the controls' More menu, writes every later sample of that session as it
was captured, named with the pointer's line and travel, plus one verdict line each in `trace.tsv` with the
interval since the last sample and the milliseconds spent capturing and matching it, to
`captures/diagnostics/scroll-<time>` under Application Support; Finder shows the folder when the
session ends. Writes queue behind sampling rather than slow it and stop after
`ScrollDiagnosticsRecorder.frameLimit` frames. Recordings older than three days, and all but the newest
three, go whenever a capture starts (`CaptureRepository.reclaimDiagnostics`), and a new recording makes
room for itself first; Disk Cleanup never offers Tinycast's own files, so this is what keeps them from
piling up. It is off for every new session, since the frames are screen contents. `capture-scroll-replay-test` replays such a
folder with `TINYCAST_SCROLL_REPLAY`.

Manual is the default and needs no Accessibility grant. Auto Scroll is an explicit choice for each
session, checks Accessibility and revalidates the original PID/window/frame/visible region immediately
before posting a scroll event at the selected region's center through the session event stream.
Target changes, lock, display changes and lost permission pause capture.
`CaptureVisibilityPolicy` ignores fully transparent windows and the system cursor layer; moving the
pointer into the selected region must not count as another window covering the content. Scrolling
capture also excludes the system Dock from its ScreenCaptureKit filter. The visibility policy uses
that same set of excluded application PIDs, so a desktop-sized Dock surface cannot pause capture or
enter the output. Application exclusions come from the full shareable-content list, because an
on-screen-only list can omit Tinycast while its launcher is hidden. Missing self-identity fails closed;
only on-screen windows remain eligible capture targets. Tinycast's content windows are taken back by
window ID (`includedWindowIDs`), into the filter and the visibility policy alike: each is a target, or
covers a region, as any app's window would, while its other windows stay invisible to both. Ordinary screenshots retain their original filter. Visible
application windows above the target still pause capture, including windows from the same target app.
Starting a scrolling session activates the selected window's application, which can differ from the app
that was active before the command. History actions capture a fresh focus-return target.
Visibility failures distinguish inactive, moved, outside and obscured targets. A bounded Capture log
records the failed check and window/PID metadata, without screen contents or window titles.
The control bar is placed outside the region, otherwise selection fails with a request to leave space.
Return/Escape/Space work when controls have key focus — Escape through the panel's `cancelOperation`,
since the shortcut inside its menu answers only while the menu is open; a configured capture hotkey
finishes independently of page focus. A Tinycast window under capture activates Tinycast and hands the
keys to the controls (`activateScrollTarget`): AI Chat closes on Escape, and the wheel still reaches it. No progress percentage or claim of reaching the bottom is inferred from duplicate frames.
Reopening Tinycast raises the active scrolling or recording controls instead of opening the launcher.
These nonactivating panels take keyboard focus without activating Tinycast over the captured application.
Continue and Auto Scroll reactivate the original captured application before resuming target checks.
Scrolling controls use the current interface metrics, matching their measured placement and hit areas.
The compact single row shows status, Auto Scroll, Pause/Continue, Finish and More Scrolling Actions.
The menu holds cancellation, reselection and optional preview/details. Paused reasons expand beneath
that row; normal progress does not occupy a second row. Controls stay outside sampling and within
screen visible frames. If the original display is disconnected, cancellation returns to the window editor.

`CaptureSessionObserver` is owned while selecting, scrolling or recording. Display/system sleep, session switch-out,
display changes and the distributed `com.apple.screenIsLocked` notification pause scrolling, cancel pending
selection work and close the selection overlay. Unlock does not restart capture. The distributed lock name
is not an AppKit notification constant, so actual lock delivery remains a native acceptance item. Private
notification-center tests verify routing and that a released observer cannot deliver a queued interruption.

## Suggested covers

All Tools → Suggest Covers can propose entire OCR lines containing email addresses, supported phone
numbers, US-style social-security numbers or Luhn-valid card-number patterns; Find All Text proposes
all recognized lines. Detection runs locally in the existing bounded helper and uses the composited
image, never an unredacted source. The result is a review list, not a guarantee that every private detail
was found. Names, addresses, faces and people are not detected by this text policy.
Candidates are outlined on the canvas and can be included or skipped. Previous/Next brings the current
candidate into the editor viewport. Cover Areas creates ordinary opaque cover annotations in one undo
step; dismissing the review changes no image pixels. Any document edit invalidates the remaining
suggestions, and stale recognition results cannot replace a newer revision. Final PNG, history,
clipboard and subsequent recognition use the same applied covers.

## Element selection

Selection Options → Select Element uses read-only Accessibility queries against the target process.
The candidate outline follows the element; click commits it, dragging chooses an ordinary region, and
Escape leaves element selection. Event-local coordinates are converted to screen coordinates before
the AX lookup. Queries are debounced and coalesced off-main; stale results cannot replace a later selection.

## Image adjustments

All Tools → Adjust Image reveals brightness, contrast, saturation, sharpness and inversion. The default
screenshot toolbar stays compact. Adjustments affect the source image; annotations retain their chosen
colors and covers are rendered last. Escape closes adjustments before closing the capture.
The document stores validated numeric parameters, with one undo entry per slider gesture. Originals stay
immutable. Accelerate applies the same bounded render path to canvas tiles, preview, PNG bands, other
exports, history, pins and recognition inputs. Sharpening reads a one-pixel halo so tile and band edges
match a single full render; alpha remains unchanged.

## Magnifier and image layers

Magnifier (G) samples the final composited image at 2×/4×/8×; it includes existing covers and vector
annotations. Other magnifiers are excluded from its source to prevent recursive sampling. Cover and
erase remain on top. The viewport and overview use the same raster effect as streamed export.

Add Image and Command-V place a separate image layer on the current canvas. Text input consumes paste
before the canvas does. Select moves and proportionally resizes the image; contextual controls adjust
opacity, rotation and stacking order. A drag or slider gesture is one undo entry. Annotation covers
remain above all image layers, and adjustments/pixelation/blur read the composed pixels.

Image layers have independent source rectangles and transforms; they never enter the contiguous
scrolling strip array. A document accepts up to 32 layers with a combined 64 million source pixels.
Rendering reads bounded source tiles with interpolation halos and hard internal clips, avoiding
antialias seams between rotated tiles. Only the exterior image edge is antialiased. Draft archival,
reopening, reflection and capture-region reprojection preserve the layers. Missing layer sources cause
the entire draft to fall back to its flattened final image. Combine with Image appends a file below or
to the right at its original pixel size and expands the canvas, preserving transparent padding. The first
combination turns the final cropped and covered result into one image layer; a single Undo restores the
previous editable document. Further combinations retain individual layers. Fit Canvas to Images moves
all image layers and annotations together and trims unused space. Append Capture temporarily returns to the same region/window/screen selector and adds the new source below or to the right. Cancelling restores the existing editor.

Remove Background runs Vision foreground-instance segmentation locally in the bounded recognition helper,
using an input at most 1024 pixels per side. A mask asset is kept separately from the immutable image.
Selecting an image processes only that layer; processing an entire document first renders its final
cropped and covered pixels into a layer. Restore Background toggles the mask without recomputation,
including after reopening an editable draft. Masks follow layer scaling, rotation and reflection;
solid covers remain above them. Missing mask assets fall back to the complete flattened final image.

Horizontal/vertical Flip in Adjust Image reflects strips, crops, annotations and image layers without
replacing immutable source rasters. Each flip is one document undo step.

## Recording and video

Record Screen and the Record mode share the existing region/window/screen selection. Switching modes
does not start recording. System audio and microphone start off; enabling the microphone requests
permission only on Start. Preparation offers a 0/3/5/10 second delay, 15/30/60 fps, cursor and mouse-click
visibility, and an end action: open preview, Save File or Copy File. Region recording captures a fixed rectangle; Window binds a desktop-independent window ID.
Recording uses SDR H.264 in MP4 with even output dimensions, capped at a 3840-pixel long edge.

`CaptureRecordingSession` owns ScreenCaptureKit streams and a leased session directory. Screen, system
audio and microphone samples have separate bounded queues and encoders; final MP4 muxing preserves
independent named audio tracks and their offset from the first video frame. Separate encoders prevent
real-time multi-track interleaving from blocking the screen queue. Pause finalizes the current segment;
resume starts another and waits up to five seconds for a valid screen frame before reporting Recording.
A failed start stops the stream and cancels its encoders. Stop joins completed segments by audio identity, retaining silence when an input
is absent from one segment. Static screens retain their last frame until Stop. A failed export retains
completed source segments for retry. A floating control and the menu bar expose Stop. More Recording Actions
provides Cancel Recording; Escape opens that cancellation path when the controls have keyboard focus.
Cancellation first pauses, then offers Back, Discard and Keep Result when completed segments exist.
Back leaves the recording paused; Keep Result opens the video preview without executing Save File or Copy File.
Capture preservation dialogs put Back/Cancel last, matching DialogController dismissal semantics.
Escape or click-away preserves the paused session or open result; only explicit actions keep or discard it.
Recording finalization checks cancellation and session identity before presenting or delivering the result.
Discard restores the retained screenshot workspace and undo state; a disconnected original display uses
its window editor. Escape never silently discards an active recording. If the recording has finalized but
inspection fails, Recorded controls retain Retry Opening Recording and cancellation rather than a spinner. Hidden/closed windows and existing lock/sleep/display observers request a pause.
ScreenCaptureKit blank/suspended/stopped frame states also pause; idle frames retain the valid static screen.
Recording pauses at two hours, 2 GB or 64 completed segments; users can stop and save the result.

Camera and key display are opt-in per recording. The camera has corner, size and mirror controls; its
circular content is composed into encoded video frames, independent of the excluded Tinycast windows.
The keyboard defaults to Off, with Shortcuts Only and All Keys choices. Secure input and repeats suppress
captions; no keystrokes are persisted separately. Camera and keyboard listeners stop on Pause, failure
and cancellation. A bounded frame pump keeps these layers moving over a static screen. Camera and
microphone request their own permissions on Start. Accessibility authorizes the keyboard observer.
Encoder finalization has a 15-second deadline. Cancellation stops the writer immediately and cancels
the reader after its sample tasks have finished, so reading and reader cancellation cannot overlap.

`CaptureVideoState` keeps the immutable MP4 and a separate trim/speed/volume/cut/hold edit. Cut and Freeze
opens an optional inspector; intervals use original recording time. Edits outside the trimmed range
remain available when that range expands. Cuts cannot overlap, and at least 0.1 seconds must remain.
Video edits have a separate bounded undo history; one slider gesture makes one undo step.
The native player and MP4 export use the same composition. Holds repeat a real source frame and insert
silence instead of stretching an audio sample. Export offers original or bounded long-edge resolution
and 15/30/60 fps, with progress and cancellation. Its explicit time range retains the final frame's
full display duration for variable-rate screen recordings. Export writes to a temporary file, then atomically
replaces the chosen destination. Saved MP4s enter Capture History with a thumbnail and duration; reopening
copies the movie into a new source lease. History deletion cannot invalidate an open player.

GIF export samples that same trim/cut/hold/speed timeline off-main, with a selected 320/480/640/960-pixel long edge
and 5/10/15 fps. It has no audio, shows progress and supports cancellation. Limits are 30 seconds,
450 frames and 64 million total frame pixels. GIF saves enter history with their animation duration;
Quick Preview decodes one frame at a time. Video Quick Preview uses AVPlayerView for native playback
controls. Closing either preview releases its source lease.

The video timeline has bounded thumbnails and trim/playhead handles. Timed cover, text and zoom effects
use source coordinates and the original recording clock; preview, MP4 and GIF share the same edit.
Save Editable Draft retains an explicit private original and edit sidecar, alongside the rendered final
video. Copy, sharing, drag and Quick Preview always use the final file.

## Storage and output

`Application Support/<bundle>/captures/sessions/<UUID>` holds active sources; `history/<UUID>` contains
`image.png` or `video.mp4`, `thumbnail.png` and bounded `entry.json`. An editable entry additionally has `document.json`
and a `source` tile tree. Session directories are leased by live owners. History opening copies a validated
source into a fresh session, so deleting a historical entry cannot invalidate an active editor or pin.
Editable archives physically crop each partial source piece before saving its manifest. A live region
may reference a full frozen display for reversible resizing, but its archived source contains only that
piece's selected pixels. No unreferenced display or earlier window rasters enter the archive.
Automatic cleanup runs after output, with defaults of seven days and 512 MB; drafts require explicit deletion.
Each live source holds an exclusive file lock. Creating a new session reclaims session directories older
than one day only when their lease is unlocked, including after a crash. Live sources in another process
are skipped; explicit saved drafts remain outside this cleanup.

Imports stream ordinary noninterlaced 8-bit PNGs. Unsupported PNG profiles/layouts, JPEG, HEIC and TIFF
use the bounded ImageIO path, applying orientation and converting to the raster color contract. Inputs
requiring more than 48 MB decoded memory through that path are rejected. PNG file input itself is bounded
at 300 MB. Clipboard image providers may allocate data before Tinycast can inspect their size; this remains
a resource acceptance limitation.

Copy first encodes PNG. `CaptureCopyPolicy` allows at most 8 MB encoded data; larger results retain the
editor and offer Save at original resolution. The whole-app RSS check was removed from this action
because the existing Dev baseline exceeded it and disabled even ordinary small-image copies. On 2026-09-29
the user replaced the universal 100 MB gate with scenario budgets; the encoded-size cap is a separate protection.

Save panels participate in the existing `ActivationPolicy` window lifetime, including inline and pin-only
save paths. App reopen focuses a visible pending panel. Its coordinator reference ends when the panel
returns, and its accessory view is detached when the operation finishes. The inline workspace resumes
immediately after the picker returns and keeps its actions busy until encoding and history finish.
Reopening the app focuses this workspace instead of placing a new launcher in front of it.
History-editor Copy has been decoded by Preview at 906 × 561 with one matching clipboard-history entry
and one new capture-history entry. Direct region copy through Return has also been decoded and re-exported
by Preview at 1350 × 590, with one matching clipboard-history entry. Repeat-operation memory recovery remains pending.

## Text recognition

`CaptureTextInput` renders 1024-pixel tiles with 128-pixel overlap at original resolution, then sends the
helper a bounded request with document ID/revision. The helper validates tile dimensions and returns
text boxes in document coordinates, with at most 32 KB text and 1,000 boxes. Overlap deduplication uses
both text and geometry, combining overlapping line fragments while retaining the same text at distinct
positions. QR payloads use exact content deduplication. Truncation is explicit.

Foreground capture recognition pauses and awaits background clipboard recognition, then restores it
according to current settings. The helper's output pipe is bounded; cancellation and deadline expiry kill
and reap the child. The exit notification is awaited even when the caller is cancelled, so a killed child is reaped before
the call returns. Clipboard search preserves its existing extraction policy. Screenshot recognition
uses accurate Vision recognition and a 90-second deadline; it does not turn on a background index.

## Verification and delivery status

The implementation is connected to native UI. It is **not yet a completed phase-one delivery**.
`capture-raster-test` guards storage/output pixels; `capture-workflow-test` covers geometry, session IDs,
registration, cursor/occlusion checks, rendered numbered text, actual vertical/horizontal strip pixels,
PNG/JPEG/HEIC crop/cover output, repository restoration
and corrupt draft fallback; `capture-ocr-test` exercises real Vision tiles, redaction, duplicate text, bounds
and child reaping. `capture-editor-test` exercises actual AppKit text composition, Unicode, multiline,
commit keys, private-pasteboard copy and undo without writing to the general pasteboard.
`capture-session-test` guards interruption routing and observer lifetime without posting system notifications.
Clipboard, backup and Translation retain their focused harnesses.

Native image import, annotation tools, crop, keyboard undo/redo, saved PNG, OCR and a live AI translation
have run against generated fixtures. Text movement/color changes and draft saving/reopening also ran.
The user approved Screen Recording and Accessibility for this Dev build. The exact checkout app and OCR
helper now use the fixed local signing identity. Both permission getters stayed true across two builds
with different CDHashes after re-registering the Dev-only grants. Real SCK selection, cancellation and
direct region copy run. Vertical manual scrolling exported a 1500 × 3276 PNG from a 1500 × 1540 region.
Independent decoding, Vision's contiguous rows 002–024, uniform 142-pixel row boundaries across seams
and one matching history entry passed. The fixture anchor hides row 001 before selection.
The session-event routing change now produces a 1500 × 3880 automatic vertical PNG with continuous
rows 063–089 and the same 142-pixel spacing. Horizontal automatic and manual captures produce
3920 × 760 and 3420 × 760 PNGs, with continuous column labels across all seven rows and 446-pixel
column spacing. Each has exactly one matching history entry. Horizontal results fit height on opening;
saved editors close without another prompt. Manual horizontal input used page arrow keys, not a
physical trackpad. Headers and scrollbars stayed outside the selection.
One initial pause was a real intersection with the computer tool's pointer indicator. Another came
from missing self-identity in the on-screen-only application list; full metadata enumeration fixes it
and native horizontal output passed. No tool-specific visibility exception was added. The residual
system prompt has been dismissed. Other real corpora, fixed regions, mixed displays, complete
interruption/accessibility/appearance coverage and the performance matrix remain pending.
Cursor and excluded-Dock visibility regressions pass; ordinary intersecting windows still pause capture.
Memory now uses 300/512/600 MB scenario peaks, five-second recovery and bounded cycle growth.
Old 100 MB failures remain historical evidence. See [current acceptance](../plans/capture-acceptance.md),
[Spec](../plans/capture-spec.md), [Plan](../plans/capture-plan.md) and [G0 evidence](../plans/capture-g0.md).

## Spotlight, blur and color sampling

All Tools holds Spotlight, Blur and Pick Color. Spotlight regions form an illuminated union; only
the image bounds are dimmed. Blur offers three strengths and uses bounded vImage neighborhoods, so
preview tiles and PNG bands agree. Blur is a visual effect and does not guarantee text removal.
Pixelation and solid covers render last. Color sampling reads the composited result, including all
covers, and supplies an editable RGB hex color to annotation styles without writing the pasteboard.

## Media history and file delivery

Saved GIFs retain animation in history, with actual frame duration, dimensions and a bounded thumbnail.
Return opens GIF playback; images and movies also offer Quick Preview. GIF playback decodes sequentially off-main
and queues at most one pending frame; closing cancels playback and releases the copied source lease.
Video preview distinguishes loading, ready and failure, offers Retry Preview, and releases its player item when hidden.
A failed GIF preview shows the same centred card; Retry Preview restarts decoding from the first frame.

Copy on movie/GIF history entries delivers a file; image entries expose Copy File separately from Copy Image.
History Copy (⌘↵) returns focus to the previous app; ⌃X deletes, ⌘Y opens Quick Preview and ⇧⌘C copies the file.
Search matches title, date and subtitle text built once per history load; no match reads No matching captures.
The file is copied into the channel's `captures/transfers/<entry-id>/` directory before changing the pasteboard.
History cleanup, preview closure and quitting the app do not remove it. Repeated copies reuse the immutable file.
The next file copy reclaims transfer directories older than 24 hours, excluding current pasteboard file URLs.
The existing Clipboard mutation handshake avoids recording this as another capture.

### Erase and suggested people covers

Erase samples a bounded perimeter outside the drawn area and commits its dominant opaque color. The sampled color is
stored in the annotation so preview, export and undo use the same result. It is intended for uniform backgrounds; an
area with no surrounding pixels fails without changing the document. Cover and Erase are composited again after image
effects so later effects cannot reveal the underlying pixels. Canvas sampling participates in the editor Cancel action.

Find Faces and Find People reuse the recognition helper and the existing review panel. The helper receives the final
composite, never a retained unredacted original, and returns bounded candidate rectangles. Full-image previews cover
objects crossing tile boundaries; overlapping original-resolution tiles retain small details. Candidates stay editable
until the user applies the covers. Detection is a suggestion and does not guarantee every face or person is found.

### Emoji and alignment

Emoji (J) uses the existing AppCore-owned emoji index, search and skin-tone setting. Its one-row picker updates the
selected sticker or the next insertion; canvas dragging resizes it, with one undo step. Size changes remain within the
image bounds. CoreText preserves color glyphs through preview, streaming PNG, history and clipboard output.
Annotation movement aligns edges and centers within six screen points. Option bypasses alignment; guides never export.


追加截图通过编辑器 More → Append Capture，沿用范围选择与显示器切换。原编辑状态暂存于协调器，
Escape 原样返回，显式确认后才组合并产生一个撤销步骤。取消或源图变更会清理未提交的临时栅格。


美化作为 `CaptureDocument.Edit.presentation` 参数保存；原图、图层、标注和裁剪保持内容坐标，
`outputBounds` 可因外框而扩展到负原点。预览、条带 PNG、OCR 与贴图共用 presentation renderer；
文字识别 helper 的坐标下限有界支持外框。透明/纯色/渐变/网格、窗框、圆角、阴影由同一渲染器输出，
渐变按全图像素坐标计算，避免分块接缝。Remove Styling 能回到未美化文档，尺寸预算仍为 6400 万像素、单边 30000。


图片内翻译保存在 `CaptureDocument.Edit.translation`；原文/译文切换不改写原始栅格。段落保持独立编号、
文本与内容坐标；批量翻译复用 Translation 的 Apple/AI 服务和配置。AI 没有工具或联网搜索能力，
响应严格检查编号和完整性。译文发生在标注之前，遮盖最后绘制；无法完整排入原段落的文字明确报错，
用户可修改后应用或继续使用文本面板。最多 32 段、输入总计 12 KB，输出有界；来源和文档 revision
变化会丢弃迟到结果，关闭/取消沿用协调器任务和来源租约。

### Video timeline and output

The editor keeps trim/cut/hold times and timed zoom, cover and text rectangles in original recording coordinates. A selected effect edits against the original frame; leaving its controls restores the composited preview. Preview, MP4 and GIF share `CaptureVideoTimeline` and the effect renderer. Covers render after text and move with zoom. Precise scrubbing uses zero seek tolerance. Audio-track volumes multiply the master volume; MP4 mixes the chosen levels and inserts silence during holds.

`CaptureVideoEncoder` streams AVAssetReader output into macOS 26 writer receivers with bounded buffering and explicit H.264 bitrate targets. Compact, Balanced and High change compression, independently of resolution and frame rate. Cancellation removes incomplete output; replacement of the user's file remains atomic.

Save Editable Draft retains `original.mp4` and `video-edit.json` only on that explicit action. Its `video.mp4` and thumbnail contain the edited result. History copy, drag, sharing and Quick Preview always use that result; reopening the editor leases both files and validates the edit against the original duration. Drafts do not expire automatically. Share and Copy File prepare a final output and use the existing transfer lifetime; they never send an editable source archive to a sharing service.

## Cross-display images

Selection Options → Display offers Select Across Displays and Capture All Displays. Normal captures
retain their existing single-display behavior. Cross-display capture freezes each connected display
sequentially into immutable tiles, then tracks one rectangle in global AppKit points across overlays.
The output uses the largest selected native scale, preserves transparent gaps in the physical layout,
and opens in the existing image editor. Each source is cropped with outward pixel rounding and positioned
without changing its scale; lower-density screens are resampled. At most 64 million source and output
pixels are accepted, with a 30,000-pixel output edge. PNG export remains streamed. Display changes cancel
the selection. Scrolling and video continue to use one display.

Native two-screen 2× output (7296 × 2234) matches 16,015,104 source pixels exactly, with 284,160 transparent
gap pixels. A drag from the internal screen onto the negative-origin external screen produces 1000 × 500;
all 500,000 pixels match the respective source crops. Mixed 1×/2× geometry and draft archive pixels pass
the harness; physical mixed-density/5K hardware and the total app memory budget remain open.

## Optional delivery destinations

Uploads are configured in Capture settings and run only through Upload and Copy Link in the image/video
editor or history actions. The saved destination and its bundle-scoped Keychain credentials are excluded
from backups. S3-compatible storage uses SigV4 PUT and keeps bucket permissions unchanged; an optional
public URL base changes only the copied link. imgbb accepts PNG/GIF up to 32 MB and is explicitly labeled public.

Google Drive uses this fork's Desktop OAuth client, PKCE S256 and a random loopback-only HTTP listener.
The five-minute authorization session validates state, rejects duplicate callback fields, does not reflect
codes in its response and closes on cancellation. Only drive.file is requested. The refresh token and
optional client secret stay in Keychain; each explicit upload obtains an access token and creates a private
file in My Drive. Upload responses cannot redirect credentials to another origin. No automatic public sharing
or background uploads are performed. Actual provider sign-in and downloaded-file acceptance remain pending.

Transfers use a private ephemeral URLSession with no URL cache, cookies or credential storage, reject
redirects and cap responses at 64 KiB. PNG/GIF/MP4 uploads use the final rendered file, never the editable
source. Local history is committed first and survives remote errors or cancellation. History uploads,
which have no editor notice, report progress in a cancellable HUD that the result replaces. S3 and Drive stream
files up to 2 GB from disk; imgbb's temporary multipart file contains no API key. Cloud links are copied
only after a successful validated response; the app does not open them automatically.

Completion thumbnails are optional and off by default. Successful Copy/Save can show one small nonactivating
panel at the current screen's corner. Click reopens the saved capture; drag exports its final file.
The panel decodes only the bounded history thumbnail, dismisses after eight unhovered seconds, and closes
before a new capture or when the feature is disabled. This desktop visibility choice stays local to the Mac.


### Long-image import and text seams

Capture commands carry Chinese search names through the launcher's existing alternate-name index
(including 截图, 长截图, 录屏, 取字, 贴图 and 截图历史); display titles stay unchanged.
Imported images at least twice as tall or wide as their other dimension initially fit the short axis,
matching scrolling documents. Fit Window remains available explicitly.

Text recognition assigns overlapping vertical tiles half of each shared band. The tile containing a
line's center retains that line; its neighbor's clipped top or bottom fragment is discarded before
text merging. Horizontal fragments still merge by their text and geometry, and repeated lines at
different document positions remain distinct. This does not alter clipboard search-index extraction.

### Arrow and shape styles

Arrow annotations persist single, double, thick and open heads plus reversal. Missing styles retain
the previous open head. Shape style overrides the archived `filled` flag and supports outline, fill
and both; rounded rectangles clamp their radius to half the shorter edge. The desktop Style menu
and editor properties update the same annotation and undo history. Curved arrows expose a control
handle in Select mode, with a persisted rotation center so dragging does not shift the curve pivot.

### Rich text annotations

Text annotations optionally carry a `CaptureTextFormat`: a base style and up to 512 ordered UTF-16
runs whose endpoints must be complete character boundaries. Old annotations without it retain their
original renderer. TextKit edits local styles and typing attributes without committing the annotation;
formatting during composition waits for the marked text to commit. Text and supported styles enter
document undo together when editing finishes. Paste accepts RTF or plain text and normalizes supported
font families, colors and decorations; links and attachments are not persisted.

CoreText renders font traits, alignment, underline and outlines; run geometry provides background and
strikethrough. Reflected rich text is rasterized in bounded canonical blocks before reflection to avoid
CoreText re-hinting flipped glyphs. PNG bands include one row of overlap at each edge so outlined glyphs
agree with the full preview. Resizing a text annotation changes its wrapping bounds, preserving fonts.

### Censor

The annotation toolbar and All Tools expose one Censor menu containing Solid, Pixelate, Blur, Erase
and Text Only. Text Only runs the existing OCR review over the current composited output; users include
or exclude detected boxes before applying solid covers. Detection can miss text. Pixelate and Blur
are visual effects, not secure concealment. B/M/F/E retain their original tool meanings and documents
retain the original tool encodings. Saved toolbar entries for Pixelate, Blur and Erase become one
Censor entry at the first saved position; a visible member keeps that entry visible.

The composite reader applies opaque Solid and Erase masks before sharpening, blur and pixelation
sample pixels, preventing hidden source content from influencing neighboring output. The final
renderer also redraws these masks above annotations. Eyedropper, recognition, translation input and
export use the same composited renderer; source rasters remain editable inside local documents.

### Numbers and pen smoothing

Number annotations optionally persist a format and value (1–3999): decimal, Roman, uppercase letters
or lowercase letters. Letters continue with AA/aa after Z/z. The Next field sets the next value;
creating a number increments it, undoing that creation restores it, and reopening continues from the
last formatted number. Reaching 3999 requires choosing a new Next value before another number.
Legacy numbered annotations keep their original text and drawing. New labels fit and center in the badge.

Leader mode connects the badge to the dragged endpoint. Select exposes an independent endpoint handle;
the badge center remains the rotation pivot. Pen annotations optionally persist a Smooth flag: new
strokes default to quadratic midpoint curves, while missing flags retain the old polyline. The same
annotation renderer draws canvas previews and exported pixels; neither option rewrites source images.

### Text-line highlighting

Highlighter defaults to Freehand. Highlight Mode → Text Lines recognizes the current composited
output, then a horizontal or rectangular drag highlights the selected horizontal portion of every
intersected text line. The draft previews the same snapped annotations that will be committed.
Each line becomes an ordinary editable highlighter annotation, and the entire drag is one undo step.
No text produces a notice and leaves Freehand available; partial recognition is reported.

Recognition belongs to the current editor operation and checks cancellation, document identity and
revision before applying results. Its line cache advances through highlighter edits and undo/redo;
changes to geometry, image layers, adjustments, presentation or other annotations discard the cache
and return to Freehand. Undo does not resurrect discarded recognition. Re-enter Text Lines to
recognize the new composition. OCR coordinates and all export paths use document pixel coordinates.

### Presentation presets

Styling → Presets offers Gradient, Paper, Grid and Window. Applying a preset changes the existing
presentation parameters in one undo step; source pixels, annotation coordinates and editable layers
remain unchanged. Save Current Style opens an inline name field. Each saved preset can be applied,
replaced with the current style, or deleted. At most 20 named presets are stored, with validated
finite styling parameters. Names must be trimmed, 1–40 characters, and contain no control characters;
case-insensitive duplicate names and duplicate IDs are rejected without changing existing presets.

CaptureSettingsStore owns presets in the current bundle's preferences. `capture.presentationPresets`
mirrors the structured list in settings.json, and configuration backups carry the same typed presets.
Invalid imported lists leave saved presets unchanged. Existing document size limits also apply when
styling is applied. Selecting or moving an existing annotation preserves its stacking position;
a plain selection click creates no undo entry.

### Continuous scrolling controls

Scrolling uses the same frosted rounded surface, 30-point cells and optical glyph sizing as the
ordinary screenshot toolbar. Its compact row shows accumulated pixel dimensions, Auto Scroll,
Pause/Continue, Finish and More. The dimensions expose the current width and height in pixels
as their accessibility value. Preview/details remain optional, and errors or pauses expand
the explanation. Selection no longer displays a permanent “Drag to select” instruction.
The content region and mouse passthrough remain stable while the page scrolls.

Matching uses bounded five-row sampling and 5×5 averaged registration descriptors to tolerate
browser text rasterization differences. Fixed header/footer boundaries use original descriptors;
exported strips retain original pixels. The best 32 coarse candidates are verified densely; ambiguity is checked on local text blocks so
shared paragraph boilerplate does not hide distinguishing content. Flat whitespace is not a fixed
header/footer unless its color is distinct from the moving content background. Error ceilings and
ambiguity margins retain their numeric limits; obstruction checks remain unchanged.
