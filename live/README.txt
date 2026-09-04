NEWGOD LIVE
screen only, no microphone, no webcam


WHAT IT IS

One button sends your whole screen to a YouTube live. Another writes it to an mp4
on your disk. A third freezes the picture so the broadcast stays up while you go
away. The panel also reads the live back: how many people are watching now and
who is typing in the chat, and it keeps those two numbers on the title bar so
they are still there when the panel is folded down to a strip.

There is no microphone input and no camera input anywhere in the command. The
only audio is a silent track, and it exists because a video only stream is
treated as unhealthy at the other end.


WHAT YOU NEED

  Windows
  Python 3.12
  ffmpeg on PATH, or put ffmpeg.exe next to newgodlive.py
  pip install pytchat requests psutil


HOW TO START IT

  pythonw newgodlive.py

Everything the tool writes stays in the same folder as the script.


THE THREE TEXT FILES, MADE ON FIRST RUN

  key.txt       your RTMP stream key, first line, nothing else
  hls.txt       or the whole https://a.upload.youtube.com/http_upload_hls?... url
                if your stream is set to HLS ingestion instead of RTMP
  channel.txt   your channel id, written automatically once it can work it out

If hls.txt holds a url it uses HLS. Otherwise it uses key.txt and RTMP. You only
need one of the two.

video.txt is optional. The tool reads your channel's live page every thirty
seconds and finds the current live by itself, so normally you never touch it.


THE BUTTONS

  LIVE     push the screen to YouTube
  REC      write the screen to an mp4 instead
  PAUSE    freeze the picture without ending the broadcast, press again to resume
  STOP     end whichever one is running
  -        fold the panel down to just its bar, the two numbers stay visible


THINGS THAT WILL WASTE YOUR EVENING IF NOBODY TELLS YOU

A remote shell cannot capture a screen. gdigrab answers "Failed to capture image
(error 5)" when it is started from a session with no desktop attached.

The GPU encoder can be newer than your driver. "Driver does not support the
required nvenc API version" means the ffmpeg build is ahead of the display
driver, not that the card is broken. This tool tests the encoder once at startup
and falls back to libx264 on its own.

A live stream that reads below the recommended bitrate is usually not your
network. -b:v is an average target, and a mostly static desktop compresses so
well that the encoder simply does not use the budget. Real CBR with filler is
what holds the number up, which is what this tool sends.

-http_persistent 1 can hang the whole encoder against an HLS ingest: the
connection stays established, the CPU drops to zero, and nothing is sent. It is
off here.

A chat reader that installs a keyboard interrupt handler throws "signal only
works in main thread of the main interpreter" the moment it is created on a
worker thread, and then the chat silently never arrives.


newgod.vip/info/liveing
