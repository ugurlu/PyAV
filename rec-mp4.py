import av
import logging
logging.basicConfig(level=logging.DEBUG)

#device as input
container = av.open('none:0',format="avfoundation")
audio_stream = container.streams.get(audio=0)[0]

#file container for output:
out_container = av.open('test.mp4', 'w')
out_stream = out_container.add_stream('aac', rate=44100)
out_container.start_encoding()
assert out_stream.time_base.denominator == 44100

samples = 0

for i, packet in enumerate(container.demux(audio_stream)):

    for frame in packet.decode():


        print frame
        print '    pts:', (float(frame.pts)*frame.time_base)

        out_pack = out_stream.encode(frame)
        print '    packet:', out_pack
        if out_pack:
            print '        pts:', out_pack.pts 
            print '        dts:', out_pack.dts
            print '        new:', samples
            out_pack.pts = out_pack.dts = samples
            samples += 1024 # because we know this
            out_container.mux(out_pack)

    if i > 100:
        break

while True:
    buffered = out_stream.fifo.samples
    out_pack = out_stream.encode(None)
    consumed = buffered - out_stream.fifo.samples
    if out_pack:
        print 'FLUSHING', consumed, out_pack
        out_pack.pts = out_pack.dts = samples
        samples += consumed
        try:
            out_container.mux(packet)
        except Exception as e:
            print e
    else:
        break

out_container.close()
