#!/bin/bash
#
# a simple dmenu session script 
#
###

#DMENU='dmenu -i -b -fn -xos4-terminus-medium-r-*--12-*-*-*-*-*-iso10646-1 -nb #000000 -nf #999999 -sb #000000 -sf #31658C'
DMENU='dmenu -i -l 10'
choice=$(echo -e "logout\nshutdown\nreboot\nsuspend\nhibernate" | $DMENU)

case "$choice" in
  logout) logout & ;;
  shutdown) shutdown -h now & ;;
  reboot) shutdown -r now & ;;
  suspend) pm-suspend & ;;
  hibernate) pm-hibernate & ;;
esac
