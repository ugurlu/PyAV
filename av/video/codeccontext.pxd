
from av.codeccontext cimport CodecContext
from av.video.reformatter cimport VideoReformatter


cdef class VideoCodecContext(CodecContext):

    cdef readonly VideoReformatter reformatter
