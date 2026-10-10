import struct
import zlib
from pathlib import Path

root = Path(__file__).resolve().parent.parent / 'Tests/Fixtures/capture/png-filters'
root.mkdir(exist_ok=True)


def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))


for kind, channels in [(0, 1), (2, 3), (4, 2), (6, 4)]:
    for first in range(5):
        scanlines = []
        previous = [0] * (17 * channels)
        for y in range(10):
            row = [(x * 67 + y * 31 + c * 43) % 256 for x in range(17) for c in range(channels)]
            filtering = (y + first) % 5
            encoded = []
            for index, value in enumerate(row):
                left = row[index - channels] if index >= channels else 0
                above = previous[index]
                corner = previous[index - channels] if index >= channels else 0
                prediction = left + above - corner
                distances = [abs(prediction - candidate) for candidate in [left, above, corner]]
                paeth = [left, above, corner][distances.index(min(distances))]
                predictor = [0, left, above, (left + above) // 2, paeth][filtering]
                encoded.append((value - predictor) % 256)
            scanlines.extend([filtering] + encoded)
            previous = row
        header = struct.pack('>IIBBBBB', 17, 10, 8, kind, 0, 0, 0)
        image = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header)
        image += chunk(b'IDAT', zlib.compress(bytes(scanlines))) + chunk(b'IEND', b'')
        (root / f'{kind}-{first}.png').write_bytes(image)
