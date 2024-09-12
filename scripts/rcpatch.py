#!/usr/bin/python3
# SPDX-License-Identifier: MIT
#
# usage: rcpatch firmware.hex [idno]
#
# Re-program an attached RC transponder with new firmware,
# and the ID number provided. If ID is omitted, use
# ID from existing firmware or a randomly chosen ID between
# 65536 and 131072.
#
# Note: This script generates the ID block and patches the
# firmware before writing. If an ID block is not found in
# the new firmware image, the script will abort with an error.
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
from secrets import randbits

OBJCOPY = 'objcopy'
IPECMD = 'ipecmd'
MPLABLOG = 'MPLABXLog.xml'

# Set POWER=True to power device from pickit programmer.
# This option is required for programming ID Locations
POWER = True
IPEARGS = ('-TPPK4', '-P16F639')

_log = logging.getLogger('rcpatch')
_log.setLevel(logging.DEBUG)


def _reflect(dat, width):
    """Reverse bit order of byte"""
    out = dat & 0x01
    for i in range(width - 1):
        dat >>= 1
        out = (out << 1) | (dat & 0x01)
    return out


# Build a lookup table for the MCRF4XX CRC
# Source: pycrc https://pycrc.org/
_MCRF4XXTBL = [0] * 256
for i in range(256):
    r = i
    r = _reflect(r, 8) << 8
    for j in range(8):
        if r & 0x8000 != 0:
            r = (r << 1) ^ 0x1021
        else:
            r = (r << 1)
    r = _reflect(r, 16)
    _MCRF4XXTBL[i] = r & 0xffff


def mcrf4xx(msgstr=b''):
    """Return MCRF4XX CRC for provided byte string."""
    r = 0xffff  # _reflect(0xffff,16) == 0xffff
    for b in msgstr:
        i = (r ^ b) & 0xff
        r = ((r >> 8) ^ _MCRF4XXTBL[i]) & 0xffff
    return r & 0xffff  # collapse two reflects, mask and ^0


def idcrc4(idno):
    """Return 4 bit CRC on the id number, long-division method"""
    # re-arrange nibbles as they are delivered
    r = ((idno & 0xff) << 16) | (idno & 0xff00) | ((idno & 0xf0000) >> 12)
    # use 0b10001 as divisor, left aligned
    d = 0x880000
    m = 0x800000
    count = 0
    while r & 0xfffff0:
        if r & m:
            r = r ^ d
        else:
            d >>= 1
            m >>= 1
    return r & 0xf


def idtoken(bitval):
    """Return encoded 2 bit value"""
    return 2 + (bitval & 0x3)


def genid(idno):
    """Return an id block for the provided idno"""
    crc4 = idcrc4(idno)
    idbytes = pack('>L', idno)[1:]
    crc = mcrf4xx(idbytes)
    idblock = [idbytes[0], idbytes[1], idbytes[2], 0, 3, 4, 7]
    for bv in ((crc >> 8) & 0xff, idbytes[2], crc & 0xff, idbytes[1],
               (idbytes[0] << 4) | (crc4 & 0xf)):
        idblock.append(idtoken(bv >> 6))
        idblock.append(idtoken(bv >> 4))
        idblock.append(idtoken(bv >> 2))
        idblock.append(idtoken(bv))
    idblock.extend((3, 2))
    return idblock


def ihexline(address, record, buf):
    """Return intel hex encoded record for the provided buffer"""
    addr = pack('>H', address)
    sum = len(buf) + record
    for b in addr:
        sum += b
    for b in buf:
        sum += b
    sum = (~(sum & 0xff) + 1) & 0xff
    return ':%02X%s%02X%s%02X' % (len(buf), addr.hex().upper(), record,
                                  buf.hex().upper(), sum)


def prog_to_ihex(program):
    """Yield intel hex encoded lines for provided program words"""
    plen = len(program)
    count = 0
    stride = 0x8
    while count < plen:
        linelen = min(stride, plen - count)
        buf = pack('<%dH' % (linelen), *program[count:count + linelen])
        yield (ihexline(count << 1, 0, buf))
        count += linelen


