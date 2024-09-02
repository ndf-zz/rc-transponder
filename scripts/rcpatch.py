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

# Set POWER=True to power device from pickit programmer.
# This option is required for programming ID Locations
#
# Warning: Remove battery before powering device from programmer
POWER = True
IPEARGS = ('-TPPK4', '-P16F639')

_log = logging.getLogger('rcpatch')
_log.setLevel(logging.DEBUG)


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


def pic_hex(program=None, config_word=None, idlocations=None):
    """Return pic hex image for the provided sections"""
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
        _log.debug('Reading new firmware image')
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
        _log.debug('ID Locations: %s', ', '.join((hex(w) for w in new_idl)))
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
        orig_idx = find_idblock(orig_prog)
        if orig_idx is None:
            raise RuntimeError('Target ID block not found')
        _log.debug('Target ID block offset: 0x%04x', orig_idx)
        orig_id = orig_prog[orig_idx + 9] & 0xff
        orig_id |= ((orig_prog[orig_idx + 7] & 0xff) << 8)
        orig_id |= ((orig_prog[orig_idx + 5] & 0xff) << 16)
        idblock = []
        j = 0
        while j < 58:
            idblock.append(orig_prog[orig_idx + 5 + j] & 0xff)
            j += 2
        _log.debug('%d - %s', orig_id, bytes(idblock).hex())
        backupname = '%d_orig.hex' % (orig_id)
        if not os.path.exists(backupname):
            os.rename(tmpf['thex'].name, backupname)
            _log.debug('Saved original firmware to %s', backupname)

        # patch firmware image with transponder id block
        _log.debug('Patching ID block 0x%04x->0x%04x', orig_idx, new_idx)
        j = 0
        while j < 58:
            new_prog[new_idx + 5 + j] = orig_prog[orig_idx + 5 + j]
            j += 2
        tmpf['phex'] = NamedTemporaryFile(suffix='.hex',
                                          prefix='t_',
                                          mode='w',
                                          dir='.',
                                          delete=False)
        tmpf['phex'].write(pic_hex(new_prog, new_cfg, new_idl))
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
