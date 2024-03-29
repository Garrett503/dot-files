#!/bin/bash
path="$HOME/.config/BetterDiscord/themes"
theme="default"
config="/home/garrett/.config/pywal-discord"

unameOut="$(uname -s)"
case "${unameOut}" in
    Darwin*)    config="$HOME/.config/pywal-discord"
                path="$HOME/Library/Preferences/BetterDiscord/themes"
        ;;
esac

print_usage() {
  echo "Usage: $0 [-t theme] [-p path] [-d]"
  echo "-h                          Display this info"
  echo "-t theme                    Available: [default,abou]"
  echo "-p path/to/folder/or/file   Path where pywal-discord will generate theme. Default: $path"
  echo "-d                          Make path directory where theme will be generated"
}

while getopts 'dp:vt:vh' flag; do
  case "${flag}" in
    d) mkdir -p $path ;;
    p) path="${OPTARG}" ;;
    t) theme="${OPTARG}" ;;
    h) print_usage ;;
    *) print_usage 
       exit 1 ;;
  esac
done

newfile=$path/pywal-discord-$theme.theme.css


cat $config/meta.css $HOME/.cache/wal/colors.css $config/pywal-discord-$theme.css > $newfile 
if [ ! -f $newfile ]
then
    echo ⚠️ THEME WAS NOT CREATED ⚠️ 
    echo Try to change path with -p because $path doesn\'t exist, or add -d to create it
    exit 1
fi
