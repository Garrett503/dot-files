#!/bin/bash

morning="Good Morning , Garrett !"
afternoon="Good Afternoon , Garrett !"
evening="Good Evening , Garrett !"
hour=$(date +"%H")
NOW=$( date '+%F_%H:%M:%S' )
# if it is 4am-12pm greet morning
if [ $hour -ge 4 -a $hour -lt 12 ]
then
greet=  date +"$morning          %I : %M %p" | toilet -t  --directory /usr/share/figlet/fonts -f standard --filter border:metal
# if it is 12pm-6pm greet afternoon
elif [ $hour -ge 12 -a $hour -lt 18 ]
then
greet=  date +"$afternoon          %I : %M %p" | toilet -t  --directory /usr/share/figlet/fonts -f standard --filter border:metal
else # if it is 6pm-4am greet evening
greet= date +"$evening          %I : %M %p" | toilet -t  --directory /usr/share/figlet/fonts -f standard --filter border:metal
fi
#display greet
$greet
#toilet flags
#https://delightlylinux.wordpress.com/2015/11/13/colored-text-with-toilet/
