import av
#device as input
container = av.open('none:0',format="avfoundation")
audio_stream = None
for i, stream in enumerate(container.streams):
    if stream.type == b'audio':
        audio_stream = stream
        break
if not audio_stream:
    exit()

#file container for output:
out_container = av.open('test.wav','w')
# out_stream = out_container.add_stream(codec_name = 'mp3',rate=44100)
out_stream = out_container.add_stream(template=audio_stream)
for i,packet in enumerate(container.demux(audio_stream)):
    print float(packet.pts*packet.stream.time_base)
    out_container.mux(packet)
    if i >500:
        break
out_container.close()
