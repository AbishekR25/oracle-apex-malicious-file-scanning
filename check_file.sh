#!/bin/bash

FILE="$1"

# Run Defender scan

mdatp scan custom --path "$FILE"

sleep 2

# Check if file was detected as threat

if mdatp threat list | grep "$(basename "$FILE")" > /dev/null; then

  echo "INFECTED"

  rm -f "$FILE"

  exit 1

else

  echo "CLEAN"

  exit 0

fi
 
