#!/usr/bin/env python

import os
import av
import time
import StringIO
import resource
import sys

class myStringIO(StringIO.StringIO):
    def __init__(self, *args, **kwargs):
        print('in myStringIO __init__()')
        self.total_read = 0
        StringIO.StringIO.__init__(self, *args, **kwargs)
    def tell(self, *args, **kwargs):
        x = StringIO.StringIO.tell(self, *args, **kwargs)
        print('in tell(), x = %d' % (x))
        return x
    def read(self, n=-1, *args, **kwargs):
        x = StringIO.StringIO.read(self, n, *args, **kwargs)
        print('read() n=%d, actually read %d' % (n, len(x)))
        self.total_read += len(x)
        return x
    def _complain_ifclosed(self, *args, **kwargs):
        print('in _complain_ifclosed()')
        return StringIO.StringIO._complain_ifclosed(self, *args, **kwargs)
    def seek(self, pos, mode, *args, **kwargs):
        print('seek() pos=%d, mode=%d' % (pos, mode))
        return StringIO.StringIO.seek(self, pos, mode, *args, **kwargs)

if True:
    file_contents = open('big_file.mpeg', 'r').read()
    print('len(file_contents) = %d' % (len(file_contents)))

    
def pyav_test():
    file_like_object = myStringIO(file_contents)
    
    before = time.time()
    container = av.open(file_like_object)

    video = next(s for s in container.streams if s.type == b'video')
    #video.delay = 0
    #print('video.delay = %d' % (video.delay))
    for packet in container.demux(video):
        #print('got packet')
        for frame in packet.decode():
            if frame.key_frame:
                print('frame.keyframe = %s' % (str(frame.key_frame)))
            print('write %d' % (frame.index))
            frame.to_image().save('pyav_frames/frame-%04d.jpg' % frame.index)
    after = time.time()

    print('elapsed = %f' % (after-before))
    print('total_read = %d' % (file_like_object.total_read))

pyav_test()
