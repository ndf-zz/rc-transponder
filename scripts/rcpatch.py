#!/usr/bin/python3
# SPDX-License-Identifier: MIT
#
# usage: rcpatch firmware.hex
#
# Re-program an attached RC transponder with new firmware,
# retaining the original ID.
#
# Note: This script requires the new firmware to have an ID
# block structure (registers 0x040:0x05c) matching in
# the old firmware. If the ID block is not found, the script
# will abort with an error.
#
# ID block example, transponder ID=93388 (0x016ccc):
#
# 0198: 309c movlw 0x9c
# 0199: 008e movwf TMR1L ; reg: 0x00e
# 019a: 30ff movlw 0xff
# 019b: 008f movwf TMR1H ; reg: 0x00f
# 019c: 00a3 movwf 0x23 ; reg: 0x023
# 019d: 3001 movlw 0x01
# 019e: 00c2 movwf 0x42 ; reg: 0x042
# 019f: 306c movlw 0x6c
# 01a0: 00c1 movwf 0x41 ; reg: 0x041
# 01a1: 30cc movlw 0xcc
# 01a2: 00c0 movwf 0x40 ; reg: 0x040
# 01a3: 3000 movlw 0x00
# 01a4: 00c3 movwf 0x43 ; reg: 0x043
# 01a5: 3003 movlw 0x03
# 01a6: 00c4 movwf 0x44 ; reg: 0x044
# [...]
# 01d3: 3002 movlw 0x02
# 01d4: 00db movwf 0x5b ; reg: 0x05b
# 01d5: 3002 movlw 0x02
# 01d6: 00dc movwf 0x5c ; reg: 0x05c

import sys
import os
import shutil
import logging
import subprocess
from struct import unpack, pack
from tempfile import NamedTemporaryFile

OBJCOPY = 'objcopy'
IPECMD = 'ipecmd'
MPLABLOG = 'MPLABXLog.xml'
CONFIG = 0x28fa

_log = logging.getLogger('rcpatch')
_log.setLevel(logging.DEBUG)


def bintoihex(buf, width=16):
    """Convert buf to ihex, add config word and return as string."""
    c = 0
    olen = len(buf)
    ret = []
    while (c < olen):
        rem = olen - c
        if rem > width:
            rem = width
        sum = rem
        adr = c
        l = ':{0:02X}{1:04X}00'.format(rem, adr)  # rem < 0x10
        sum += ((adr >> 8) & 0xff) + (adr & 0xff)
        for j in range(0, rem):
            nb = buf[c + j]
            l += '{0:02X}'.format(nb)
            sum = (sum + nb) & 0xff
        l += '{0:02X}'.format((~sum + 1) & 0xff)
        ret.append(l)
        c += rem
    ret.append(':02400E00FA288E')  # Config
    ret.append(':00000001FF')  # EOF
    return '\n'.join(ret)


def find_idblock(fw):
    """Find ID block pattern in fw"""
    idx = None
    pat = (0x309c, 0x008e, 0x30ff, 0x008f, 0x00a3)
    i = 0
    j = 0
    while idx is None:
        try:
            k = fw.index(pat[j], i)
            if j > 0:
                if k - i == j:
                    j += 1
                    if j == len(pat):
                        idx = i
                else:
                    i += j
                    j = 0
            else:
                j = 1
                i = k
        except ValueError:
            break
    return idx


