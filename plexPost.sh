#!/bin/bash
if [ $# -lt 1 ]
then
    echo "Usage: `basename $0` <filename> (must be a mkv file)"
        exit 1
fi

#vars
file=$(basename "$1")
logfile="/config/tmp/plexPost.log"
ondeck="/config/tmp/ondeck"
mkdir /config/tmp >&/dev/null
echo $(date) "Adding '$file' to ondeck list..." >> $logfile
echo $file >> $ondeck
