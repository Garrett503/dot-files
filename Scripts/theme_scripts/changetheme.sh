#!/bin/bash

#random wallpaper
wal -i ~/Pictures/Wallpapers2/;
#update cava
cp $HOME/.cache/wal/cava.config $HOME/.config/cava/config; 
pkill -USR2 cava;
#update xresources
cp $HOME/.cache/wal/colors.Xresources $HOME/.Xresources;
xrdb -merge ~/.Xresources;
#live update spotify colors
spicetify watch --live-update &
#update dunst colors
~/Scripts/theme_scripts/dunst_pywal.sh;
#theme changed notification
sleep 1
~/Scripts/theme_scripts/theme_change_success.sh;

############################################################
#IGNORE
###########################################################
#sleep 2
#~/Scripts/theme_scripts/dunst_pywal.sh;
#sleep 2
#~/Scripts/theme_scripts/theme_change_success.sh; 
#update spotify
#killall spotify
#sleep 1
#spicetify --update;
#spicetify watch --live-update
#~/Scripts/workspace_scripts/ws4_spotify_layout.sh;
#sleep 5
#spicetify apply;
#killall spotify;
#killall urxvt;
#sleep 1
#~/Scripts/workspace_scripts/ws4_spotify_layout.sh;
#update discord
#~/.config/BetterDiscord/pydis/pywal-discord/pywal-discord abou;
#update dunst
