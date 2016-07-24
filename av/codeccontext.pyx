from libc.stdint cimport uint8_t, int64_t
from libc.string cimport memcpy
from cpython cimport PyWeakref_NewRef

cimport libav as lib

from av.codec cimport Codec
from av.packet cimport Packet
from av.utils cimport err_check, avdict_to_dict, avrational_to_faction, to_avrational, media_type_to_string


cdef object _cinit_sentinel = object()


cdef Stream wrap_codec_context(lib.AVStream *c_ctx):
    """Build an av.CodecContext for an existing AVCodecContext."""
    
    cdef CodecContext py_ctx

    # TODO: This.
    # if c_stream.codec.codec_type == lib.AVMEDIA_TYPE_VIDEO:
    #    py_stream = VideoStream.__new__(VideoStream, _cinit_sentinel)
    # elif c_stream.codec.codec_type == lib.AVMEDIA_TYPE_AUDIO:
    #    py_stream = AudioStream.__new__(AudioStream, _cinit_sentinel)
    # elif c_stream.codec.codec_type == lib.AVMEDIA_TYPE_SUBTITLE:
    #     py_stream = SubtitleStream.__new__(SubtitleStream, _cinit_sentinel)
    # else:
    #     py_stream = Stream.__new__(Stream, _cinit_sentinel)

    py_ctx = CodecContext(_cinit_sentinel, None)
    py_ctx._init(c_ctx)
    return py_ctx


cdef class CodecContext(object):
    
    def __cinit__(self, name, mode=None):

        # Something else is constructing us.
        if name is _cinit_sentinel:
            return

        if isinstance(name, Codec):
            self.codec = name
        else:
            self.codec = Codec(name, mode)

    @property
    def is_open(self):
        return lib.avcodec_is_open(self.ptr)

    def open(self):

        if lib.avcodec_is_open(self.ptr):
            raise ValueError('is already open')

        # TODO: Options
        err_check(lib.avcodec_open2(self.ptr, self.codec.ptr))

    def __dealloc__(self):
        if self.ptr:
            lib.avcodec_close(self.ptr)

    def __repr__(self):
        return '<av.%s #%d %s/%s at 0x%x>' % (
            self.__class__.__name__,
            self.type or '<notype>',
            self.name or '<nocodec>',
            id(self),
        )

    property type:
        def __get__(self): return media_type_to_string(self.ptr.codec_type)

    property name:
        def __get__(self):
            return self.codec.ptr.name if self.codec.ptr else None

    property long_name:
        def __get__(self):
            return self.codec.ptr.long_name if self.codec.ptr else None
    
    property profile:
        def __get__(self):
            if self.codec.ptr and lib.av_get_profile_name(self.codec.ptr, self.ptr.profile):
                return lib.av_get_profile_name(self.codec.ptr, self.ptr.profile)
            else:
                return None

    property time_base:
        def __get__(self):
            return avrational_to_faction(&self.ptr.time_base)

    property rate:
        def __get__(self): 
            return self.ptr.ticks_per_frame * avrational_to_faction(&self.ptr.time_base)

    property bit_rate:
        def __get__(self):
            return self.ptr.bit_rate if self.ptr and self.ptr.bit_rate > 0 else None
        def __set__(self, int value):
            self.ptr.bit_rate = value

    property max_bit_rate:
        def __get__(self):
            if self.ptr and self.ptr.rc_max_rate > 0:
                return self.ptr.rc_max_rate
            else:
                return None
            
    property bit_rate_tolerance:
        def __get__(self):
            return self.ptr.bit_rate_tolerance if self.ptr else None
        def __set__(self, int value):
            self.ptr.bit_rate_tolerance = value

    # TODO: Does it conceptually make sense that this is on streams, instead
    # of on the container?
    property thread_count:
        def __get__(self):
            return self.ptr.thread_count
        def __set__(self, int value):
            self.ptr.thread_count = value

    cpdef decode(self, Packet packet, int count=0):
        """Decode a list of :class:`.Frame` from the given :class:`.Packet`.

        If the packet is None, the buffers will be flushed. This is useful if
        you do not want the library to automatically re-order frames for you
        (if they are encoded with a codec that has B-frames).

        """

        if packet is None:
            raise TypeError('packet must not be None')

        if not self.codec.ptr:
            raise ValueError('cannot decode unknown codec')

        cdef int data_consumed = 0
        cdef list decoded_objs = []

        cdef uint8_t *original_data = packet.struct.data
        cdef int      original_size = packet.struct.size

        cdef bint is_flushing = not (packet.struct.data and packet.struct.size)

        # Keep decoding while there is data.
        while is_flushing or packet.struct.size > 0:

            if is_flushing:
                packet.struct.data = NULL
                packet.struct.size = 0

            decoded = self._decode_one(&packet.struct, &data_consumed)
            packet.struct.data += data_consumed
            packet.struct.size -= data_consumed

            if decoded:

                if isinstance(decoded, Frame):
                    self._setup_frame(decoded)
                decoded_objs.append(decoded)

                # Sometimes we will error if we try to flush the stream
                # (e.g. MJPEG webcam streams), and so we must be able to
                # bail after the first, even though buffers may build up.
                if count and len(decoded_objs) >= count:
                    break

            # Sometimes there are no frames, and no data is consumed, and this
            # is ok. However, no more frames are going to be pulled out of here.
            # (It is possible for data to not be consumed as long as there are
            # frames, e.g. during flushing.)
            elif not data_consumed:
                break

        # Restore the packet.
        packet.struct.data = original_data
        packet.struct.size = original_size

        return decoded_objs
    
 
    cdef _decode_one(self, lib.AVPacket *packet, int *data_consumed):
        raise NotImplementedError('base stream cannot decode packets')
# 
