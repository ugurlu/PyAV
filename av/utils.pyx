from libc.stdint cimport int64_t, uint8_t, uint64_t

from fractions import Fraction
from threading import local
import sys
import traceback
import os

cimport libav as lib


# === ERROR HANDLING ===
# ======================

# Would love to use the built-in constant, but it doesn't appear to
# exist on Travis, or my Linux workstation. Could this be because they
# are actually libav?
cdef int AV_ERROR_MAX_STRING_SIZE = 64

# Our custom error.
cdef int PYAV_ERROR = -0x50794156 # 'PyAV'


class AVError(EnvironmentError):
    """Exception class for errors from within the underlying FFmpeg/Libav."""
    pass
AVError.__module__ = 'av'


cdef object _local = local()
cdef int _err_count = 0

cdef int stash_exception(exc_info=None):

    global _err_count

    existing = getattr(_local, 'exc_info', None)
    if existing is not None:
        print >> sys.stderr, 'PyAV library exception being dropped:'
        traceback.print_exception(*existing)
        _err_count -= 1

    exc_info = exc_info or sys.exc_info()
    _local.exc_info = exc_info
    if exc_info:
        _err_count += 1

    return PYAV_ERROR


cdef int err_check(int res=0, str filename=None) except -1:

    # global _err_count
    #
    # # Check for stashed exceptions.
    # if _err_count:
    #     exc_info = getattr(_local, 'exc_info', None)
    #     if exc_info is not None:
    #         _err_count -= 1
    #         _local.exc_info = None
    #         raise exc_info[0], exc_info[1], exc_info[2]

    # cdef bytes py_buffer
    # cdef char *c_buffer
    if res < 0:

        raise AVError(-res, 'error')
        #
        # if res == PYAV_ERROR:
        #     py_buffer = b'Error in PyAV callback'
        # else:
        #     # This is kinda gross.
        #     py_buffer = b"\0" * AV_ERROR_MAX_STRING_SIZE
        #     c_buffer = py_buffer
        #     lib.av_strerror(res, c_buffer, AV_ERROR_MAX_STRING_SIZE)
        #     py_buffer = c_buffer
        #
        # if filename:
        #     raise AVError(-res, py_buffer.decode('latin1'), filename)
        # else:
        #     raise AVError(-res, py_buffer.decode('latin1'))

    return res



# === DICTIONARIES ===
# ====================


cdef dict avdict_to_dict(lib.AVDictionary *input):

    cdef lib.AVDictionaryEntry *element = NULL
    cdef dict output = {}
    while True:
        element = lib.av_dict_get(input, "", element, lib.AV_DICT_IGNORE_SUFFIX)
        if element == NULL:
            break
        output[element.key] = element.value
    return output


cdef dict_to_avdict(lib.AVDictionary **dst, dict src, bint clear=True):
    if clear:
        lib.av_dict_free(dst)
    for key, value in src.iteritems():
        err_check(lib.av_dict_set(dst, key, value, 0))



# === FRACTIONS ===
# =================

cdef object avrational_to_faction(lib.AVRational *input):
    return Fraction(input.num, input.den) if input.den else Fraction(0, 1)


cdef object to_avrational(object value, lib.AVRational *input):

    if isinstance(value, Fraction):
        frac = value
    else:
        frac = Fraction(value)

    input.num = frac.numerator
    input.den = frac.denominator


cdef object av_frac_to_fraction(lib.AVFrac *input):
    return Fraction(input.val * input.num, input.den)



# === OTHER ===
# =============

cdef str media_type_to_string(lib.AVMediaType media_type):

    # There is a convenient lib.av_get_media_type_string(x), but it
    # doesn't exist in libav.

    if media_type == lib.AVMEDIA_TYPE_VIDEO:
        return "video"
    elif media_type == lib.AVMEDIA_TYPE_AUDIO:
        return "audio"
    elif media_type == lib.AVMEDIA_TYPE_DATA:
        return "data"
    elif media_type == lib.AVMEDIA_TYPE_SUBTITLE:
        return "subtitle"
    elif media_type == lib.AVMEDIA_TYPE_ATTACHMENT:
        return "attachment"
    else:
        return "unknown"




# === DEBUGGING ===
# =================

cdef bint debug = bool(os.environ.get('PYAV_DEBUG'))
cdef int _last_mem = 0

cdef void _debug_add_to_stack(int delta):
    _seen = set()
    for name in _stack:
        if name in _seen:
            continue
        _seen.add(name)
        _data[name]['cmem'] += delta

cdef int _debug_mem_delta():
    global _last_mem
    cdef int mem = _proc.memory_info().rss
    cdef int delta = mem - _last_mem
    _last_mem = mem
    return delta

cdef void debug_enter(str name):
    if not debug:
        return
    delta = _debug_mem_delta()
    _data.setdefault(name, {'mem': 0, 'cmem': 0, 'num': 0})
    _data[name]['num'] += 1
    _debug_add_to_stack(delta)
    _stack.append(name)

def _debug_enter(name):
    debug_enter(name)

cdef void debug_exit():
    if not debug:
        return
    delta = _debug_mem_delta()
    _debug_add_to_stack(delta)
    name = _stack.pop()
    _data[name]['mem'] += delta

def _debug_exit():
    debug_exit()

def debug_report():
    import csv
    import sys

    path = os.environ['PYAV_DEBUG'].strip()
    fh = sys.stdout if path == '-' else open(path, 'w')
    def writerow(row):
        fh.write('%-40s, %4s, %9s, %12s, %9s\n' % row)
        fh.flush()
    writerow(('section', 'num', 'cum_mem', 'avg_mem', 'mem'))
    for name, data in sorted(_data.iteritems()):
        writerow((
            name,
            data['num'],
            data['cmem'],
            '%.1f' % (float(data['mem']) / data['num']),
            data['mem'],
        ))

if debug:
    import atexit
    import psutil
    _proc = psutil.Process()
    _data = {}
    _stack = []
    atexit.register(debug_report)
