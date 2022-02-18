#!/bin/bash

dmenu='dmenu -i -l 10 '
choice=$(echo -e "" | $dmenu -p "Youtube search")
#query=$(printf '%s' "$*" | tr ' ' '+')
[[ $choice != "" ]] && \
query=$(sed "s/ /+/g" <<< $choice) && \
mpv "https://youtube.com/$(curl -s "https://vid.puffyan.us/search?q=$query" | grep -Eo "watch\?v=.{11}" | head -n 1)"
