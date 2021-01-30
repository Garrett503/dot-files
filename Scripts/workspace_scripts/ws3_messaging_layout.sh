#!/bin/bash

i3-msg "workspace 3:  Messaging; append_layout ~/.config/i3/ws_layouts/ws3_messaging_layout.json"

discord &
mailspring &
skypeforlinux &