def pic16f639_hex(program=None, config_word=None, idlocations=None):
    """Return pic16f639 hex image for the provided sections"""
    ret = []

    # prepend the extended linear address
    ret.append(ihexline(0, 0x04, b'\x00\x00'))

    if program is not None:
        for l in prog_to_ihex(program):
            ret.append(l)
    if config_word is not None:
        ret.append(ihexline(0x400e, 0, pack('<H', config_word)))
    if idlocations is not None:
        ret.append(ihexline(0x4000, 0, pack('<4H', *idlocations)))

    # append EOF
    ret.append(ihexline(0, 1, b''))
    return '\n'.join(ret)


def find_idblock(fw):
    """Find ID block pattern in fw"""
    idx = None
    pat = (0x00c2, 0x00c1, 0x00c0, 0x00c3, 0x00c4)
    i = 0
    j = 0
    while idx is None:
        try:
            k = fw.index(pat[j], i)
            if j > 0:
                if k - i == (2 * j):
                    j += 1
                    if j == len(pat):
                        idx = i - 1
                else:
                    i += (2 * j)
                    j = 0
            else:
                j = 1
                i = k
        except ValueError:
            break
    return idx


def read_idlocs(idlocs):
    """Return string version of IDlocs if programmed"""
    unprogrammed = True
    bv = []
    for i in range(4):
        if idlocs[i] != 0x3fff:
            unprogrammed = False
        bv.append((idlocs[i] >> 7) & 0x7f)
        bv.append(idlocs[i] & 0x7f)
    if unprogrammed:
        return '[unprogrammed]'
    else:
        return bytes(bv).decode('ascii', 'replace')


