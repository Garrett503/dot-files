#!/bin/bash

#https://peter.sh/experiments/chromium-command-line-switches/
#--app=http://facebook.com

url1=reddit.com
url2=bing.com
url3=twitch.tv
url4=twitter.com

i3-msg "workspace 11:  browser news; append_layout ~/.config/i3/ws_layouts/ws11_browsers_layout.json"

google-chrome-stable --user-data-dir=$HOME/.config/google-chrome/Profile1 --class=topleft --no-default-browser-check http://facebook.com  &
google-chrome-stable --user-data-dir=$HOME/.config/google-chrome/Profile2 --class=bottomleft --no-default-browser-check $url2  &
google-chrome-stable --user-data-dir=$HOME/.config/google-chrome/Profile3 --class=topright --no-default-browser-check --app=$url3  &
google-chrome-stable --user-data-dir=$HOME/.config/google-chrome/Profile4 --class=bottomright --no-default-browser-check $url4  &
