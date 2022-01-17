#!/bin/bash
#
# Screen shot using maim & xclip 
#
###

DMENU='dmenu -i -l 10 -p 'Screenshot''
choice=$(echo -e "area\nfull-screen" | $DMENU)

case "$choice" in
  area) maim -s -u | xclip -selection clipboard -t image/png -i & ;;
  full-screen) maim -u | xclip -selection clipboard -t image/png -i & ;;
esac
