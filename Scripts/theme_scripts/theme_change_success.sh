#dunst notification for new color scheme with wallpaper

newbackground=$(cat ~/.cache/wal/wal)
notify-send -a  "Theme Changed!" "Wallpaper, Terminals, Spotify, Discord, Polybar, VSCode Updated!" -i $newbackground                                                                                            
