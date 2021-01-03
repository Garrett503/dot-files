#!/bin/bash

#
#pick random wallpaper
wal -i ~/Pictures/Wallpapers/;
cp $HOME/.cache/wal/cava.config $HOME/.config/cava/config; 
update cava
pkill -USR2 cava;
cp $HOME/.cache/wal/colors.Xresources $HOME/.Xresources;
#cat $HOME/.Xresources $HOME/gg.txt > $HOME/.Xresources;
xrdb -merge ~/.Xresources;
#xrdb -merge ~/.Xdefaults;
spicetify update;
spicetify apply;
#killall spotify;
#killall urxvt;
#spicetify update
#spicetify apply
#sleep 1
#~/Scripts/workspace_scripts/ws4_spotify_layout.sh;
#update discord
#~/.config/BetterDiscord/pydis/pywal-discord/pywal-discord abou;
#update dunst;
~/Scripts/theme_scripts/dunst_pywal.sh;
sleep 0.5
#success message
~/Scripts/theme_scripts/theme_change_success.sh;
