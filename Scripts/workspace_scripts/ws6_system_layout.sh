i3-msg "workspace 6:  System; append_layout ~/.config/i3/ws_layouts/ws6_system_layout.json"


#ranger
kitty --name "rangersystem" -e $SHELL -c 'cd $HOME;ranger;' &
#pipes
kitty --name "pipessystem" -e $SHELL -c 'pipes.sh;$SHELL -i' &
#matrix
kitty --name "cmatrixsystem" -e $SHELL -c 'cmatrix;$SHELL -i' &
#peaclock
kitty --name "peaclocksystem" -e $SHELL -c 'peaclock;$SHELL -i' &
#blank term
kitty --name "blanksystem" -e $SHELL -c 'cd $HOME;$SHELL -i' &
#ytop
kitty --name "ytopsystem" -e $SHELL -c 'ytop;$SHELL -i' &
#htop
kitty --name "htopsystem" -e $SHELL -c 'htop;$SHELL -i' &
