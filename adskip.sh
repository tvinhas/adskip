#!/bin/bash
###############################################################################
# adskip by Thiago Vinhas: https://github.com/tvinhas/adskip                  #
# Based on comcut by Brett Sheleski: https://github.com/BrettSheleski/comchap #
###############################################################################

ldPath=${LD_LIBRARY_PATH}
unset LD_LIBRARY_PATH

if [[ $# -lt 1 ]]; then
    echo "Usage: adskip file-name"
    exit 1
fi

templog="/config/tmp/run.log"
log="/config/tmp/tv.log"
ondeck="/config/tmp/ondeck"
processing="/config/tmp/processing"
dvrhome="/dvr"
comskip="/opt/Comskip/comskip"
comskipini="/opt/adskip/comskip.ini"
file=$(basename "$1")
infile=$1

echo $(date) "-=-=-=Init log for $file=-=-=-" > $templog
echo $(date) "Starting adskip for $file..." >> $log

# Prevents processing multiple files at the same time
if [ ! -z "$processing" ]; then
    while [[ -f "$processing" ]]; do
        echo $(date) "...Processing file exists, run in progress, waiting" >> $log
        sleep 3
    done

    echo $(date) "...Creating lockfile on $processing" >> $log
    touch "$processing"
fi

newfile="${infile%.*}.mkv"
dir=`mktemp -d -p $dvrhome`
edlfile="$dir/${file%.*}.edl"
ccnofile="$dir/${file%.*}.ccno"
metafile="$dir/${file%.*}.ffmeta"
outmkv="$dir/${file%.*}.mkv"
cskipfile="$dir/${file%.*}-cskip.ts"

# Let's convert it to mkv first
echo $(date) "...Running ffmpeg" >> $log
/usr/bin/ffmpeg -fflags +genpts -i "$infile" -c:v copy -c:a copy -preset superfast -sn -movflags faststart "$newfile"  &>> $templog

#generate commercial file
echo $(date) "...Running Comskip on $dir" >> $log
$comskip --output=$dir --ini="$comskipini" "$newfile" &>> $templog

# If no commercials are detected, skip comskip concatanation
if [ ! -s "$edlfile" ]; then
    cskipfile=$newfile
    echo $(date) "...no commercials were found" >> $log
    rm -f "$infile" &>> $templog
    echo $(date) "We're all done!!!" >> $templog
else
    let start=i=totalcutduration=0
    concat=""
    tempfiles=()

    echo ";FFMETADATA1" > "$metafile"
    # Reads in from $edlfile, see end of loop.
    while IFS=$'\t' read -r -a line
    do

        end="${line[0]}"
        startnext="${line[1]}"

        if [ `echo "$end" | awk '{printf "%i", $0 * 1000}'` -gt `echo "$start" | awk '{printf "%i", $0 * 1000}'` ]; then

            ((i++))

            echo [CHAPTER] >> "$metafile"
            echo TIMEBASE=1/1000 >> "$metafile"
            echo START=`echo "($start - $totalcutduration) * 1000" | bc | awk '{printf "%i", $0}'` >> "$metafile"
            echo END=`echo "($end - $totalcutduration) * 1000" | bc | awk '{printf "%i", $0}'` >> "$metafile"
            echo "title=Chapter $i" >> "$metafile"

            chapterfile="$dir/${file%.*}.part-$i.ts"
            tempfiles+=("$chapterfile")
            concat="$concat|$chapterfile"
            duration=`echo "$end" "$start" | awk  '{printf "%f", $1 - $2}'`

            /usr/bin/ffmpeg -nostdin -i "$infile" -ss "$start" -t "$duration" -c copy -y "$chapterfile"  &>> $templog

            totalcutduration=`echo "$totalcutduration" + "$startnext" - "$end" | bc`
        fi
        start=$startnext
    done < "$edlfile"

    /usr/bin/ffmpeg -nostdin -i "$metafile" -i "concat:${concat:1}" -c copy -map_metadata 0 -y "$cskipfile"  &>> $templog

    # Move back so plex can continue
    echo $(date) "...Moving $outmkv to $newfile" >> $log
    if mv -f "$cskipfile" "$newfile" &>> $templog
    then
        rm -f "$infile" &>> $templog
    fi
fi
echo $(date) "...Cleanup" >> $log
rm -rf $dir &>> $templog
chown -R plex: $dvrhome

rm $processing &>> $templog
export LD_LIBRARY_PATH="$ldPath"

echo $(date) "Convert run complete!" >> $log
