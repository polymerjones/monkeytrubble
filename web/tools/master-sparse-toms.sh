# Phone-speaker master for Sparse Toms (2026-10-16, Paul picked this "B" version).
# usage: HARM=-3 sh web/tools/master-sparse-toms.sh "newdldump/Sparse Toms orig.mp3" web/audio/music/competitive-5-sparse-toms.mp3
# Adds tom overtones (asoftclip on 50-160 Hz, kept above 170 Hz) so small speakers carry the toms, trims sub and mud,
# lifts 3.5 kHz attack and air, gentle glue compression, then two-pass loudnorm to -15.8 LUFS / -1.2 dBTP.
IN="$1"; OUT="$2"
CHAIN="[0:a]highpass=f=30:poles=2,lowshelf=f=70:g=-2.5,asplit=2[dry][b];
[b]highpass=f=50,lowpass=f=160,volume=14dB,asoftclip=type=tanh,highpass=f=170:poles=2,highpass=f=170:poles=2,lowpass=f=1500,volume=${HARM:-0}dB[h];
[dry][h]amix=inputs=2:normalize=0,
equalizer=f=320:t=q:w=1.1:g=-2.5,
equalizer=f=1200:t=q:w=1:g=1,
equalizer=f=3500:t=q:w=0.9:g=4,
highshelf=f=9000:g=2.5,
acompressor=threshold=-20dB:ratio=2.2:attack=25:release=250:knee=6:makeup=2dB"
ffmpeg -hide_banner -nostats -y -i "$IN" -filter_complex "$CHAIN,loudnorm=I=-15.8:TP=-1.2:LRA=7:print_format=json" -f null - 2>&1 | sed -n '/^{/,/^}/p' > /tmp/ln.json
mI=$(grep input_i /tmp/ln.json|cut -d'"' -f4); mTP=$(grep input_tp /tmp/ln.json|cut -d'"' -f4); mLRA=$(grep input_lra /tmp/ln.json|cut -d'"' -f4); mT=$(grep input_thresh /tmp/ln.json|cut -d'"' -f4); off=$(grep target_offset /tmp/ln.json|cut -d'"' -f4)
ffmpeg -hide_banner -nostats -y -i "$IN" -filter_complex "$CHAIN,loudnorm=I=-15.8:TP=-1.2:LRA=7:measured_I=$mI:measured_TP=$mTP:measured_LRA=$mLRA:measured_thresh=$mT:offset=$off:linear=true,aresample=48000" -map_metadata 0 -c:a libmp3lame -b:a 192k "$OUT" 2>&1 | grep -i error
