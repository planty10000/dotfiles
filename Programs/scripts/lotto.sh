printf \
"+-------------------------------+
| Lotto random numbers          |
+-------------------------------+\n\n"


#.-------------------------------------------.
#| 1. Get # of games                         |
#'-------------------------------------------'
while $loop; do
    echo && read -p "How many games? " games
    if [[ $games =~ [q|Q] ]]; then
        games=0;break;
    elif [[ $games =~ ^[0-9]+$ ]]; then
        break; 
    else
        echo "Invalid # games"  
    fi 
done;


#.-------------------------------------------.
#| 2. Get # of # per game                    |
#'-------------------------------------------'
while $loop; do
    echo && read -p "How many numbers? " numbers
    if [[ $numbers =~ [q|Q] ]]; then
        numbers=0;break;
    elif [[ $numbers =~ ^[0-9]+$ ]]; then
        break; 
    else
        echo "Invalid # numbers"  
    fi 
done;


#.-------------------------------------------.
#| 3. Get max number                         |
#'-------------------------------------------'
while $loop; do
    echo && read -p "Highest #? " highNum
    if [[ $highNum =~ [q|Q] ]]; then
        highNum=0;break;
    elif [[ $highNum =~ ^[0-9]+$ ]]; then
        break; 
    else
        echo "Invalid # number"  
    fi 
done;

 
#.-------------------------------------------.
#| 3. Get number for game                    |
#'-------------------------------------------'
x=0;y=0;match=0

# loop for number of games
while [[ $x < $games ]]; do

    # loop for numbers per game
    while [[ $y < $numbers ]]; do
        # create a random number padded with zero to the left
        #RANDOM=$(date +%s%N | cut -b10-19)      # random seed
        RANDOM=$$
        rand=$(printf "%02d" $[RANDOM%$highNum+1])  #rand=$[RANDOM%45+1];    
        match=0

        # check if the number is in the game already
        for i in "${game[@]}"; do 
            if  [[ $rand == $i ]]; then
                match=1;  
            fi   
        done;

        # Add # to array as no match found
        if [[ $match == 0 ]]; then
            game[$y]=$rand
            (( y+=1 ))
        fi
    done;
    
    # print game
    #echo ${game[@]}
    
    # replaces bubble sort
    IFS=$'\n' a=(${game[*]}) 
    gamesorted=$(sort <<< "${a[*]}")
    echo $(printf "%02d" $((x+1)))': ' ${gamesorted[*]}

    # bubble sort
    #for ((i = 0; i<$numbers; i++))
    #do
    #    for((j = 0; j<$numbers-i-1; j++))
    #    do
    #
    #        if [ ${game[j]} -gt ${game[$((j+1))]} ]
    #        then
    #            # swap
    #            temp=${game[j]}
    #            game[$j]=${game[$((j+1))]}
    #            game[$((j+1))]=$temp
    #        fi
    #    done
    #done

    ## sorted game
    #echo ${game[@]}
    unset game
    (( x+=1 )); y=0;
done;
unset IFS
