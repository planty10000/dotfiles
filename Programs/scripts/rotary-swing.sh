#!/bin/bash
#
# List rotary swing golf videos in dmenu, upon selection play video in mpv 
#
#

DMENU='dmenu -i -l 30'
while true; do
    choice=$(find ~/Documents/G/Golf/rotary-swing/ -type f -iname "*.mp4" | sort | $DMENU)
    if [ -z "$choice" ]; then exit; fi  # if esc-ed then exit
    mpv $choice 
done

