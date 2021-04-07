#!/bin/bash

#https://peter.sh/experiments/chromium-command-line-switches/
#--app=http://facebook.com

url1=https://www.binance.us/en/trade/pro/BTC_USD
#url2=https://www.binance.com/en/trade/BTC_USDT?layout=pro
i3-msg "workspace 11:  browser news; append_layout ~/.config/i3/ws_layouts/ws11_crypto_layout.json"
google-chrome-unstable  --class=one --no-default-browser-check $url1 &
google-chrome-unstable  --class=two --no-default-browser-check $url1 &
google-chrome-unstable  --class=three --no-default-browser-check $url1 &
google-chrome-unstable  --class=four --no-default-browser-check $url1 &
google-chrome-unstable  --class=five --no-default-browser-check $url1 &
google-chrome-unstable  --class=six --no-default-browser-check $url1 &
