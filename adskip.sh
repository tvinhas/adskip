#!/usr/bin/env bash

RAND1=$(( ( RANDOM % 10 )  + 1 ))
sleep $RAND1
RAND2=$(( ( RANDOM % 10 )  + 1 ))
RAND=$(($RAND1 + $RAND2 * $RAND1 * $RAND2 % 10))

ldPath=${LD_LIBRARY_PATH}
unset LD_LIBRARY_PATH

exitcode=0

ffmpegPath="ffmpeg"
comskipPath="comskip"

if [[ $# -lt 1 ]]; then

  exename=$(basename "$0")

  echo "Remove commercial from video file using EDL file"
  echo "     (If no EDL file is found, comskip will be used to generate one)"
  echo ""
  echo "Usage: $exename infile [outfile]"

  exit 1
fi

comskipini=/dvr/comskip.ini
deleteedl=true
deletemeta=true
deletelog=true
deletelogo=true
deletetxt=true
lockfile="/dvr/comskip.lock"
workdir=""

while [[ $# -gt 1 ]]
do
key="$1"
case $key in
    --keep-edl)
    deleteedl=false
    shift
    ;;
    --keep-meta)
    deletemeta=false
    shift
    ;;
    --ffmpeg=*)
    ffmpegPath="${key#*=}"
    shift
    ;;
    --comskip=*)
    comskipPath="${key#*=}"
    shift
    ;;
    --comskip-ini=*)
    comskipini="${key#*=}"
    shift
    ;;
    --lockfile=*)
    lockfile="${key#*=}"
    shift
    ;;
    --work-dir=*)
    workdir="${key#*=}"
    shift
    ;;
    *)
    break
    ;;
esac

done

if [ ! -z "$lockfile" ]; then

  echo "lockfile: $lockfile"
  while [[ -f "$lockfile" ]]; do
    echo "Waiting"
    sleep 5
  done

  touch "$lockfile"
fi

if [ ! -f "$comskipini" ]; then
  echo "output_edl=1" > "$comskipini"
elif ! grep -q "output_edl=1" "$comskipini"; then
  echo "output_edl=1" >> "$comskipini"
fi

echo "Backing up file $infile..." >>/dvr/dvr.log
time cp "$1" /dvr/backup >>/dvr/dvr.log
echo "Sleeping for $RAND seconds..." >>/dvr/dvr.log
sleep $RAND

infile=$1
tsfile=$1
outfile=$infile

if [[ -z "$2" ]]; then
  outfile="$infile"
else
  outfile="$2"
fi

outdir=$(dirname "$outfile")

outextension="${outfile##*.}"
comskipoutput=""

if [[ ! -z "$workdir" ]]; then
  case "$workdir" in
    */)
      ;;
    *)
      comskipoutput="--output=$workdir"
      workdir="$workdir/"
      ;;
  esac
fi

edlfile="$workdir${infile%.*}.edl"
metafile="$workdir${infile%.*}.ffmeta"
logfile="$workdir${infile%.*}.log"
logofile="$workdir${infile%.*}.logo.txt"
txtfile="$workdir${infile%.*}.txt"
outmkv="${outfile%.*}.mkv"

echo "Demuxing file $outfile..." >>/dvr/dvr.log
ffmpeg -fflags +genpts -i "$infile" -c:v copy -c:a:0 copy -c:s copy "$outmkv"
echo "Sleeping for $RAND seconds..." >>/dvr/dvr.log
sleep $RAND

infile=$outmkv
outfile=$outmkv

if [ ! -f "$edlfile" ]; then
  $comskipPath $comskipoutput --ini="$comskipini" "$infile"
fi

start=0
i=0
hascommercials=false

concat=""

tempfiles=()
totalcutduration=0

echo ";FFMETADATA1" > "$metafile"
# Reads in from $edlfile, see end of loop.
while IFS=$'\t' read -r -a line
do
  ((i++))

  end="${line[0]}"
  duration=`echo "$end" - "$start" | bc | awk '{printf "%f", $0}'`
  startnext="${line[1]}"

  hascommercials=true

  echo [CHAPTER] >> "$metafile"
  echo TIMEBASE=1/1000 >> "$metafile"
  echo START=`echo "($start - $totalcutduration) * 1000" | bc | awk '{printf "%i", $0}'` >> "$metafile"
  echo END=`echo "($end - $totalcutduration) * 1000" | bc | awk '{printf "%i", $0}'` >> "$metafile"

  chapterfile="${infile%.*}.part-$i.ts"

  if [[ ! -z "$workdir" ]]; then
    chapterfile=`basename "$chapterfile"`
    chapterfile="$workdir$chapterfile"
  fi

  tempfiles+=("$chapterfile")
  concat="$concat|$chapterfile"

  $ffmpegPath -nostdin -i "$infile" -ss "$start" -t "$duration" -c copy -y "$chapterfile"

  totalcutduration=`echo "$totalcutduration" + "$startnext" - "$end" | bc`
  start=$startnext
done < "$edlfile"

if $hascommercials ; then
  $ffmpegPath -nostdin -i "$metafile" -i "concat:${concat:1}" -c copy -map_metadata 0 -y "$outfile"
fi

for i in "${tempfiles[@]}"
do
  rm "$i"
done


#>&$"$tsfile"
#cp -f "$outmkv" /dvr/Shows
rm -f "$tsfile"


if $deleteedl ; then
  if [ -f "$edlfile" ] ; then
    rm "$edlfile";
  fi
fi

if $deletemeta ; then
  if [ -f "$metafile" ]; then
    rm "$metafile";
  fi
fi

if $deletelog ; then
  if [ -f "$logfile" ]; then
    rm "$logfile";
  fi
fi

if $deletelogo ; then
  if [ -f "$logofile" ]; then
    rm "$logofile";
  fi
fi

if $deletetxt ; then
  if [ -f "$txtfile" ]; then
    rm "$txtfile";
  fi
fi

if [ ! -z $ldPath ] ; then
  export LD_LIBRARY_PATH="$ldPath"
fi

if [ ! -z "$lockfile" ]; then
  rm "$lockfile"
fi
