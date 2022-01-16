#!/bin/bash

#random wallpaper
wal -i ~/Wallpapers/;

#update cava
cp $HOME/.cache/wal/cava.config $HOME/.config/cava/config; 
pkill -USR2 cava;

#update xresources
#cp $HOME/.cache/wal/colors.Xresources $HOME/.Xresources;
#xrdb -merge $HOME/.Xresources;

#live update spotify colors
spicetify watch --live-update &

#update discord theme
$HOME/Scripts/theme_scripts/pywal-discord.sh -t default

#update dunst colors
$HOME/Scripts/theme_scripts/dunst_pywal.sh;

#theme changed notification
sleep 1
$HOME/Scripts/theme_scripts/theme_change_success.sh;
