from libc.stdint cimport uint8_t, int64_t
from libc.string cimport memcpy
from cpython cimport PyWeakref_NewRef

cimport libav as lib

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

    py_ctx = CodecContext(_cinit_sentinel)
    py_ctx._init(c_ctx)
    return py_ctx


cdef class CodecContext(object):
    
    def __cinit__(self, name):
        if name is _cinit_sentinel:
            return
        raise RuntimeError('cannot manually instatiate CodecContext')

    cdef _init(self, lib.AVCodecContext *ptr):
        
        self._ptr = ptr
        
        if True: # TODO: Is this an input?!

            # Find the codec.
            self._codec = lib.avcodec_find_decoder(self._ptr.codec_id)
            if self._codec == NULL:
                return
            
            # Open the codec.
            try:
                err_check(lib.avcodec_open2(self._ptr, self._codec, &self._codec_options))
            except:
                # Signal that we don't need to close it.
                self._codec = NULL
                raise
            
        # This is an output container!
        else:
            self._codec = self._ptr.codec

    def __dealloc__(self):
        if self._ptr:
            lib.avcodec_close(self._ptr)

    def __repr__(self):
        return '<av.%s #%d %s/%s at 0x%x>' % (
            self.__class__.__name__,
            self.type or '<notype>',
            self.name or '<nocodec>',
            id(self),
        )

    property type:
        def __get__(self): return media_type_to_string(self._ptr.codec_type)

    property name:
        def __get__(self):
            return self._codec.name if self._codec else None

    property long_name:
        def __get__(self):
            return self._codec.long_name if self._codec else None
    
    property profile:
        def __get__(self):
            if self._codec and lib.av_get_profile_name(self._codec, self._ptr.profile):
                return lib.av_get_profile_name(self._codec, self._ptr.profile)
            else:
                return None

    property time_base:
        def __get__(self):
            return avrational_to_faction(&self._ptr.time_base)

    property rate:
        def __get__(self): 
            return self._ptr.ticks_per_frame * avrational_to_faction(&self._ptr.time_base)

    property bit_rate:
        def __get__(self):
            return self._ptr.bit_rate if self._ptr and self._ptr.bit_rate > 0 else None
        def __set__(self, int value):
            self._ptr.bit_rate = value

    property max_bit_rate:
        def __get__(self):
            if self._ptr and self._ptr.rc_max_rate > 0:
                return self._ptr.rc_max_rate
            else:
                return None
            
    property bit_rate_tolerance:
        def __get__(self):
            return self._ptr.bit_rate_tolerance if self._ptr else None
        def __set__(self, int value):
            self._ptr.bit_rate_tolerance = value

    # TODO: Does it conceptually make sense that this is on streams, instead
    # of on the container?
    property thread_count:
        def __get__(self):
            return self._ptr.thread_count
        def __set__(self, int value):
            self._ptr.thread_count = value

    cpdef decode(self, Packet packet, int count=0):
        """Decode a list of :class:`.Frame` from the given :class:`.Packet`.

        If the packet is None, the buffers will be flushed. This is useful if
        you do not want the library to automatically re-order frames for you
        (if they are encoded with a codec that has B-frames).

        """

        if packet is None:
            raise TypeError('packet must not be None')

        if not self._codec:
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
