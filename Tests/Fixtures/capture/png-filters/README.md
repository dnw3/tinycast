# PNG scanline fixtures

Generated locally by `python3 Scripts/gen-capture-png-fixtures.py`; no external images or libraries.
The filename is PNG color type followed by the first row's filter. Each 17 × 10 image rotates all five
PNG filters and covers grayscale, grayscale with alpha, RGB, or RGBA at 8 bits. Source components follow
`(x * 67 + y * 31 + channel * 43) % 256`, including nonopaque alpha. `capture-raster-test` decodes every
pixel through the shipped streaming reader and compares it against this source formula.
