i3-msg "workspace 4:  Music; append_layout ~/.config/i3/ws_layouts/ws4_spotify_layout.json"
#cava
sleep 5
urxvt -name 'cavaspot' -sh 100 -tr -e sh -c 'cava; bash' &
#spotify
spotify &
#update spotify
spicetify watch --live-update &
