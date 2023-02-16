 #!/bin/bash
  
  wd="~/Documents/G/Golf/rotary-swing/03-unleashing-speed"
  
  #echo $wd
  
  while read -r line; do
      #echo -e "$line\n"; 
      IFS=$'\t' read -r date size dim folder file <<<"$line" 
      
      if [[ $date < "2022-10-06" ]] ; then
  #        printf "Processing: %s \n" "$file"
          path=$folder"/"$file    
          newpath=$folder"/"$( echo $file | sed -E 's/\.mp4/\-new.mp4/g')
  
          #echo $path $newpath
  
          if [[ $dim =~ '4096x2160' ]] ; then
              ffmpeg -i "$path" -c:v libx264 -crf 28 -preset faster -tune film -vf scale=1920x1080 "$newpath" </dev/null && mv $newpath $path
           else
              ffmpeg -i "$path" -c:v libx264 -crf 28 -preset faster -tune film "$newpath" </dev/null && mv $newpath $path
          fi
          #mv $newpath $path
      fi
  done < vid.txt
 

