# Hotkeys - sxhkd
sxhkd -c ~/.config/sxhkd/sxhkdrc &

# start audio
pulseaudio --start &

# X11 compositor - frame opacity, window transparency
picom &

# wallpaper
nitrogen --restore &

# Network GUI
nm-applet &

# kill and start audio
pkill pulseaudio &
pulseaudio --start &

# screen lock after 10 minutes
xautolock -time 10 -locker slock -corners '----'  &

# slstatus
#slstatus &
dwmblocks &

# screen messaging
dunst &

# loop to restart dwm
while true; do
  dwm > /dev/null 2>&1
done

exec dwm
