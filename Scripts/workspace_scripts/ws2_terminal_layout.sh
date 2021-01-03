i3-msg "workspace 2:  Terminals; append_layout ~/.config/i3/ws2_terminal_layout.json"


kitty --name "leftterm" -e $SHELL -c 'cd $HOME;toilet -t  --directory /usr/share/figlet/fonts -f standard --filter border:metal Hello , Garrett;$SHELL -i' &
kitty --name "rightterm" -e $SHELL -c 'cd $HOME;$SHELL -i'  &



