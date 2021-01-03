#!/bin/sh
#left monitor vertical - set primary 144hz
xrandr --output DVI-D-0 --off --output HDMI-0 --off --output HDMI-1 --mode 2560x1440 --pos 0x0 --rotate right --output DP-2 --off --output DP-1 --off --output DP-0 --primary --mode 1920x1080 --rate 144 --pos 1440x575 --rotate normal --output DP-3 --off --output VGA-1-1 --off --output HDMI-1-1 --off --output HDMI-1-2 --off
