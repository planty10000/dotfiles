#!/bin/bash

echo && read -p "Max number? " HighNum
echo && read -p "Numbers per game? " NumPerGame
#HighNum=45

shuf -e $(seq -w 01 $HighNum) -n$HighNum | xargs -n$NumPerGame | awk ' {split( $0, a, " " ); asort( a ); printf("%02d: ", NR); for( i = 1; i <= length(a); i++ ) printf( "%s ", a[i] ); printf( "\n" ); }'
