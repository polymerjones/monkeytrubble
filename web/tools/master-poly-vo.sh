# POLY card VO master (2026-10-21): radio-announcer read in an arena.
# usage: sh web/tools/master-poly-vo.sh "~/Downloads/Poly card vo.wav" web/audio/praise [wav-copy-dir]
# Cuts the 5 takes on their silences, then per take: rumble/pop cleanup (90 Hz high-pass, de-click,
# dynamic cut on 60-160 Hz plosive bursts, light de-hiss), announcer EQ, two stacked compressors + limiter,
# synthetic 2.4 s arena reverb (WET, default 0.14: Paul found 0.42 plus the game's echo too much), measured gain to -13 LUFS + limiter at -0.7 dB like the other VO
# (loudnorm undershoots on clips this short),
# mono 44.1 kHz 128k MP3. The game plays these dry (sayCallout dry:true), without the praise doubler + echo.
IN="$1"; OUT="$2"; WAVS="$3"; WET=${WET:-0.14}
TMP=$(mktemp -d)

# Arena impulse response: decaying filtered noise (-60 dB at ~2.4 s), 40 ms pre-delay, darker tail.
ffmpeg -v error -y -f lavfi -i "anoisesrc=d=2.6:c=pink:r=44100:a=0.5:seed=7" \
  -af "volume='exp(-2.9*t)':eval=frame,lowpass=f=4500,highpass=f=180,adelay=40,afade=t=out:st=2.3:d=0.3" "$TMP/arena.wav"

# name start end (seconds in the source recording)
TAKES="poly-a 0.45 1.45
poly-hey-a 2.9 4.78
poly-hey-b 6.7 9.6
poly-monkey-trubble-a 11.2 13.45
poly-monkey-trubble-b 14.6 17.35"

CLEAN="highpass=f=90:poles=2,highpass=f=70:poles=2,
adeclick=w=55:o=75,
adynamicequalizer=dfrequency=110:dqfactor=0.8:tfrequency=110:tqfactor=0.8:threshold=0.02:ratio=6:attack=1:release=60:range=12:mode=cutabove,
afftdn=nf=-45:nr=8,
equalizer=f=300:t=q:w=1.2:g=-3,
equalizer=f=3000:t=q:w=0.9:g=4,
highshelf=f=10000:g=2,
acompressor=threshold=-24dB:ratio=4:attack=3:release=120:knee=4:makeup=6dB,
acompressor=threshold=-18dB:ratio=8:attack=1:release=80:knee=2:makeup=4dB,
alimiter=limit=0.89:attack=2:release=40:level=0"

echo "$TAKES" | while read NAME S E; do
  # cut with a short head/tail fade, then pad 1.6 s so the reverb tail rings out
  CHAIN="[0:a]atrim=start=$S:end=$E,asetpts=PTS-STARTPTS,afade=t=in:d=0.01,
$CLEAN,aresample=44100,apad=pad_dur=1.6,asplit=2[dry][w];
[w][1:a]afir=dry=10:wet=10[wet];
[dry]volume=1[d];[wet]volume=$WET[v];
[d][v]amix=inputs=2:normalize=0:duration=first,
areverse,silenceremove=start_periods=1:start_threshold=-62dB,areverse"
  ffmpeg -v error -y -i "$IN" -i "$TMP/arena.wav" -filter_complex "$CHAIN" -ac 1 -c:a pcm_f32le "$TMP/raw.wav"
  I=$(ffmpeg -hide_banner -nostats -i "$TMP/raw.wav" -af ebur128 -f null - 2>&1 | grep -E '^ +I:' | tail -1 | awk '{print $2}')
  G=$(echo "-13 - ($I) + 0.4" | bc -l)
  ffmpeg -v error -y -i "$TMP/raw.wav" -af "volume=${G}dB,aresample=176400,alimiter=limit=0.92:attack=1:release=50:level=0,aresample=44100,areverse,afade=t=in:d=0.12,areverse" -c:a pcm_s16le "$TMP/$NAME.wav"
  ffmpeg -v error -y -i "$TMP/$NAME.wav" -c:a libmp3lame -b:a 128k "$OUT/$NAME.mp3"
  [ -n "$WAVS" ] && cp "$TMP/$NAME.wav" "$WAVS/$NAME.wav"
  echo "$NAME done"
done
rm -rf "$TMP"
