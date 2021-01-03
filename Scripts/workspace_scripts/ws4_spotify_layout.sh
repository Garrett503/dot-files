i3-msg "workspace 4:  Music; append_layout ~/.config/i3/ws4_spotify_layout.json"
#cava
urxvt -name 'cavaspot' -sh 100 -tr -e sh -c 'cava; bash' &
spotify
