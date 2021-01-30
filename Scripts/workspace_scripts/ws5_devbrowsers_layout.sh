#!/bin/bash

i3-msg "workspace 5:  Dev Browser; append_layout ~/.config/i3/ws_layouts/ws5_devbrowsers_layout.json" 
firefox-developer-edition &
google-chrome-unstable &
