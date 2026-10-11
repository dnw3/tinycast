# Fixed header browser regression

Anonymous local fixture: `docs/plans/capture-evidence/scroll-acceptance-fixture-20261011.html`.
Captured on 2026-10-11 through the in-app browser at 1138 × 932 pixels, before and after
scrolling down approximately 280 pixels. Both frames have the same 64-pixel fixed header.
These are browser-rendered screenshots, containing no user conversation or account content.

The test exercises the shipped frame reader, confidence policy, reverse/duplicate rejection,
and byte-exact exported strips. It also checks crops excluding the left gutter and fixed header,
where sparse sampling could confuse similar paragraphs or mistake whitespace for a fixed footer. The differing text antialiasing reproduced an uncertain match
that kept only the first frame. This fixture does not prove native ScreenCaptureKit delivery,
window visibility, mouse passthrough, or whole-session resource acceptance.
