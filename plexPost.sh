#!/bin/bash
if [ $# -lt 1 ]
then
    echo "Usage: `basename $0` <filename> (must be a mkv file)"
        exit 1
fi

#vars
file=$(basename "$1")
logfile="/dvr/tmp/plexPost.log"
ondeck="/dvr/tmp/ondeck"
echo $(date) "Adding '$file' to ondeck list..." >> $logfile
echo $file >> $ondeck
