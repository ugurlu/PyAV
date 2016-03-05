#!/usr/bin/env python

import os
import av
import time
import StringIO
import resource
import sys

fh = open('big_file.mpeg', 'r')

class MyBuffer(list):

    def read(self, n):
        print '    read(%d)' % n
        if not self:
            return ''
        if n < len(self[0]):
            ret = self[0][:n]
            self[0] = self[0][n:]
            return ret
        else:
            return self.pop(0)
        return fh.read(buf)

buf = MyBuffer()
buf.append(fh.read(4096))
container = av.open(buf, options=dict(bufsize='4096', seekable='', skip_stream_info='True'))

def get_frames(x):
    buf.append(x)
    ret = []
    for packet in container.demux(video=0):
        for frame in packet.decode():
            ret.append(frame)
    return ret

print get_frames(fh.read(4096))
print get_frames(fh.read(4096))
print get_frames(fh.read(4096))
print get_frames(fh.read(4096))
print get_frames(fh.read(4096))
print get_frames(fh.read(4096))
print get_frames(fh.read(4096))
print get_frames(fh.read(4096))
print get_frames(fh.read(4096))
print get_frames(fh.read(4096))
print get_frames(fh.read(4096))