def main():
    logging.basicConfig()

    fwfile = None
    idno = None
    if len(sys.argv) == 3:
        try:
            idno = int(sys.argv[2], base=0)
            maskid = idno & 0xfffff
            if maskid != idno:
                idno = maskid
                _log.warning('ID number truncated to %d (0x%05x)', idno, idno)
        except Exception as e:
            pass
        if idno is None:
            print('Usage: rcpatch firmware.hex [idno]')
            return -1

    if len(sys.argv) >= 2:
        if os.path.exists(sys.argv[1]):
            fwfile = os.path.realpath(sys.argv[1])
        else:
            print('Firmware image file not found')
            return -1
    else:
        print('Usage: rcpatch firmware.hex [idno]')
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
        # read in firmware image
        tmpf['nbin'] = NamedTemporaryFile(suffix='.bin',
                                          prefix='t_',
                                          dir='.',
                                          delete=False)
        tmpf['nbin'].close()
        _log.debug('Reading firmware image')
        subprocess.run(
            (OBJCOPY, '-Iihex', '-Obinary', fwfile, tmpf['nbin'].name),
            check=True,
            capture_output=True)
        new_bin = None
        with open(tmpf['nbin'].name, 'rb') as f:
            new_bin = f.read()
        new_prog = list(unpack('<2048H', new_bin[0:0x1000]))
        new_cfg = unpack('<H', new_bin[0x400e:0x4010])[0]
        new_idl = unpack('<4H', new_bin[0x4000:0x4008])
        _log.debug('Configuration Word = 0x%04x', new_cfg)
        _log.debug('ID Locations: %r (%s)', read_idlocs(new_idl), ', '.join(
            (hex(w) for w in new_idl)))
        new_idx = find_idblock(new_prog)
        if new_idx is None:
            raise RuntimeError('Firmware ID block not found')
        _log.debug('Firmware ID block offset: 0x%04x', new_idx)

        # Read target transponder memory
        tmpf['thex'] = NamedTemporaryFile(suffix='.hex',
                                          prefix='t_',
                                          dir='.',
                                          delete=False)
        tmpf['thex'].close()
        _log.debug('Reading old firmware from target')
        ipeargs = [ipecmd]
        ipeargs.extend(IPEARGS)
        if POWER:
            ipeargs.append('-W')
        ipeargs.append('-GF' + tmpf['thex'].name)
        subprocess.run(ipeargs, check=True, capture_output=True)

        # objcopy hex to bin
        tmpf['tbin'] = NamedTemporaryFile(suffix='.bin',
                                          prefix='t_',
                                          dir='.',
                                          delete=False)
        tmpf['tbin'].close()
        subprocess.run((OBJCOPY, '-Iihex', '-Obinary', tmpf['thex'].name,
                        tmpf['tbin'].name),
                       check=True,
                       capture_output=True)

        # find original transponder id block
        orig_bin = None
        with open(tmpf['tbin'].name, 'rb') as f:
            orig_bin = f.read()
        orig_prog = unpack('<2048H', orig_bin[0:0x1000])
        orig_idl = unpack('<4H', orig_bin[0x4000:0x4008])
        _log.debug('ID Locations: %r (%s)', read_idlocs(orig_idl), ', '.join(
            (hex(w) for w in orig_idl)))
        orig_idno = None
        orig_idx = find_idblock(orig_prog)
        if orig_idx is not None:
            _log.debug('Target ID block offset: 0x%04x', orig_idx)
            orig_idno = orig_prog[orig_idx + 4] & 0xff
            orig_idno |= ((orig_prog[orig_idx + 2] & 0xff) << 8)
            orig_idno |= ((orig_prog[orig_idx] & 0xff) << 16)
            _log.debug('Target old ID: %d (0x%05x)', orig_idno, orig_idno)
        else:
            _log.warning('Target ID block not found')

        # Backup old firmware
        if orig_idno is not None:
            backupname = '%d_orig.hex' % (orig_idno)
            if not os.path.exists(backupname):
                os.rename(tmpf['thex'].name, backupname)
                _log.debug('Saved original firmware to %s', backupname)

        # Prepare new ID block
        if idno is None:
            idno = orig_idno
        if idno is None:
            _log.debug('Using random ID')
            idno = 0x10000 + randbits(16)

        _log.debug('Creating new ID: %d (0x%05x)', idno, idno)
        idblock = genid(idno)
        _log.debug('%d - %s', idno, bytes(idblock).hex())

        # patch firmware image with transponder id block
        _log.debug('Patching ID block @ 0x%04x', new_idx)
        i = 0
        for sym in idblock:
            # clear bits
            new_prog[new_idx + i] &= 0xff00
            # copy in new bits
            new_prog[new_idx + i] |= sym
            i += 2
        tmpf['phex'] = NamedTemporaryFile(suffix='.hex',
                                          prefix='t_',
                                          mode='w',
                                          dir='.',
                                          delete=False)
        tmpf['phex'].write(pic16f639_hex(new_prog, new_cfg, new_idl))
        tmpf['phex'].close()

        # Write patched firmware back to transponder
        ipeargs = [ipecmd]
        ipeargs.extend(IPEARGS)
        if POWER:
            ipeargs.append('-W')
        ipeargs.extend(('-M', '-F' + tmpf['phex'].name))
        _log.debug('Writing new firmware to target')
        subprocess.run(ipeargs, check=True, capture_output=True)

    except subprocess.CalledProcessError as e:
        _log.debug('Error running command %s (%d), Output: \n%s', e.cmd,
                   e.returncode, e.output.decode('utf-8', 'replace'))
        _log.error('Update aborted')
        return -2
    except Exception as e:
        _log.debug('%s: %s', e.__class__.__name__, e)
        _log.error('Update aborted')
        return -1
    finally:
        for t in tmpf:
            if os.path.exists(tmpf[t].name):
                os.unlink(tmpf[t].name)
                _log.debug('Remove temp file %s', t)
        if os.path.exists(MPLABLOG):
            _log.debug('Remove MPLAB log')
            os.unlink(MPLABLOG)
    _log.info('Target updated OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
