#!/usr/bin/env python3
#
# Pack a NAND page directory (nand/cs<N>/<page>.page) into the flat image
# format read by hw/arm/ipod_touch_fmss.c. With a flat image the guest's
# writes to the NAND are saved, so the iPod keeps its changes across reboots.
#
# Usage: python3 nand-to-image.py <nand dir> <image>
#
# Layout (see include/hw/arm/ipod_touch_fmss.h):
#   records  (cs * NAND_PAGES_PER_CS + page) * 4160: 4096 data + 64 spare bytes,
#            the contents of the matching .page file
#   bitmap   at NAND_IMAGE_RECORD_AREA, one bit per record (LSB first), set
#            for pages that exist; clear pages read as erased
#   lmap     logical-page map, all zero (no logical identities yet)
# The file is sparse: about 8.7 GB long, but only the pages take disk space.
# The emulator appends the logical-page area behind it as the guest writes.

import os
import re
import sys

NAND_BYTES_PER_RECORD = 4096 + 64
NAND_PAGES_PER_CS = 4096 * 128          # blocks per CS * pages per block
NAND_NUM_CS = 4
NAND_IMAGE_RECORD_AREA = NAND_NUM_CS * NAND_PAGES_PER_CS * NAND_BYTES_PER_RECORD
NAND_IMAGE_BITMAP_LEN = NAND_NUM_CS * NAND_PAGES_PER_CS // 8
NAND_IMAGE_LMAP_OFF = NAND_IMAGE_RECORD_AREA + NAND_IMAGE_BITMAP_LEN
NAND_IMAGE_LMAP_LEN = NAND_NUM_CS * NAND_PAGES_PER_CS * 4
NAND_IMAGE_LOGICAL_AREA = NAND_IMAGE_LMAP_OFF + NAND_IMAGE_LMAP_LEN

PAGE_RE = re.compile(r'^(\d+)\.page$')


def pack(nand_dir, image):
    bitmap = bytearray(NAND_IMAGE_BITMAP_LEN)
    count = 0
    tmp = image + '.part'

    with open(tmp, 'wb') as out:
        for cs in range(NAND_NUM_CS):
            cs_dir = os.path.join(nand_dir, 'cs%d' % cs)
            if not os.path.isdir(cs_dir):
                continue
            for name in os.listdir(cs_dir):
                m = PAGE_RE.match(name)
                if not m:
                    continue
                page = int(m.group(1))
                if page >= NAND_PAGES_PER_CS:
                    sys.exit('error: %s: page %d is beyond the %d pages per CS the image models'
                             % (cs_dir, page, NAND_PAGES_PER_CS))
                with open(os.path.join(cs_dir, name), 'rb') as f:
                    data = f.read(NAND_BYTES_PER_RECORD)
                if len(data) != NAND_BYTES_PER_RECORD:
                    sys.exit('error: %s/%s is %d bytes, expected %d'
                             % (cs_dir, name, len(data), NAND_BYTES_PER_RECORD))
                rec = cs * NAND_PAGES_PER_CS + page
                out.seek(rec * NAND_BYTES_PER_RECORD)
                out.write(data)
                bitmap[rec >> 3] |= 1 << (rec & 7)
                count += 1

        if count == 0:
            sys.exit('error: no cs<N>/<page>.page files in %s' % nand_dir)

        out.seek(NAND_IMAGE_RECORD_AREA)
        out.write(bitmap)
        out.truncate(NAND_IMAGE_LOGICAL_AREA)

    os.replace(tmp, image)
    return count


def main():
    if len(sys.argv) != 3:
        sys.exit('usage: %s <nand dir> <image>' % sys.argv[0])
    count = pack(sys.argv[1], sys.argv[2])
    print('packed %d pages into %s' % (count, sys.argv[2]))


if __name__ == '__main__':
    main()
