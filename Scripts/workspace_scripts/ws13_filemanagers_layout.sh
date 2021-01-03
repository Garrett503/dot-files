#!/bin/bash

i3-msg "workspace 13:  filemanager; append_layout ~/.config/i3/ws13_filemanagers_layout.json"

dolphin &
filezilla &
