#!/bin/sh
#Equation=$(echo "" | dmenu -n -p "Enter equation" | xargs -I % calc %)
Equation=$(echo "" | dmenu -p "Enter equation" | xargs -I % calc %)

notify-send "Result" "$Equation"
