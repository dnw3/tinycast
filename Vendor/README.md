# Capture WebP dependency

The user approved an exception to the zero-dependency rule on 2026-09-29 for WebP export.
`libwebp/` contains unmodified source from the official libwebp 1.6.0 release:

- Source: https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz
- SHA-256: `e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564`
- Preserved directories: `src`, `sharpyuv`; preserved COPYING, PATENTS, AUTHORS, README.md, ChangeLog.
- `CaptureWebP/module.modulemap` is Tinycast's small module boundary, exposing encoding and mux APIs.

The XcodeGen static target and standalone harness build both compile enc/dec/dsp/utils/mux plus sharpyuv,
excluding animation encoding and demux. Official mux requires codec header readers from the decoder
sources; Tinycast does not call libwebp to decode imported images. No tools, external binaries, Swift
package wrappers, runtime downloads or network access are needed to build or use this vendored library.
The app bundles its own small `CaptureWebPHelper`, linked to this static library. One process encodes each
explicit WebP save and exits; no separately installed codec or persistent daemon is required.

The C target uses O2 in Debug and Release. Xcode's optional conditional-uninitialized warning is disabled
only for this upstream target: dec_neon.c consumes sum_top/sum_left under the same flags that initialize
them; backward_references_enc.c assigns best_offset in either the existing-match branch or do_compute.
Ordinary uninitialized warnings and all application Swift checks remain enabled.

Update by replacing these upstream files from a verified official release, updating the version/hash
here, and running image pixel, cancellation, memory, Debug/Release and signing checks. Do not patch
vendor files to silence a local diagnostic; change Tinycast's integration or adopt an upstream fix.
Git whitespace checks exclude only `Vendor/libwebp/` so its upstream bytes stay unchanged.
