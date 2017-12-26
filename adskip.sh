#!/bin/bash

templog="/data/tmp/run.log"
log="/data/tmp/tv.log"
ondeck="/data/tmp/ondeck"
processing="/data/tmp/processing"
dvrhome="/archive"
comskipini="/opt/adskip/comskip.ini"

echo "Init log" > $templog

echo $(date) "Starting convert run..." >> $log

if [ -a "$processing" ]
then
    echo $(date) "...Processing file exists, run in progress, aborting" >> $log
else
    if [ -a "$ondeck" ]
    then
        echo $(date) "...Moving ondeck to processing" >> $log
        mv -f $ondeck $processing &>> $log

        #read in list of files to process
        while IFS='' read -u 42 -r line || [[ -n "$line" ]]; do
            echo $(date) "...Processing $line" >> $log
            file=`find "$dvrhome" -iname "$line"`

            if [ -a "$file" ]

            newfile="${file%.*}.mkv"
            dir=`mktemp -d -p $dvrhome`
            filename=$line
            edlfile="$dir/${filename%.*}.edl"
            ccnofile="$dir/${filename%.*}.ccno"
            metafile="$dir/${filename%.*}.ffmeta"
            cskipfile="$dir/${filename%.*}-cskip.ts"
            outmkv="$dir/${filename%.*}.mkv"

            then
                echo $(date) "...Found $file" >> $log

                # backup the file
                echo $(date) "...Backing up $file" >> $log
#               cp -f "$file" /backup/  &>> $templog

                #generate commercial file
                echo $(date) "...Running Comskip on $dir" >> $log
                comskip --output=$dir --ini="$comskipini" "$file" &>> $templog

                let start=i=totalcutduration=0
                hascommercials=false
                concat=""
                tempfiles=()

                echo ";FFMETADATA1" > "$metafile"
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

                  chapterfile="$dir/${filename%.*}.part-$i.ts"
                  tempfiles+=("$chapterfile")
                  concat="$concat|$chapterfile"

                  ffmpeg -nostdin -i "$file" -ss "$start" -t "$duration" -c copy -y "$chapterfile"  &>> $templog

                  totalcutduration=`echo "$totalcutduration" + "$startnext" - "$end" | bc`
                  start=$startnext
                done < "$edlfile"

                if $hascommercials ; then
                  ffmpeg -nostdin -i "$metafile" -i "concat:${concat:1}" -c copy -map_metadata 0 -y "$cskipfile"  &>> $templog
                fi

                #convert
                echo $(date) "...Running Handbrake" >> $log
#               ffmpeg -fflags +genpts -i "$cskipfile" -c:v libx264 -c:a ac3 -preset fast -crf 12 "$outmkv"  &>> $templog

                ffmpeg -fflags +genpts -i "$cskipfile" -c:v copy -c:a copy -preset superfast -sn -movflags faststart "$outmkv"  &>> $templog


                #move back so plex can continue
                echo $(date) "...Moving $outmkv to $newfile" >> $log
                if mv -f "$outmkv" "$newfile" &>> $templog
                then
                    rm "$file" &>> $templog
                fi
            else
                echo $(date) "...No file found. Skipping $line" >> $log
            fi

            echo "...Cleanup" >> $log
            rm -rf $dir &>> $templog
            chown -R plex: $dvrhome

        done 42< "$processing"
        rm $processing &>> $templog
    else
        echo $(date) "...No shows ondeck, aborting" >> $log
    fi
fi

echo $(date) "Convert run complete!" >> $log