def main():
    logging.basicConfig()

    fwfile = None
    if len(sys.argv) == 2:
        if os.path.exists(sys.argv[1]):
            fwfile = os.path.realpath(sys.argv[1])
        else:
            print('Input firmware file not found')
            return -1
    else:
        print('Usage: rcpatch firmware.hex')
        return -1

    # check for required tools
    if shutil.which(OBJCOPY) is None:
        _log.error('Missing objcopy')
        return -1
    _log.debug('objcopy: OK')
    ipecmd = IPECMD
    if shutil.which(IPECMD) is None:
        # try same dir as this script
        ipecmd = os.path.join(os.path.dirname(os.path.realpath(__file__)),
                              IPECMD)
        if shutil.which(ipecmd) is None:
            _log.error('Missing ipecmd wrapper script')
            return -1
    _log.debug('ipecmd wrapper script: OK')

    tmpf = {}
    try:
        # read in new firmware
        tmpf['nbin'] = NamedTemporaryFile(suffix='.bin',
                                          prefix='t_',
                                          dir='.',
                                          delete=False)
        tmpf['nbin'].close()
        _log.debug('Loading firmware image into %s', tmpf['nbin'].name)
        subprocess.run(
            [OBJCOPY, '-Iihex', '-Obinary', fwfile, tmpf['nbin'].name],
            check=True)
        newbin = None
        with open(tmpf['nbin'].name, 'rb') as f:
            newbin = f.read(4096)
        newfw = list(unpack('<2048H', newbin))
        nidx = find_idblock(newfw)
        if nidx is None:
            raise RuntimeError('Firmware ID block not found')
        _log.debug('Found ID block at offset: 0x%03x', nidx)

        # Read transponder memory
        tmpf['thex'] = NamedTemporaryFile(suffix='.hex',
                                          prefix='t_',
                                          dir='.',
                                          delete=False)
        tmpf['thex'].close()
        _log.debug('Reading transponder into %s', tmpf['thex'].name)
        subprocess.run(
            [ipecmd, '-TPPK4', '-P16F639', '-GF' + tmpf['thex'].name],
            check=True)

        # objcopy hex to bin
        tmpf['tbin'] = NamedTemporaryFile(suffix='.bin',
                                          prefix='t_',
                                          dir='.',
                                          delete=False)
        tmpf['tbin'].close()
        _log.debug('Copying program binary to %s', tmpf['tbin'].name)
        subprocess.run([
            OBJCOPY, '-Iihex', '-Obinary',
            tmpf['thex'].name, tmpf['tbin'].name
        ],
                       check=True)

        # find original transponder id block
        origbin = None
        with open(tmpf['tbin'].name, 'rb') as f:
            origbin = f.read(4096)
        origfw = unpack('<2048H', origbin)
        idx = find_idblock(origfw)
        if idx is None:
            raise RuntimeError('Transponder ID block not found')
        _log.debug('Found ID block at offset: 0x%03x', idx)
        oid = origfw[idx + 9] & 0xff | ((origfw[idx + 7] & 0xff) << 8) | (
            (origfw[idx + 5] & 0xff) << 16)
        idblock = []
        j = 0
        while j < 58:
            idblock.append(origfw[idx + 5 + j] & 0xff)
            j += 2
        _log.debug('%d - %s', oid, bytes(idblock).hex())
        backupname = '%d_orig.hex' % (oid)
        if not os.path.exists(backupname):
            os.rename(tmpf['thex'].name, backupname)
            _log.debug('Saved original firmware to %s', backupname)

        # patch firmware image with transponder id block
        j = 0
        while j < 58:
            newfw[nidx + 5 + j] = origfw[idx + 5 + j]
            j += 2
        pbin = pack('<2048H', *newfw)
        tmpf['phex'] = NamedTemporaryFile(suffix='.hex',
                                          prefix='t_',
                                          mode='w',
                                          dir='.',
                                          delete=False)
        _log.debug('Copying patched binary to %s', tmpf['phex'].name)
        tmpf['phex'].write(bintoihex(pbin))
        tmpf['phex'].close()

        # Write patched firmware back to transponder
        subprocess.run(
            [ipecmd, '-TPPK4', '-P16F639', '-M', '-F' + tmpf['phex'].name],
            check=True)

    except Exception as e:
        _log.error('%s: %s', e.__class__.__name__, e)
        return -1
    finally:
        for t in tmpf:
            if os.path.exists(tmpf[t].name):
                os.unlink(tmpf[t].name)
                _log.debug('Removed %s: %s', t, tmpf[t].name)
        if os.path.exists(MPLABLOG):
            os.unlink(MPLABLOG)
    return 0


if __name__ == '__main__':
    sys.exit(main())
