#!/bin/sh

PROGRESS_CURR=0
PROGRESS_TOTAL=3108                        

# This file was autowritten by rmlint
# rmlint was executed from: /home/garrett/
# Your command line was: rmlint .config

RMLINT_BINARY="/usr/bin/rmlint"

# Only use sudo if we're not root yet:
# (See: https://github.com/sahib/rmlint/issues/27://github.com/sahib/rmlint/issues/271)
SUDO_COMMAND="sudo"
if [ "$(id -u)" -eq "0" ]
then
  SUDO_COMMAND=""
fi

USER='garrett'
GROUP='garrett'

# Set to true on -n
DO_DRY_RUN=

# Set to true on -p
DO_PARANOID_CHECK=

# Set to true on -r
DO_CLONE_READONLY=

# Set to true on -q
DO_SHOW_PROGRESS=true

# Set to true on -c
DO_DELETE_EMPTY_DIRS=

# Set to true on -k
DO_KEEP_DIR_TIMESTAMPS=

# Set to true on -i
DO_ASK_BEFORE_DELETE=

##################################
# GENERAL LINT HANDLER FUNCTIONS #
##################################

COL_RED='[0;31m'
COL_BLUE='[1;34m'
COL_GREEN='[0;32m'
COL_YELLOW='[0;33m'
COL_RESET='[0m'

print_progress_prefix() {
    if [ -n "$DO_SHOW_PROGRESS" ]; then
        PROGRESS_PERC=0
        if [ $((PROGRESS_TOTAL)) -gt 0 ]; then
            PROGRESS_PERC=$((PROGRESS_CURR * 100 / PROGRESS_TOTAL))
        fi
        printf '%s[%3d%%]%s ' "${COL_BLUE}" "$PROGRESS_PERC" "${COL_RESET}"
        if [ $# -eq "1" ]; then
            PROGRESS_CURR=$((PROGRESS_CURR+$1))
        else
            PROGRESS_CURR=$((PROGRESS_CURR+1))
        fi
    fi
}

handle_emptyfile() {
    print_progress_prefix
    echo "${COL_GREEN}Deleting empty file:${COL_RESET} $1"
    if [ -z "$DO_DRY_RUN" ]; then
        rm -f "$1"
    fi
}

handle_emptydir() {
    print_progress_prefix
    echo "${COL_GREEN}Deleting empty directory: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        rmdir "$1"
    fi
}

handle_bad_symlink() {
    print_progress_prefix
    echo "${COL_GREEN} Deleting symlink pointing nowhere: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        rm -f "$1"
    fi
}

handle_unstripped_binary() {
    print_progress_prefix
    echo "${COL_GREEN} Stripping debug symbols of: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        strip -s "$1"
    fi
}

handle_bad_user_id() {
    print_progress_prefix
    echo "${COL_GREEN}chown ${USER}${COL_RESET} $1"
    if [ -z "$DO_DRY_RUN" ]; then
        chown "$USER" "$1"
    fi
}

handle_bad_group_id() {
    print_progress_prefix
    echo "${COL_GREEN}chgrp ${GROUP}${COL_RESET} $1"
    if [ -z "$DO_DRY_RUN" ]; then
        chgrp "$GROUP" "$1"
    fi
}

handle_bad_user_and_group_id() {
    print_progress_prefix
    echo "${COL_GREEN}chown ${USER}:${GROUP}${COL_RESET} $1"
    if [ -z "$DO_DRY_RUN" ]; then
        chown "$USER:$GROUP" "$1"
    fi
}

###############################
# DUPLICATE HANDLER FUNCTIONS #
###############################

check_for_equality() {
    if [ -f "$1" ]; then
        # Use the more lightweight builtin `cmp` for regular files:
        cmp -s "$1" "$2"
        echo $?
    else
        # Fallback to `rmlint --equal` for directories:
        "$RMLINT_BINARY" -p --equal  "$1" "$2"
        echo $?
    fi
}

original_check() {
    if [ ! -e "$2" ]; then
        echo "${COL_RED}^^^^^^ Error: original has disappeared - cancelling.....${COL_RESET}"
        return 1
    fi

    if [ ! -e "$1" ]; then
        echo "${COL_RED}^^^^^^ Error: duplicate has disappeared - cancelling.....${COL_RESET}"
        return 1
    fi

    # Check they are not the exact same file (hardlinks allowed):
    if [ "$1" = "$2" ]; then
        echo "${COL_RED}^^^^^^ Error: original and duplicate point to the *same* path - cancelling.....${COL_RESET}"
        return 1
    fi

    # Do double-check if requested:
    if [ -z "$DO_PARANOID_CHECK" ]; then
        return 0
    else
        if [ "$(check_for_equality "$1" "$2")" -ne "0" ]; then
            echo "${COL_RED}^^^^^^ Error: files no longer identical - cancelling.....${COL_RESET}"
            return 1
        fi
    fi
}

cp_symlink() {
    print_progress_prefix
    echo "${COL_YELLOW}Symlinking to original: ${COL_RESET}$1"
    if original_check "$1" "$2"; then
        if [ -z "$DO_DRY_RUN" ]; then
            # replace duplicate with symlink
            rm -rf "$1"
            ln -s "$2" "$1"
            # make the symlink's mtime the same as the original
            touch -mr "$2" -h "$1"
        fi
    fi
}

cp_hardlink() {
    if [ -d "$1" ]; then
        # for duplicate dir's, can't hardlink so use symlink
        cp_symlink "$@"
        return $?
    fi
    print_progress_prefix
    echo "${COL_YELLOW}Hardlinking to original: ${COL_RESET}$1"
    if original_check "$1" "$2"; then
        if [ -z "$DO_DRY_RUN" ]; then
            # replace duplicate with hardlink
            rm -rf "$1"
            ln "$2" "$1"
        fi
    fi
}

cp_reflink() {
    if [ -d "$1" ]; then
        # for duplicate dir's, can't clone so use symlink
        cp_symlink "$@"
        return $?
    fi
    print_progress_prefix
    # reflink $1 to $2's data, preserving $1's  mtime
    echo "${COL_YELLOW}Reflinking to original: ${COL_RESET}$1"
    if original_check "$1" "$2"; then
        if [ -z "$DO_DRY_RUN" ]; then
            touch -mr "$1" "$0"
            if [ -d "$1" ]; then
                rm -rf "$1"
            fi
            cp --archive --reflink=always "$2" "$1"
            touch -mr "$0" "$1"
        fi
    fi
}

clone() {
    print_progress_prefix
    # clone $1 from $2's data
    # note: no original_check() call because rmlint --dedupe takes care of this
    echo "${COL_YELLOW}Cloning to: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        if [ -n "$DO_CLONE_READONLY" ]; then
            $SUDO_COMMAND $RMLINT_BINARY --dedupe  --dedupe-readonly "$2" "$1"
        else
            $RMLINT_BINARY --dedupe  "$2" "$1"
        fi
    fi
}

skip_hardlink() {
    print_progress_prefix
    echo "${COL_BLUE}Leaving as-is (already hardlinked to original): ${COL_RESET}$1"
}

skip_reflink() {
    print_progress_prefix
    echo "${COL_BLUE}Leaving as-is (already reflinked to original): ${COL_RESET}$1"
}

user_command() {
    print_progress_prefix

    echo "${COL_YELLOW}Executing user command: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        # You can define this function to do what you want:
        echo 'no user command defined.'
    fi
}

remove_cmd() {
    print_progress_prefix
    echo "${COL_YELLOW}Deleting: ${COL_RESET}$1"
    if original_check "$1" "$2"; then
        if [ -z "$DO_DRY_RUN" ]; then
            if [ -n "$DO_KEEP_DIR_TIMESTAMPS" ]; then
                touch -r "$(dirname "$1")" "$STAMPFILE"
            fi
            if [ -n "$DO_ASK_BEFORE_DELETE" ]; then
              rm -ri "$1"
            else
              rm -rf "$1"
            fi
            if [ -n "$DO_KEEP_DIR_TIMESTAMPS" ]; then
                # Swap back old directory timestamp:
                touch -r "$STAMPFILE" "$(dirname "$1")"
                rm "$STAMPFILE"
            fi

            if [ -n "$DO_DELETE_EMPTY_DIRS" ]; then
                DIR=$(dirname "$1")
                while [ ! "$(ls -A "$DIR")" ]; do
                    print_progress_prefix 0
                    echo "${COL_GREEN}Deleting resulting empty dir: ${COL_RESET}$DIR"
                    rmdir "$DIR"
                    DIR=$(dirname "$DIR")
                done
            fi
        fi
    fi
}

original_cmd() {
    print_progress_prefix
    echo "${COL_GREEN}Keeping:  ${COL_RESET}$1"
}

##################
# OPTION PARSING #
##################

ask() {
    cat << EOF

This script will delete certain files rmlint found.
It is highly advisable to view the script first!

Rmlint was executed in the following way:

   $ rmlint .config

Execute this script with -d to disable this informational message.
Type any string to continue; CTRL-C, Enter or CTRL-D to abort immediately
EOF
    read -r eof_check
    if [ -z "$eof_check" ]
    then
        # Count Ctrl-D and Enter as aborted too.
        echo "${COL_RED}Aborted on behalf of the user.${COL_RESET}"
        exit 1;
    fi
}

usage() {
    cat << EOF
usage: $0 OPTIONS

OPTIONS:

  -h   Show this message.
  -d   Do not ask before running.
  -x   Keep rmlint.sh; do not autodelete it.
  -p   Recheck that files are still identical before removing duplicates.
  -r   Allow deduplication of files on read-only btrfs snapshots. (requires sudo)
  -n   Do not perform any modifications, just print what would be done. (implies -d and -x)
  -c   Clean up empty directories while deleting duplicates.
  -q   Do not show progress.
  -k   Keep the timestamp of directories when removing duplicates.
  -i   Ask before deleting each file
EOF
}

DO_REMOVE=
DO_ASK=

while getopts "dhxnrpqcki" OPTION
do
  case $OPTION in
     h)
       usage
       exit 0
       ;;
     d)
       DO_ASK=false
       ;;
     x)
       DO_REMOVE=false
       ;;
     n)
       DO_DRY_RUN=true
       DO_REMOVE=false
       DO_ASK=false
       DO_ASK_BEFORE_DELETE=false
       ;;
     r)
       DO_CLONE_READONLY=true
       ;;
     p)
       DO_PARANOID_CHECK=true
       ;;
     c)
       DO_DELETE_EMPTY_DIRS=true
       ;;
     q)
       DO_SHOW_PROGRESS=
       ;;
     k)
       DO_KEEP_DIR_TIMESTAMPS=true
       STAMPFILE=$(mktemp 'rmlint.XXXXXXXX.stamp')
       ;;
     i)
       DO_ASK_BEFORE_DELETE=true
       ;;
     *)
       usage
       exit 1
  esac
done

if [ -z $DO_REMOVE ]
then
    echo "#${COL_YELLOW} ///${COL_RESET}This script will be deleted after it runs${COL_YELLOW}///${COL_RESET}"
fi

if [ -z $DO_ASK ]
then
  usage
  ask
fi

if [ -n "$DO_DRY_RUN" ]
then
    echo "#${COL_YELLOW} ////////////////////////////////////////////////////////////${COL_RESET}"
    echo "#${COL_YELLOW} /// ${COL_RESET} This is only a dry run; nothing will be modified! ${COL_YELLOW}///${COL_RESET}"
    echo "#${COL_YELLOW} ////////////////////////////////////////////////////////////${COL_RESET}"
fi

######### START OF AUTOGENERATED OUTPUT #########

handle_bad_symlink '/home/garrett/.config/google-chrome-unstable/SingletonLock' # bad symlink pointing nowhere
handle_bad_symlink '/home/garrett/.config/discord/SingletonCookie' # bad symlink pointing nowhere
handle_bad_symlink '/home/garrett/.config/google-chrome-unstable/SingletonCookie' # bad symlink pointing nowhere
handle_bad_symlink '/home/garrett/.config/Mailspring/SingletonLock' # bad symlink pointing nowhere
handle_bad_symlink '/home/garrett/.config/Mailspring/SingletonCookie' # bad symlink pointing nowhere
handle_bad_symlink '/home/garrett/.config/skypeforlinux/SingletonCookie' # bad symlink pointing nowhere
handle_bad_symlink '/home/garrett/.config/Bitwarden/SS' # bad symlink pointing nowhere
handle_bad_symlink '/home/garrett/.config/Bitwarden/SingletonLock' # bad symlink pointing nowhere
handle_bad_symlink '/home/garrett/.config/Bitwarden/SingletonCookie' # bad symlink pointing nowhere
handle_bad_symlink '/home/garrett/.config/google-chrome/SingletonCookie' # bad symlink pointing nowhere
handle_bad_symlink '/home/garrett/.config/google-chrome/SingletonLock' # bad symlink pointing nowhere
handle_bad_symlink '/home/garrett/.config/discord/SingletonLock' # bad symlink pointing nowhere
handle_bad_symlink '/home/garrett/.config/skypeforlinux/SingletonLock' # bad symlink pointing nowhere
handle_emptydir '/home/garrett/.config/wal/colorschemes/light' # empty folder
handle_emptydir '/home/garrett/.config/wal/colorschemes/dark' # empty folder
handle_emptydir '/home/garrett/.config/wal/colorschemes' # empty folder
handle_emptydir '/home/garrett/.config/spotify/User Data/Dictionaries' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/zlink/libs/ad-formats/images' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/zlink/libs/ad-formats' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/zlink/libs' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/zlink/images/share' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/zlink/images' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/stations/images' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/login/images/fake-web-player' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/login/images' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/licenses/css' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/glue-resources/images' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/glue-resources/fonts' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/full-screen-modal/img' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/findfriends/img' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/buddy-list/img' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/browse/libs/ad-formats/images' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/browse/libs/ad-formats' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/browse/libs' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/artist/img' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Themed/about/img' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extracted/Raw/licenses/css' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/Extensions' # empty folder
handle_emptydir '/home/garrett/.config/spicetify/CustomApps' # empty folder
handle_emptydir '/home/garrett/.config/skypeforlinux/blob_storage/89b4dfb1-dddc-4e09-a219-edc622b64528' # empty folder
handle_emptydir '/home/garrett/.config/skypeforlinux/blob_storage' # empty folder
handle_emptydir '/home/garrett/.config/ranger' # empty folder
handle_emptydir '/home/garrett/.config/qt5ct/qss' # empty folder
handle_emptydir '/home/garrett/.config/qt5ct/colors' # empty folder
handle_emptydir '/home/garrett/.config/obs-studio/plugin_config/text-freetype2' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome/Webstore Downloads' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome/NativeMessagingHosts' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome/MEIPreload' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome/Floc' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome/Default/blob_storage/431f6d9a-c408-445a-8040-91ad5554cf94' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome/Default/blob_storage' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome/Default/Search Logos' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome/Default/File System/030/t' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome/Default/File System/030' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome/Default/File System/029/t' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome/Default/File System/029' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome/Default/Extensions/epcnnfbjfcgphgdmggkamkmgojdagdnn/0.9.5.25_0/assets/tmp/httpsb-asset' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome/Default/Extensions/epcnnfbjfcgphgdmggkamkmgojdagdnn/0.9.5.25_0/assets/tmp' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome/Crash Reports' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome-unstable/NativeMessagingHosts' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome-unstable/MEIPreload' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome-unstable/Floc' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome-unstable/Default/blob_storage/27db3725-950e-4307-94e0-7c1a30e031f7' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome-unstable/Default/blob_storage' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome-unstable/Default/Search Logos' # empty folder
handle_emptydir '/home/garrett/.config/google-chrome-unstable/Crash Reports' # empty folder
handle_emptydir '/home/garrett/.config/discord/blob_storage/01d76d8d-ae23-4b9e-b2f0-528ee16805fb' # empty folder
handle_emptydir '/home/garrett/.config/discord/blob_storage' # empty folder
handle_emptydir '/home/garrett/.config/discord/0.0.13/modules/pending' # empty folder
handle_emptydir '/home/garrett/.config/VIA/blob_storage/6db0b0bb-e32a-4ca0-a1cc-c018983d190b' # empty folder
handle_emptydir '/home/garrett/.config/VIA/blob_storage' # empty folder
handle_emptydir '/home/garrett/.config/VIA/VIA/logs' # empty folder
handle_emptydir '/home/garrett/.config/VIA/VIA' # empty folder
handle_emptydir '/home/garrett/.config/Skype/Dictionaries' # empty folder
handle_emptydir '/home/garrett/.config/Skype' # empty folder
handle_emptydir '/home/garrett/.config/Mailspring/dictionaries' # empty folder
handle_emptydir '/home/garrett/.config/Mailspring/blob_storage/11ece780-3da5-47c5-9bfe-f099b711a9d8' # empty folder
handle_emptydir '/home/garrett/.config/Mailspring/blob_storage' # empty folder
handle_emptydir '/home/garrett/.config/Code/blob_storage/96b0c118-3fe5-4956-8935-0faa68ee6150' # empty folder
handle_emptydir '/home/garrett/.config/Code/User/globalStorage/ms-toolsai.jupyter/nbsignatures' # empty folder
handle_emptydir '/home/garrett/.config/Bitwarden/blob_storage/2feee832-9623-4eef-91a4-05fab0a9b925' # empty folder
handle_emptydir '/home/garrett/.config/Bitwarden/blob_storage' # empty folder
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/000/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/018/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.camwhoresbay.com_0.indexeddb.leveldb/000007.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Local Storage/leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Session Storage/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/011/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_monkeytype.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.snipesusa.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Reporting and NEL-journal' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/output_1_20210101T074854/tasks.log' # empty file
handle_emptyfile '/home/garrett/.config/skypeforlinux/IndexedDB/file__0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/001/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.frandieguez.dev_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.amazon.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/BudgetDatabase/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Local Storage/leveldb/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_realpython.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/data_reduction_proxy_leveldb/000079.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.autodesk.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/output_1_20210101T074854/extensions.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Local Storage/leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Media History-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Feature Engagement Tracker/AvailabilityDB/LOG.old' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.frandieguez.dev_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/000/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_github.community_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T122042/exthost1/output_logging_20210101T122044/1-Microsoft Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125238/exthost1/output_logging_20210101T125242/6-TodoHighlight.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210102T084228/exthost1/output_logging_20210102T084230/1-Microsoft Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Session Storage/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/016/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/025/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/VIA/Session Storage/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/001/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074904/1-Microsoft Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Login Data For Account-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Top Sites-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/007/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.sportingnews.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/Session Storage/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Extension Rules/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Web Data-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/011/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/output_1_20210101T074916/extensions.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T131833/exthost1/output_logging_20210101T131837/7-GitHub Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T115114/exthost1/output_logging_20210101T115117/1-Microsoft Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_lpcdn.lpsnmedia.net_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.lowes.com_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/discord/Cookies-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Extension Rules/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Platform Notifications/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Cookies-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.lowes.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T122042/output_1_20210101T122044/extensions.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/AutofillStrikeDatabase/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T112137/exthost1/output_logging_20210101T112142/5-CSS Peek.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/Origins/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T122042/renderer1.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.nba.com_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Login Data-journal' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074917/1-Microsoft Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Media History-journal' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T115346/exthost1/output_logging_20210101T115349/5-CSS Peek.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T115114/output_1_20210101T115115/extensions.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/Cookies-journal' # empty file
handle_emptyfile '/home/garrett/.config/Bitwarden/Cookies-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Favicons-journal' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T131833/exthost1/output_logging_20210101T131837/6-TodoHighlight.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.thesaurus.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T115346/exthost1/output_logging_20210101T115349/6-TodoHighlight.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125726/exthost1/output_logging_20210101T125729/1-Microsoft Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/output_1_20210101T074904/tasks.log' # empty file
handle_emptyfile '/home/garrett/.config/skypeforlinux/Local Storage/leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/shared_proto_db/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/VIA/Session Storage/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/012/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_h.online-metrix.net_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.instagram.com_0.indexeddb.leveldb/000016.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074905/7-GitHub Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_theporndude.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/028/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/output_1_20210101T074904/extensions.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/028/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/shared_proto_db/LOG' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T131833/exthost1/output_logging_20210101T131837/5-CSS Peek.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.cardboardconnection.com_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T115346/exthost1/output_logging_20210101T115349/1-Microsoft Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.youtube-nocookie.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Site Characteristics Database/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/shared_proto_db/metadata/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/spicetify/Extracted/Raw/error/css/error.css' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_photos.google.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/shared_proto_db/metadata/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Session Storage/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_bongacams.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Feature Engagement Tracker/AvailabilityDB/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Platform Notifications/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_bongacams.com_0.indexeddb.leveldb/000007.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/output_1_20210101T074916/tasks.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.camwhoresbay.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/First Run' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/AutofillStrikeDatabase/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Safe Browsing Cookies-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/020/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T112137/output_1_20210101T112141/extensions.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/IndexedDB/https_googleads.g.doubleclick.net_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Platform Notifications/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/gpick/user_init.lua' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/AutofillStrikeDatabase/LOG.old' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.twitch.tv_0.indexeddb.leveldb/000115.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.sportingnews.com_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Favicons-journal' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T122042/output_1_20210101T122044/tasks.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T115114/output_1_20210101T115115/tasks.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/012/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Bitwarden/Local Storage/leveldb/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/016/p/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/shared_proto_db/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T131833/exthost1/output_logging_20210101T131837/1-Microsoft Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_h.online-metrix.net_0.indexeddb.leveldb/000010.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125513/exthost1/output_logging_20210101T125517/4-CSS Peek.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_mail.google.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074855/8-TodoHighlight.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T112137/exthost1/output_logging_20210101T112141/1-Microsoft Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Platform Notifications/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Service Worker/Database/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074905/5-CSS Peek.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/AutofillStrikeDatabase/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/skypeforlinux/Cookies-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_stockx.com_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Network Action Predictor-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_stockx.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/019/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/spicetify/Extracted/Themed/error/css/error.css' # empty file
handle_emptyfile '/home/garrett/.config/VIA/Cookies-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Platform Notifications/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_pages.ebay.com_0.indexeddb.leveldb/000011.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.nfl.com_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074905/6-TodoHighlight.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/Local Storage/leveldb/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125513/exthost1/output_logging_20210101T125517/6-TodoHighlight.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Feature Engagement Tracker/EventDB/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T112137/exthost1/output_logging_20210101T112139/7-GitHub Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T115346/exthost1/output_logging_20210101T115349/7-GitHub Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074855/10-Python Test Log.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125513/exthost1/output_logging_20210101T125517/7-GitHub Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T115346/output_1_20210101T115347/extensions.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.autodesk.com_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125513/exthost1/output_logging_20210101T125516/1-Microsoft Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/BudgetDatabase/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_twitter.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/005/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Local Storage/leveldb/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210102T084228/renderer1.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/022/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074855/11-GitHub Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/019/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Platform Notifications/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T112137/exthost1/output_logging_20210101T112142/6-TodoHighlight.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_mrrobot.fandom.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_pages.ebay.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.twitch.tv_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.nba.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210102T084228/output_1_20210102T084229/extensions.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Shortcuts-journal' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T112137/output_1_20210101T112141/tasks.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/data_reduction_proxy_leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T112137/exthost1/output_logging_20210101T112142/7-GitHub Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/024/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125726/renderer1.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.atlassian.com_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.techradar.com_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/024/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_addons.mozilla.org_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Network Action Predictor-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.fool.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/002/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Login Data-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Feature Engagement Tracker/EventDB/LOG' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_pua.emp.state.or.us_0.indexeddb.leveldb/000007.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/022/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_lpcdn.lpsnmedia.net_0.indexeddb.leveldb/000071.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/015/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.microsoft.com_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/filezilla/lockfile' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Reporting and NEL-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/005/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T112137/exthost1/output_logging_20210101T112139/5-CSS Peek.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/databases/Databases.db-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_mail.google.com_0.indexeddb.leveldb/000011.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/BudgetDatabase/LOG.old' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/IndexedDB/https_googleads.g.doubleclick.net_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Local Extension Settings/ghbmnnjooekpmoecnnnilnnbdlolhkhi/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/VideoDecodeStats/LOG' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/027/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Sync Extension Settings/pkedcjkdefgpdelpbcmbmeomcjbeemfm/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T112137/exthost1/output_logging_20210101T112139/6-TodoHighlight.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/File System/000/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_pua.emp.state.or.us_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_photos.google.com_0.indexeddb.leveldb/000011.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/BudgetDatabase/LOG' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.microsoft.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210102T084228/output_1_20210102T084229/tasks.log' # empty file
handle_emptyfile '/home/garrett/.config/discord/Session Storage/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.atlassian.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074917/6-TodoHighlight.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_mega.nz_0.indexeddb.leveldb/000011.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/previews_opt_out.db-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/015/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.nfl.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T122042/exthost1/output_logging_20210101T122045/7-GitHub Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T131833/output_1_20210101T131836/extensions.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125513/renderer1.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/LOG' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Extension State/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Platform Notifications/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Mailspring/Local Storage/leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074917/7-GitHub Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_collegereadiness.collegeboard.org_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/002/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/014/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T131833/output_1_20210101T131836/tasks.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/004/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/discord/Local Storage/leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.youtube.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/File System/000/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.instagram.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Shortcuts-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/006/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/LOG.old' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_addons.mozilla.org_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Local Storage/leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.spotify.com_0.indexeddb.leveldb/000039.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Top Sites-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/010/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Site Characteristics Database/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/VideoDecodeStats/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/013/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.cardboardconnection.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T112137/output_1_20210101T112138/extensions.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.techradar.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Sync Extension Settings/pkedcjkdefgpdelpbcmbmeomcjbeemfm/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125238/renderer1.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Extension State/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.americascardroom.eu_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Feature Engagement Tracker/AvailabilityDB/LOG' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210102T084228/exthost1/output_logging_20210102T084231/7-GitHub Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/026/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Feature Engagement Tracker/EventDB/LOG.old' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210102T084228/exthost1/output_logging_20210102T084231/5-CSS Peek.log' # empty file
handle_emptyfile '/home/garrett/.config/oh-my-zsh/plugins/glassfish/glassfish.plugin.zsh' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/AutofillStrikeDatabase/LOG' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/006/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_sciencing.com_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_mrrobot.fandom.com_0.indexeddb.leveldb/000007.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T115114/exthost1/output_logging_20210101T115118/6-TodoHighlight.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/010/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125726/exthost1/output_logging_20210101T125730/7-GitHub Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Local Storage/leveldb/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/heavy_ad_intervention_opt_out.db-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/007/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/014/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/017/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/004/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.americascardroom.eu_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074917/5-CSS Peek.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Safe Browsing Cookies-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Trust Tokens-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Platform Notifications/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T122042/exthost1/output_logging_20210101T122045/5-CSS Peek.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/026/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/027/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/skypeforlinux/QuotaManager-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/VideoDecodeStats/LOG.old' # empty file
handle_emptyfile '/home/garrett/.config/Bitwarden/Local Storage/leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T122042/exthost1/output_logging_20210101T122045/6-TodoHighlight.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125726/exthost1/output_logging_20210101T125729/5-CSS Peek.log' # empty file
handle_emptyfile '/home/garrett/.config/discord/domainMigrated' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125238/output_1_20210101T125240/extensions.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Sync Data/LevelDB/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_sciencing.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125726/output_1_20210101T125728/extensions.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_forum.archlabslinux.com_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125238/exthost1/output_logging_20210101T125241/1-Microsoft Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/skypeforlinux/databases/Databases.db-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_mega.nz_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T112137/output_1_20210101T112138/tasks.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/Local Storage/leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_collegereadiness.collegeboard.org_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T131833/renderer1.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/003/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074855/7-CSS Peek.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.snipesusa.com_0.indexeddb.leveldb/000006.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/008/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/databases/Databases.db-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/GCM Store/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/First Run' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125238/exthost1/output_logging_20210101T125242/4-CSS Peek.log' # empty file
handle_emptyfile '/home/garrett/.config/oh-my-zsh/plugins/fabric/fabric.plugin.zsh' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Feature Engagement Tracker/AvailabilityDB/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/017/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125726/output_1_20210101T125728/tasks.log' # empty file
handle_emptyfile '/home/garrett/.config/Mailspring/Cookies-journal' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125726/exthost1/output_logging_20210101T125729/6-TodoHighlight.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Cookies-journal' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074854/1-Microsoft Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074854/2-VS IntelliCode.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/previews_opt_out.db-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.tomshardware.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/023/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_realpython.com_0.indexeddb.leveldb/000007.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125238/exthost1/output_logging_20210101T125242/7-GitHub Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Local Storage/leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Sync Extension Settings/pkedcjkdefgpdelpbcmbmeomcjbeemfm/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/GCM Store/Encryption/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210102T084228/exthost1/output_logging_20210102T084231/6-TodoHighlight.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/heavy_ad_intervention_opt_out.db-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Feature Engagement Tracker/EventDB/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125513/output_1_20210101T125515/extensions.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/data_reduction_proxy_leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125513/output_1_20210101T125515/tasks.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_forum.archlabslinux.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_theporndude.com_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Local Storage/leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T125238/output_1_20210101T125240/tasks.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T115346/output_1_20210101T115347/tasks.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.spotify.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/009/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/021/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T115114/renderer1.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T112137/exthost1/output_logging_20210101T112138/1-Microsoft Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/023/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.thesaurus.com_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/018/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/013/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/GCM Store/Encryption/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T115114/exthost1/output_logging_20210101T115118/5-CSS Peek.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/008/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T115346/renderer1.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Local Extension Settings/epcnnfbjfcgphgdmggkamkmgojdagdnn/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Session Storage/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Feature Engagement Tracker/EventDB/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Sync Data/LevelDB/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Local Storage/leveldb/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.tomshardware.com_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Platform Notifications/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/data_reduction_proxy_leveldb/000075.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Session Storage/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/BudgetDatabase/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/Code/logs/20210101T115114/exthost1/output_logging_20210101T115118/7-GitHub Authentication.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/shared_proto_db/LOG.old' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Platform Notifications/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Sync Extension Settings/pkedcjkdefgpdelpbcmbmeomcjbeemfm/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Web Data-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/File System/Origins/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_app2.ged.com_0.indexeddb.leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/GCM Store/Encryption/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/025/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/Local Extension Settings/ghbmnnjooekpmoecnnnilnnbdlolhkhi/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/IndexedDB/https_github.community_0.indexeddb.leveldb/000004.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Session Storage/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/009/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/021/t/Paths/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/File System/003/t/Paths/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Local Storage/leveldb/LOCK' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome-unstable/Default/QuotaManager-journal' # empty file
handle_emptyfile '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Platform Notifications/000003.log' # empty file
handle_emptyfile '/home/garrett/.config/oh-my-zsh/plugins/golang/templates/search.txt' # empty file

original_cmd  '/home/garrett/.config/pulse/15ed70bc016e4913b02c15c0d989c5e9-default-sink' # original
remove_cmd    '/home/garrett/.config/pulse/15ed70bc016e4913b02c15c0d989c5e9-default-source' '/home/garrett/.config/pulse/15ed70bc016e4913b02c15c0d989c5e9-default-sink' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/cld/deps/cld/LICENSE' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/cld/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/cld/deps/cld/LICENSE' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/keyboard-layout/LICENSE.md' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/event-kit/LICENSE.md' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/keyboard-layout/LICENSE.md' # duplicate

original_cmd  '/home/garrett/.config/obs-studio/basic/scenes/Untitled.json.bak' # original
remove_cmd    '/home/garrett/.config/obs-studio/basic/scenes/Untitled.json' '/home/garrett/.config/obs-studio/basic/scenes/Untitled.json.bak' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/once/once.js' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/once/once.js' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/once/once.js' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/wrappy/wrappy.js' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/wrappy/wrappy.js' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/wrappy/wrappy.js' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/combined-stream/License' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/delayed-stream/License' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/combined-stream/License' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/inherits/LICENSE' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/inherits/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/inherits/LICENSE' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/inherits/package.json' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/inherits/package.json' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/inherits/package.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/inherits/README.md' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/inherits/README.md' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/inherits/README.md' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/end-of-stream/LICENSE' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/pump/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/end-of-stream/LICENSE' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/signal-exit/README.md' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/signal-exit/README.md' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/signal-exit/README.md' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/signal-exit/CHANGELOG.md' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/signal-exit/CHANGELOG.md' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/signal-exit/CHANGELOG.md' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/shebang-regex/package.json' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/shebang-regex/package.json' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/shebang-regex/package.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/signal-exit/index.js' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/signal-exit/index.js' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/signal-exit/index.js' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/string-width/node_modules/strip-ansi/readme.md' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/cliui/node_modules/strip-ansi/readme.md' '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/string-width/node_modules/strip-ansi/readme.md' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/string-width/node_modules/strip-ansi/package.json' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/cliui/node_modules/strip-ansi/package.json' '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/string-width/node_modules/strip-ansi/package.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/string-width/node_modules/ansi-regex/package.json' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/cliui/node_modules/ansi-regex/package.json' '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/string-width/node_modules/ansi-regex/package.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/which/package.json' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/which/package.json' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/which/package.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/which/CHANGELOG.md' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/which/CHANGELOG.md' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/which/CHANGELOG.md' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/which/which.js' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/which/which.js' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/which/which.js' # duplicate

original_cmd  '/home/garrett/.config/spotify/Users/cyjv6842g51vbch5xxzova15l-user/watch-sources.bnk' # original
remove_cmd    '/home/garrett/.config/spotify/Users/garrettrocky-user/watch-sources.bnk' '/home/garrett/.config/spotify/Users/cyjv6842g51vbch5xxzova15l-user/watch-sources.bnk' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/isexe/index.js' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/isexe/index.js' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/isexe/index.js' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/shebang-command/readme.md' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/shebang-command/readme.md' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/shebang-command/readme.md' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/which/bin/which' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/which/bin/which' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/which/bin/which' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/keymap.json' # original
remove_cmd    '/home/garrett/.config/Code/languagepacks.json' '/home/garrett/.config/Mailspring/keymap.json' # duplicate
remove_cmd    '/home/garrett/.config/skypeforlinux/SkypeRT/ecs.conf' '/home/garrett/.config/Mailspring/keymap.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/minimatch/LICENSE' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/once/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/minimatch/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/wrappy/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/minimatch/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/rimraf/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/minimatch/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/glob/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/minimatch/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/semver/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/minimatch/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/which/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/minimatch/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/isexe/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/minimatch/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/once/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/minimatch/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/wrappy/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/minimatch/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/cross-spawn/node_modules/semver/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/minimatch/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/lru-cache/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/minimatch/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/which/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/minimatch/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/isexe/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/minimatch/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/pseudomap/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/minimatch/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/yallist/LICENSE' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/minimatch/LICENSE' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/path-key/readme.md' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/path-key/readme.md' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/path-key/readme.md' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/imports.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/9049b41024a61794890273aa8c5b33c9a758b566/imports.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/imports.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/path-key/package.json' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/path-key/package.json' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/path-key/package.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/5af91cf1f6188ad596b86f89d8affa1a060fadad/email-frame.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/5af91cf1f6188ad596b86f89d8affa1a060fadad/email-frame.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/5af91cf1f6188ad596b86f89d8affa1a060fadad/email-frame.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/3f961d90e41a81116d692ea4f82f48754cf506b3/content/018e1e7fc7381ddf3e13d071ec3a3bb1680fe31d/ui-variables.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/0e5965c877d83f64250b4c19dc975fc54bb672d0/content/018e1e7fc7381ddf3e13d071ec3a3bb1680fe31d/ui-variables.json' '/home/garrett/.config/Mailspring/compile-cache/less/3f961d90e41a81116d692ea4f82f48754cf506b3/content/018e1e7fc7381ddf3e13d071ec3a3bb1680fe31d/ui-variables.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/string-width/node_modules/ansi-regex/readme.md' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/cliui/node_modules/ansi-regex/readme.md' '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/string-width/node_modules/ansi-regex/readme.md' # duplicate

original_cmd  '/home/garrett/.config/nano/nano-syntax-highlighting/zsh.nanorc' # original
remove_cmd    '/home/garrett/.config/nano/nano-syntax-highlighting/zshrc.nanorc' '/home/garrett/.config/nano/nano-syntax-highlighting/zsh.nanorc' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/about/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/about/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/about/index.html' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/2f78d6d236b81cd41dbee4b3f64b70f4a7c50a37/fonts.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/3f961d90e41a81116d692ea4f82f48754cf506b3/content/2f78d6d236b81cd41dbee4b3f64b70f4a7c50a37/fonts.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/2f78d6d236b81cd41dbee4b3f64b70f4a7c50a37/fonts.json' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/0e5965c877d83f64250b4c19dc975fc54bb672d0/content/2f78d6d236b81cd41dbee4b3f64b70f4a7c50a37/fonts.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/2f78d6d236b81cd41dbee4b3f64b70f4a7c50a37/fonts.json' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/5986f64a241009cff575a185214e9af6893391c3/content/2f78d6d236b81cd41dbee4b3f64b70f4a7c50a37/fonts.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/2f78d6d236b81cd41dbee4b3f64b70f4a7c50a37/fonts.json' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/2f78d6d236b81cd41dbee4b3f64b70f4a7c50a37/fonts.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/2f78d6d236b81cd41dbee4b3f64b70f4a7c50a37/fonts.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/c1a7ca9d1cd84cb64d000c04583dd1462697f771/composer.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/c1a7ca9d1cd84cb64d000c04583dd1462697f771/composer.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/c1a7ca9d1cd84cb64d000c04583dd1462697f771/composer.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/e691db14e75304a4db4b6ca0f6adcbb43b1644cf/message-list.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/e691db14e75304a4db4b6ca0f6adcbb43b1644cf/message-list.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/e691db14e75304a4db4b6ca0f6adcbb43b1644cf/message-list.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/c93845dffeff179cb77b0232a57f54f6bec7cd8d/notifications.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/c93845dffeff179cb77b0232a57f54f6bec7cd8d/notifications.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/c93845dffeff179cb77b0232a57f54f6bec7cd8d/notifications.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/0e5965c877d83f64250b4c19dc975fc54bb672d0/content/01ea51967a51d0d8423673d21a2b1dd2c80d1c09/index.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/5986f64a241009cff575a185214e9af6893391c3/content/01ea51967a51d0d8423673d21a2b1dd2c80d1c09/index.json' '/home/garrett/.config/Mailspring/compile-cache/less/0e5965c877d83f64250b4c19dc975fc54bb672d0/content/01ea51967a51d0d8423673d21a2b1dd2c80d1c09/index.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/c93845dffeff179cb77b0232a57f54f6bec7cd8d/styles.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/c93845dffeff179cb77b0232a57f54f6bec7cd8d/styles.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/c93845dffeff179cb77b0232a57f54f6bec7cd8d/styles.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/once/package.json' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/once/package.json' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/once/package.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/strip-final-newline/license' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/p-finally/license' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/strip-final-newline/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/execa/license' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/strip-final-newline/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/npm-run-path/node_modules/path-key/license' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/strip-final-newline/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/is-stream/license' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/strip-final-newline/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/npm-run-path/license' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/strip-final-newline/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/string-width/node_modules/strip-ansi/license' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/strip-final-newline/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/string-width/license' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/strip-final-newline/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/string-width/node_modules/ansi-regex/license' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/strip-final-newline/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/cliui/node_modules/ansi-regex/license' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/strip-final-newline/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/cliui/node_modules/strip-ansi/license' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/strip-final-newline/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/execa/license' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/strip-final-newline/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/mimic-fn/license' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/strip-final-newline/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/p-limit/license' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/strip-final-newline/license' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Accounts/Avatar Images/102542880969516513468' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Google Profile Picture.png' '/home/garrett/.config/google-chrome/Default/Accounts/Avatar Images/102542880969516513468' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/isexe/package.json' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/isexe/package.json' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/isexe/package.json' # duplicate

original_cmd  '/home/garrett/.config/Code/User/workspaceStorage/0b6b77c243264eedee166c86ca33e977/state.vscdb' # original
remove_cmd    '/home/garrett/.config/Code/User/workspaceStorage/0b6b77c243264eedee166c86ca33e977/state.vscdb.backup' '/home/garrett/.config/Code/User/workspaceStorage/0b6b77c243264eedee166c86ca33e977/state.vscdb' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/0ae20d63b80df3557ae287116767c373e232bd04/selected-items-stack.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/0ae20d63b80df3557ae287116767c373e232bd04/selected-items-stack.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/0ae20d63b80df3557ae287116767c373e232bd04/selected-items-stack.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/3cdc5b0d660456f5dcf1a4268edc206df8592a63/preferences-identity.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/3cdc5b0d660456f5dcf1a4268edc206df8592a63/preferences-identity.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/3cdc5b0d660456f5dcf1a4268edc206df8592a63/preferences-identity.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/3cdc5b0d660456f5dcf1a4268edc206df8592a63/preferences-mail-rules.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/3cdc5b0d660456f5dcf1a4268edc206df8592a63/preferences-mail-rules.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/3cdc5b0d660456f5dcf1a4268edc206df8592a63/preferences-mail-rules.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/3dbba6f0764b1a42814eb5bb8aa2d43c7808cae4/thread-search-bar.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/3dbba6f0764b1a42814eb5bb8aa2d43c7808cae4/thread-search-bar.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/3dbba6f0764b1a42814eb5bb8aa2d43c7808cae4/thread-search-bar.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/3cdc5b0d660456f5dcf1a4268edc206df8592a63/preferences-accounts.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/3cdc5b0d660456f5dcf1a4268edc206df8592a63/preferences-accounts.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/3cdc5b0d660456f5dcf1a4268edc206df8592a63/preferences-accounts.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/3cdc5b0d660456f5dcf1a4268edc206df8592a63/preferences.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/3cdc5b0d660456f5dcf1a4268edc206df8592a63/preferences.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/3cdc5b0d660456f5dcf1a4268edc206df8592a63/preferences.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/5986f64a241009cff575a185214e9af6893391c3/content/dadf920aacc4a0c66f69b7eb38b68bb4c474d7c0/index.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/dadf920aacc4a0c66f69b7eb38b68bb4c474d7c0/index.json' '/home/garrett/.config/Mailspring/compile-cache/less/5986f64a241009cff575a185214e9af6893391c3/content/dadf920aacc4a0c66f69b7eb38b68bb4c474d7c0/index.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/0ae20d63b80df3557ae287116767c373e232bd04/thread-list.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/0ae20d63b80df3557ae287116767c373e232bd04/thread-list.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/0ae20d63b80df3557ae287116767c373e232bd04/thread-list.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/cc7bfd0dd2fe77120e61666e48482b23b8a54416/category-mapper.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/cc7bfd0dd2fe77120e61666e48482b23b8a54416/category-mapper.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/cc7bfd0dd2fe77120e61666e48482b23b8a54416/category-mapper.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/aadad4e0b36529ad24d11dde5b80ab752f0d844f/category-picker.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/aadad4e0b36529ad24d11dde5b80ab752f0d844f/category-picker.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/aadad4e0b36529ad24d11dde5b80ab752f0d844f/category-picker.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/21051d8676543e5288d9681925aeb1ec6c47c3d8/message-autoload-images.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/21051d8676543e5288d9681925aeb1ec6c47c3d8/message-autoload-images.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/21051d8676543e5288d9681925aeb1ec6c47c3d8/message-autoload-images.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/5a3e043eead56452b4d980c253b791532cfc0deb/events.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/5a3e043eead56452b4d980c253b791532cfc0deb/events.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/5a3e043eead56452b4d980c253b791532cfc0deb/events.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/8fb6b45d4ea0f10c20f6c091bb081d4c322684f3/index.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/8fb6b45d4ea0f10c20f6c091bb081d4c322684f3/index.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/8fb6b45d4ea0f10c20f6c091bb081d4c322684f3/index.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/a687c40a97c8e6f774c61746d509cb836bd3490a/composer-signature.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/a687c40a97c8e6f774c61746d509cb836bd3490a/composer-signature.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/a687c40a97c8e6f774c61746d509cb836bd3490a/composer-signature.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/f914be5a6d404f8180bde1c734d93e088651a1bf/message-templates.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/f914be5a6d404f8180bde1c734d93e088651a1bf/message-templates.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/f914be5a6d404f8180bde1c734d93e088651a1bf/message-templates.json' # duplicate

original_cmd  '/home/garrett/.config/polybar/crypto-eth/main.rb' # original
remove_cmd    '/home/garrett/.config/polybar/crypto-btc/main.rb' '/home/garrett/.config/polybar/crypto-eth/main.rb' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/shebang-regex/readme.md' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/shebang-regex/readme.md' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/shebang-regex/readme.md' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/f28873dc0e06a81ef649a0a1699ad79a43267779/send-later-used-modal.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/f28873dc0e06a81ef649a0a1699ad79a43267779/send-later-used-modal.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/f28873dc0e06a81ef649a0a1699ad79a43267779/send-later-used-modal.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/signal-exit/package.json' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/signal-exit/package.json' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/signal-exit/package.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/isexe/mode.js' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/isexe/mode.js' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/isexe/mode.js' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/95ece7afb66bed7c151f9c8c1bb5c966bca97ac4/theme-picker.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/95ece7afb66bed7c151f9c8c1bb5c966bca97ac4/theme-picker.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/95ece7afb66bed7c151f9c8c1bb5c966bca97ac4/theme-picker.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/c2a864199e15a504a981a2bf502ccc149faad365/snooze-feature-used-modal.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/c2a864199e15a504a981a2bf502ccc149faad365/snooze-feature-used-modal.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/c2a864199e15a504a981a2bf502ccc149faad365/snooze-feature-used-modal.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/c2a864199e15a504a981a2bf502ccc149faad365/snooze-mail-label.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/3f961d90e41a81116d692ea4f82f48754cf506b3/content/c2a864199e15a504a981a2bf502ccc149faad365/snooze-mail-label.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/c2a864199e15a504a981a2bf502ccc149faad365/snooze-mail-label.json' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/0e5965c877d83f64250b4c19dc975fc54bb672d0/content/c2a864199e15a504a981a2bf502ccc149faad365/snooze-mail-label.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/c2a864199e15a504a981a2bf502ccc149faad365/snooze-mail-label.json' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/5986f64a241009cff575a185214e9af6893391c3/content/c2a864199e15a504a981a2bf502ccc149faad365/snooze-mail-label.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/c2a864199e15a504a981a2bf502ccc149faad365/snooze-mail-label.json' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/c2a864199e15a504a981a2bf502ccc149faad365/snooze-mail-label.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/c2a864199e15a504a981a2bf502ccc149faad365/snooze-mail-label.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/c2a864199e15a504a981a2bf502ccc149faad365/snooze-popover.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/c2a864199e15a504a981a2bf502ccc149faad365/snooze-popover.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/c2a864199e15a504a981a2bf502ccc149faad365/snooze-popover.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/97d5117231ad648bb3ef14b61cdfa54268379b32/index.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/97d5117231ad648bb3ef14b61cdfa54268379b32/index.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/97d5117231ad648bb3ef14b61cdfa54268379b32/index.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/77aba68ced20c9e89ad7a583a9b4719e2beebddf/reminders-used-modal.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/77aba68ced20c9e89ad7a583a9b4719e2beebddf/reminders-used-modal.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/77aba68ced20c9e89ad7a583a9b4719e2beebddf/reminders-used-modal.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/7e8fa9ada00f3bee1142d342f9d8788a4870de67/ui-variables.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/3f961d90e41a81116d692ea4f82f48754cf506b3/content/7e8fa9ada00f3bee1142d342f9d8788a4870de67/ui-variables.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/7e8fa9ada00f3bee1142d342f9d8788a4870de67/ui-variables.json' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/7e8fa9ada00f3bee1142d342f9d8788a4870de67/ui-variables.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/7e8fa9ada00f3bee1142d342f9d8788a4870de67/ui-variables.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/77aba68ced20c9e89ad7a583a9b4719e2beebddf/send-reminders.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/77aba68ced20c9e89ad7a583a9b4719e2beebddf/send-reminders.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/77aba68ced20c9e89ad7a583a9b4719e2beebddf/send-reminders.json' # duplicate

original_cmd  '/home/garrett/.config/Bitwarden/GPUCache/data_0' # original
remove_cmd    '/home/garrett/.config/VIA/GPUCache/data_0' '/home/garrett/.config/Bitwarden/GPUCache/data_0' # duplicate
remove_cmd    '/home/garrett/.config/skypeforlinux/GPUCache/data_0' '/home/garrett/.config/Bitwarden/GPUCache/data_0' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/ShaderCache/GPUCache/data_0' '/home/garrett/.config/Bitwarden/GPUCache/data_0' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/GPUCache/data_0' '/home/garrett/.config/Bitwarden/GPUCache/data_0' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/GPUCache/data_0' '/home/garrett/.config/Bitwarden/GPUCache/data_0' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/GPUCache/data_0' '/home/garrett/.config/Bitwarden/GPUCache/data_0' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/ShaderCache/GPUCache/data_0' '/home/garrett/.config/Bitwarden/GPUCache/data_0' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/GPUCache/data_0' '/home/garrett/.config/Bitwarden/GPUCache/data_0' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/GPUCache/data_0' '/home/garrett/.config/Bitwarden/GPUCache/data_0' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/GPUCache/data_0' '/home/garrett/.config/Bitwarden/GPUCache/data_0' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/GPUCache/data_0' '/home/garrett/.config/Bitwarden/GPUCache/data_0' # duplicate

original_cmd  '/home/garrett/.config/Code/GPUCache/data_2' # original
remove_cmd    '/home/garrett/.config/Bitwarden/GPUCache/data_2' '/home/garrett/.config/Code/GPUCache/data_2' # duplicate
remove_cmd    '/home/garrett/.config/VIA/GPUCache/data_2' '/home/garrett/.config/Code/GPUCache/data_2' # duplicate
remove_cmd    '/home/garrett/.config/discord/GPUCache/data_2' '/home/garrett/.config/Code/GPUCache/data_2' # duplicate
remove_cmd    '/home/garrett/.config/skypeforlinux/GPUCache/data_2' '/home/garrett/.config/Code/GPUCache/data_2' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/ShaderCache/GPUCache/data_2' '/home/garrett/.config/Code/GPUCache/data_2' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/GPUCache/data_2' '/home/garrett/.config/Code/GPUCache/data_2' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/GPUCache/data_2' '/home/garrett/.config/Code/GPUCache/data_2' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/GrShaderCache/GPUCache/data_2' '/home/garrett/.config/Code/GPUCache/data_2' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/GPUCache/data_2' '/home/garrett/.config/Code/GPUCache/data_2' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/ShaderCache/GPUCache/data_2' '/home/garrett/.config/Code/GPUCache/data_2' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/GPUCache/data_2' '/home/garrett/.config/Code/GPUCache/data_2' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/GPUCache/data_2' '/home/garrett/.config/Code/GPUCache/data_2' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/GrShaderCache/GPUCache/data_2' '/home/garrett/.config/Code/GPUCache/data_2' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/GPUCache/data_2' '/home/garrett/.config/Code/GPUCache/data_2' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/GPUCache/data_2' '/home/garrett/.config/Code/GPUCache/data_2' # duplicate

original_cmd  '/home/garrett/.config/Bitwarden/GPUCache/data_3' # original
remove_cmd    '/home/garrett/.config/VIA/GPUCache/data_3' '/home/garrett/.config/Bitwarden/GPUCache/data_3' # duplicate
remove_cmd    '/home/garrett/.config/skypeforlinux/GPUCache/data_3' '/home/garrett/.config/Bitwarden/GPUCache/data_3' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/ShaderCache/GPUCache/data_3' '/home/garrett/.config/Bitwarden/GPUCache/data_3' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/GPUCache/data_3' '/home/garrett/.config/Bitwarden/GPUCache/data_3' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/GPUCache/data_3' '/home/garrett/.config/Bitwarden/GPUCache/data_3' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/GPUCache/data_3' '/home/garrett/.config/Bitwarden/GPUCache/data_3' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/ShaderCache/GPUCache/data_3' '/home/garrett/.config/Bitwarden/GPUCache/data_3' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/GPUCache/data_3' '/home/garrett/.config/Bitwarden/GPUCache/data_3' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/GPUCache/data_3' '/home/garrett/.config/Bitwarden/GPUCache/data_3' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/GPUCache/data_3' '/home/garrett/.config/Bitwarden/GPUCache/data_3' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/GPUCache/data_3' '/home/garrett/.config/Bitwarden/GPUCache/data_3' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Network Persistent State' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Network Persistent State' '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Network Persistent State' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Session Storage/000003.log' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Session Storage/000003.log' '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Session Storage/000003.log' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Session Storage/000003.log' '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Session Storage/000003.log' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Session Storage/000003.log' '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Session Storage/000003.log' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/SSLErrorAssistant/7/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/SSLErrorAssistant/7/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/SSLErrorAssistant/7/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/SSLErrorAssistant/7/ssl_error_assistant.pb' # original
remove_cmd    '/home/garrett/.config/google-chrome/SSLErrorAssistant/7/ssl_error_assistant.pb' '/home/garrett/.config/google-chrome-unstable/SSLErrorAssistant/7/ssl_error_assistant.pb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/OriginTrials/1.0.0.5/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/OriginTrials/1.0.0.5/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/OriginTrials/1.0.0.5/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Subresource Filter/Unindexed Rules/9.18.0/LICENSE.txt' # original
remove_cmd    '/home/garrett/.config/google-chrome/Subresource Filter/Unindexed Rules/9.18.0/LICENSE.txt' '/home/garrett/.config/google-chrome-unstable/Subresource Filter/Unindexed Rules/9.18.0/LICENSE.txt' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Crowd Deny/2020.12.6.1201/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Crowd Deny/2020.12.6.1201/manifest.json' '/home/garrett/.config/google-chrome-unstable/Crowd Deny/2020.12.6.1201/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/male_names.txt' # original
remove_cmd    '/home/garrett/.config/google-chrome/ZxcvbnData/1/male_names.txt' '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/male_names.txt' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/manifest.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/female_names.txt' # original
remove_cmd    '/home/garrett/.config/google-chrome/ZxcvbnData/1/female_names.txt' '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/female_names.txt' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/128.png' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/128.png' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/128.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/128.png' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/128.png' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/128.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/hu/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/hu/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/hu/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/de/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/de/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/de/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/da/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/da/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/da/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/es/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/es/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/es/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ru/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ru/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ru/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/lv/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/lv/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/lv/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Crowd Deny/2020.12.6.1201/Preload Data' # original
remove_cmd    '/home/garrett/.config/google-chrome/Crowd Deny/2020.12.6.1201/Preload Data' '/home/garrett/.config/google-chrome-unstable/Crowd Deny/2020.12.6.1201/Preload Data' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/uk/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/uk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/uk/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ja/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ja/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ja/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/se/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/se/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/se/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/no/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/no/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/no/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/th/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/th/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/th/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/bg/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/bg/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/bg/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/hi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/hi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/hi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ar/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ar/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ar/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/el/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/el/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/el/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/en/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/en/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/en/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/bg/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/bg/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/bg/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/icon_128.png' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/icon_128.png' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/icon_128.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/cs/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/cs/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/cs/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/fi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/fi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/fi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/lt/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/lt/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/lt/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/sv/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/sv/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/sv/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/sr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/sr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/sr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/uk/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/uk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/uk/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/icon_128.png' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/icon_128.png' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/icon_128.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/bg/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/bg/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/bg/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/hu/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/hu/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/hu/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/icon_16.png' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/icon_16.png' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/icon_16.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/hu/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/hu/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/hu/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/main.js' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/main.js' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/main.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/no/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/no/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/no/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/zh_TW/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/zh_TW/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/zh_TW/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/pt_BR/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/pt_BR/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/pt_BR/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ko/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ko/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ko/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/es_419/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/es_419/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/es_419/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/zh_CN/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/zh_CN/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/zh_CN/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/sr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/sr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/sr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/main.js' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/main.js' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/main.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/main.js' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/main.js' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/main.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Secure Preferences' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Secure Preferences' '/home/garrett/.config/google-chrome-unstable/Default/Secure Preferences' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/manifest.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/manifest.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/manifest.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/bg/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/bg/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/bg/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/README' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/README' '/home/garrett/.config/google-chrome-unstable/Default/README' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/tr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/tr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/tr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/vi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/vi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/vi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/cs/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/cs/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/cs/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/icon_128.png' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/icon_128.png' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/icon_128.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ja/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ja/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ja/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/de/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/de/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/de/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/en_GB/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/en_GB/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/en_GB/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/es/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/es/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/es/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/sv/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/sv/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/sv/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/pt_PT/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/pt_PT/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/pt_PT/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/id/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/id/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/id/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/el/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/el/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/el/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/en_US/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/en_US/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/en_US/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/da/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/da/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/da/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/de/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/de/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/de/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/et/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/et/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/et/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/nl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/nl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/nl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/fi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/fi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/fi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/fi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/fi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/fi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/hi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/hi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/hi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/hi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/hi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/hi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/hu/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/hu/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/hu/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/pt_PT/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/pt_PT/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/pt_PT/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ja/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ja/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ja/messages.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/string-width/node_modules/strip-ansi/index.js' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/cliui/node_modules/strip-ansi/index.js' '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/string-width/node_modules/strip-ansi/index.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ko/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ko/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ko/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ko/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ko/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ko/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/lv/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/lv/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/lv/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/no/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/no/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/no/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/sk/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/sk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/sk/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/tr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/tr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/tr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/fil/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/fil/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/fil/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/lv/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/lv/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/lv/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/es_419/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/es_419/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/es_419/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/tr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/tr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/tr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/de/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/de/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/de/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/uk/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/uk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/uk/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/id/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/id/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/id/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/fr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/fr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/fr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/zh_CN/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/zh_CN/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/zh_CN/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/it/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/it/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/it/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/vi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/vi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/vi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_metadata/computed_hashes.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_metadata/computed_hashes.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_metadata/computed_hashes.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_metadata/computed_hashes.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_metadata/computed_hashes.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_metadata/computed_hashes.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_metadata/computed_hashes.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_metadata/computed_hashes.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_metadata/computed_hashes.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/manifest.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/bg/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/bg/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/bg/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ro/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ro/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ro/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ca/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ca/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ca/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/128.png' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/128.png' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/128.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/el/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/el/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/el/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/en_US/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/en_GB/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/en_US/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/en_US/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/en_US/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/en_GB/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/en_US/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/zh_TW/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/zh_TW/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/zh_TW/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/cs/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/cs/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/cs/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/fr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/fr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/fr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/string-width/node_modules/ansi-regex/index.js' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/cliui/node_modules/ansi-regex/index.js' '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/string-width/node_modules/ansi-regex/index.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/hr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/hr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/hr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/id/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/id/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/id/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ja/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ja/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ja/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/lt/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/lt/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/lt/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ca/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ca/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ca/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ms/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ms/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ms/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/id/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/id/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/id/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/nl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/nl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/nl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/no/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/no/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/no/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ro/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ro/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ro/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ko/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ko/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ko/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/fr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/fr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/fr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/sl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/sl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/sl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/pt_BR/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/pt_BR/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/pt_BR/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/sr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/sr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/sr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/7e8fa9ada00f3bee1142d342f9d8788a4870de67/email-frame.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/3f961d90e41a81116d692ea4f82f48754cf506b3/content/7e8fa9ada00f3bee1142d342f9d8788a4870de67/email-frame.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/7e8fa9ada00f3bee1142d342f9d8788a4870de67/email-frame.json' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/7e8fa9ada00f3bee1142d342f9d8788a4870de67/email-frame.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/7e8fa9ada00f3bee1142d342f9d8788a4870de67/email-frame.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/tr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/tr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/tr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/uk/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/uk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/uk/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/zh_TW/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/zh_TW/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/zh_TW/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/zh_CN/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/zh_CN/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/zh_CN/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/manifest.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/signal-exit/signals.js' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/signal-exit/signals.js' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/signal-exit/signals.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/bg/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/bg/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/bg/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/et/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/et/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/et/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/el/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/el/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/el/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/fr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/fr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/fr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/wrappy/README.md' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/wrappy/README.md' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/wrappy/README.md' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/hr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/hr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/hr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/hi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/hi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/hi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/cs/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/cs/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/cs/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/id/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/id/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/id/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/en_GB/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/en/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/en_GB/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/en_GB/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/en_GB/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/en/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/en_GB/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/ja/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/ja/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/ja/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/manifest.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/lt/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/lt/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/lt/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/ko/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/ko/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/ko/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/lv/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/lv/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/lv/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/pl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/pl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/pl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/pt_BR/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/pt_BR/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/pt_BR/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/es_419/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/es_419/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/es_419/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/pt_PT/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/pt_PT/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/pt_PT/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/ru/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/ru/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/ru/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/ro/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/ro/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/ro/messages.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/shebang-command/package.json' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/shebang-command/package.json' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/shebang-command/package.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/fi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/fi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/fi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/da/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/da/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/da/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/nl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/nl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/nl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/sl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/sl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/sl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/sr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/sr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/sr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/sk/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/sk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/sk/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/sv/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/sv/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/sv/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/tr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/tr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/tr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/th/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/th/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/th/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/uk/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/uk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/uk/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/zh_CN/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/zh_CN/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/zh_CN/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/vi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/vi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/vi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/html/craw_window.html' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/html/craw_window.html' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/html/craw_window.html' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/icon_16.png' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/icon_16.png' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/icon_16.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/css/craw_window.css' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/css/craw_window.css' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/css/craw_window.css' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/ZxcvbnData/1/manifest.json' '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/topbar_floating_button_maximize.png' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/topbar_floating_button_maximize.png' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/topbar_floating_button_maximize.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/topbar_floating_button_close.png' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/topbar_floating_button_close.png' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/topbar_floating_button_close.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/topbar_floating_button.png' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/topbar_floating_button.png' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/topbar_floating_button.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/icon_16.png' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/icon_16.png' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/icon_16.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/topbar_floating_button_pressed.png' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/topbar_floating_button_pressed.png' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/topbar_floating_button_pressed.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/topbar_floating_button_hover.png' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/topbar_floating_button_hover.png' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/topbar_floating_button_hover.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/icon_128.png' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/icon_128.png' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/icon_128.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/am/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/am/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/am/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/128.png' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/128.png' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/128.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ne/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ne/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ne/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/iw/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/iw/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/iw/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ca/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ca/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ca/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/km/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/km/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/km/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/id/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/id/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/id/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/hi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/hi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/hi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ta/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ta/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ta/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/bg/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/bg/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/bg/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/es/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/es/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/es/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ru/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ru/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ru/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ro/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ro/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ro/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/fr_CA/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/fr_CA/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/fr_CA/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/cy/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/cy/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/cy/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ko/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ko/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ko/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/zh_HK/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/zh_HK/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/zh_HK/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/kk/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/kk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/kk/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/nl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/nl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/nl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ur/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ur/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ur/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/lo/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/lo/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/lo/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/sl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/sl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/sl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/isexe/README.md' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/isexe/README.md' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/isexe/README.md' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/en_US/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/en_US/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/en_US/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/da/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/da/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/da/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/el/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/el/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/el/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/pa/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/pa/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/pa/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/bn/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/bn/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/bn/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/gu/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/gu/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/gu/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/be/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/be/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/be/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/sr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/sr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/sr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/isexe/windows.js' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/isexe/windows.js' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/isexe/windows.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/cs/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/cs/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/cs/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/hr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/hr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/hr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/zu/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/zu/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/zu/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/fi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/fi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/fi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/mr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/mr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/mr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/sk/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/sk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/sk/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/si/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/si/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/si/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/kn/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/kn/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/kn/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/my/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/my/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/my/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/sw/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/sw/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/sw/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/lt/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/lt/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/lt/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/pt_PT/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/pt_PT/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/pt_PT/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/te/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/te/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/te/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/en_GB/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/en_GB/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/en_GB/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/zh_TW/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/zh_TW/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/zh_TW/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/et/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/et/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/et/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/no/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/no/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/no/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/pt_BR/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/pt_BR/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/pt_BR/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/af/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/af/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/af/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/fil/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/fil/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/fil/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/gl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/gl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/gl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/uk/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/uk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/uk/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/eu/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/eu/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/eu/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/mn/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/mn/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/mn/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ja/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ja/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ja/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/hy/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/hy/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/hy/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/de/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/de/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/de/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ka/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ka/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ka/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/fa/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/fa/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/fa/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/zh_CN/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/zh_CN/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/zh_CN/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ms/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ms/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ms/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/is/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/is/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/is/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/fr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/fr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/fr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/az/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/az/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/az/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/pl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/pl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/pl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/feedback.css' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/feedback.css' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/feedback.css' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ml/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ml/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ml/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/feedback.html' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/feedback.html' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/feedback.html' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_metadata/computed_hashes.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_metadata/computed_hashes.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_metadata/computed_hashes.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/lt/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/lt/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/lt/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/lv/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/lv/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/lv/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/pl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/pl/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/pl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ro/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/ro/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ro/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/pt/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/pt/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/pt/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/sl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/sl/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/sl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ms/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/ms/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ms/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ru/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/ru/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ru/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/sw/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/sw/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/sw/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/tr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/tr/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/tr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/sv/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/sv/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/sv/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ru/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ru/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ru/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ta/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/ta/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ta/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/th/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/th/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/th/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/vi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/vi/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/vi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/zh_TW/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/zh_TW/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/zh_TW/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_metadata/computed_hashes.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_metadata/computed_hashes.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_metadata/computed_hashes.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/zh/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/zh/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/zh/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/te/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/te/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/te/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/uk/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/uk/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/uk/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/manifest.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/nb/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/nb/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/nb/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/previews_opt_out.db' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/previews_opt_out.db' '/home/garrett/.config/google-chrome-unstable/Default/previews_opt_out.db' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/heavy_ad_intervention_opt_out.db' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/heavy_ad_intervention_opt_out.db' '/home/garrett/.config/google-chrome-unstable/Default/heavy_ad_intervention_opt_out.db' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/cs/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/cs/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/cs/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/am/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/am/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/am/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/de/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/de/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/de/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ar/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/ar/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ar/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/bg/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/bg/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/bg/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/bn/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/bn/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/bn/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ca/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/ca/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ca/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/da/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/da/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/da/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/es/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/es/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/es/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/el/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/el/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/el/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/en/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/en/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/en/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/et/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/et/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/et/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/fi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/fi/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/fi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/fil/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/fil/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/fil/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/hu/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/hu/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/hu/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/hr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/hr/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/hr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/gu/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/gu/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/gu/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/id/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/id/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/id/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ko/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/ko/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ko/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/iw/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/iw/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/iw/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/kn/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/kn/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/kn/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/it/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/it/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/it/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/hi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/hi/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/hi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ja/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/ja/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ja/messages.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/about/img/logo.svg' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Raw/login/images/logo.svg' '/home/garrett/.config/spicetify/Extracted/Raw/about/img/logo.svg' # duplicate

original_cmd  '/home/garrett/.config/nano/nano-syntax-highlighting/html.j2.nanorc' # original
remove_cmd    '/home/garrett/.config/nano/nano-syntax-highlighting/html.nanorc' '/home/garrett/.config/nano/nano-syntax-highlighting/html.j2.nanorc' # duplicate
remove_cmd    '/home/garrett/.config/nano/nano-syntax-highlighting/twig.nanorc' '/home/garrett/.config/nano/nano-syntax-highlighting/html.j2.nanorc' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/buddy-list/img/empty-friend-feed-top-1.svg' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Raw/login/images/background.svg' '/home/garrett/.config/spicetify/Extracted/Raw/buddy-list/img/empty-friend-feed-top-1.svg' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/hu/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/hu/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/hu/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/th/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/th/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/th/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/es_419/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/es_419/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/es_419/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/th/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/th/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/th/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Crowd Deny/2020.12.6.1201/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Crowd Deny/2020.12.6.1201/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/Crowd Deny/2020.12.6.1201/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/TLSDeprecationConfig/3/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/TLSDeprecationConfig/3/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/TLSDeprecationConfig/3/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_crtend_o' # original
remove_cmd    '/home/garrett/.config/google-chrome/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_crtend_o' '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_crtend_o' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_pnacl_json' # original
remove_cmd    '/home/garrett/.config/google-chrome/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_pnacl_json' '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_pnacl_json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_libpnacl_irt_shim_dummy_a' # original
remove_cmd    '/home/garrett/.config/google-chrome/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_libpnacl_irt_shim_dummy_a' '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_libpnacl_irt_shim_dummy_a' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ru/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ru/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ru/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/FileTypePolicies/43/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/FileTypePolicies/43/manifest.json' '/home/garrett/.config/google-chrome-unstable/FileTypePolicies/43/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/pnacl/0.57.44.2492/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AD' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/AD' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AD' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AE' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/AE' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AE' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_libpnacl_irt_shim_a' # original
remove_cmd    '/home/garrett/.config/google-chrome/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_libpnacl_irt_shim_a' '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_libpnacl_irt_shim_a' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AG' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/AG' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AG' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AL' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/AL' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AL' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AM' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/AM' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AM' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AO' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/AO' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AO' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/FileTypePolicies/43/download_file_types.pb' # original
remove_cmd    '/home/garrett/.config/google-chrome/FileTypePolicies/43/download_file_types.pb' '/home/garrett/.config/google-chrome-unstable/FileTypePolicies/43/download_file_types.pb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/FileTypePolicies/43/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/FileTypePolicies/43/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/FileTypePolicies/43/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AR' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/AR' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AR' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AU' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/AU' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AU' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_crtbegin_o' # original
remove_cmd    '/home/garrett/.config/google-chrome/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_crtbegin_o' '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_crtbegin_o' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/no/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/no/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/no/messages.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/03386ba0c408f7d2b4ae666bd2940b3d07036f13/send-and-archive.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/3f961d90e41a81116d692ea4f82f48754cf506b3/content/03386ba0c408f7d2b4ae666bd2940b3d07036f13/send-and-archive.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/03386ba0c408f7d2b4ae666bd2940b3d07036f13/send-and-archive.json' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/0e5965c877d83f64250b4c19dc975fc54bb672d0/content/03386ba0c408f7d2b4ae666bd2940b3d07036f13/send-and-archive.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/03386ba0c408f7d2b4ae666bd2940b3d07036f13/send-and-archive.json' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/5986f64a241009cff575a185214e9af6893391c3/content/03386ba0c408f7d2b4ae666bd2940b3d07036f13/send-and-archive.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/03386ba0c408f7d2b4ae666bd2940b3d07036f13/send-and-archive.json' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/03386ba0c408f7d2b4ae666bd2940b3d07036f13/send-and-archive.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/03386ba0c408f7d2b4ae666bd2940b3d07036f13/send-and-archive.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AZ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/AZ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AZ' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AX' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/AX' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AX' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/fi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/fi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/fi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/pl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/pl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/pl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/page_embed_script.js' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/page_embed_script.js' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/page_embed_script.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BA' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BA' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BA' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BB' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BB' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BB' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/f28873dc0e06a81ef649a0a1699ad79a43267779/send-later.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/f28873dc0e06a81ef649a0a1699ad79a43267779/send-later.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/f28873dc0e06a81ef649a0a1699ad79a43267779/send-later.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BD' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BD' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BD' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BF' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BF' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BF' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BH' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BH' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BH' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/it/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/it/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/it/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BI' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BI' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BI' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BG' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BG' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BG' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/3f961d90e41a81116d692ea4f82f48754cf506b3/content/018e1e7fc7381ddf3e13d071ec3a3bb1680fe31d/theme-colors.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/0e5965c877d83f64250b4c19dc975fc54bb672d0/content/018e1e7fc7381ddf3e13d071ec3a3bb1680fe31d/theme-colors.json' '/home/garrett/.config/Mailspring/compile-cache/less/3f961d90e41a81116d692ea4f82f48754cf506b3/content/018e1e7fc7381ddf3e13d071ec3a3bb1680fe31d/theme-colors.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BN' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BN' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BN' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BO' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BO' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BO' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BR' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BR' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BR' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BM' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BM' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BM' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BS' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BS' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BS' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BT' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BT' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BT' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BY' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BY' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BY' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CA' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/CA' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CA' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BZ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BZ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BZ' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CG' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/CG' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CG' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CF' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/CF' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CF' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CN' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/CN' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CN' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CO' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/CO' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CO' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/zh_TW/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/zh_TW/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/zh_TW/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CM' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/CM' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CM' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/999a98ac76824b3f59eb2f0f241afd31685eef92/account-sidebar.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/999a98ac76824b3f59eb2f0f241afd31685eef92/account-sidebar.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/999a98ac76824b3f59eb2f0f241afd31685eef92/account-sidebar.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CL' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/CL' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CL' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CR' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/CR' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CR' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CV' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/CV' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CV' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CU' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/CU' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CU' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CY' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/CY' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CY' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/he/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/he/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/he/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ar/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ar/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ar/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/DJ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/DJ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/DJ' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/DK' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/DK' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/DK' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CD' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/CD' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CD' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/DM' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/DM' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/DM' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/DO' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/DO' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/DO' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/hu/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/hu/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/hu/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/pl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/pl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/pl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/pt_PT/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/pt_PT/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/pt_PT/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/EH' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/EH' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/EH' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/EE' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/EE' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/EE' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/EG' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/EG' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/EG' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/DZ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/DZ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/DZ' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/de/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/de/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/de/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ES' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/ES' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ES' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/main.html' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/main.html' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/main.html' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/main.html' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/main.html' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/main.html' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/main.html' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/main.html' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/main.html' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/main.html' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/main.html' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/FO' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/FO' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/FO' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/FI' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/FI' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/FI' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GA' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/GA' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GA' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/hr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/hr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/hr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GB' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/GB' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GB' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/uk/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/uk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/uk/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GF' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/GF' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GF' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GG' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/GG' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GG' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GE' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/GE' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GE' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GL' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/GL' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GL' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/pt_PT/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/pt_PT/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/pt_PT/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GM' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/GM' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GM' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/fil/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/fil/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/fil/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/sl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/sl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/sl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/tr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/tr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/tr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ko/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ko/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/ko/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/de/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/de/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/de/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GN' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/GN' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GN' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/fi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/fi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/fi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/it/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/it/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/it/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GQ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/GQ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GQ' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GR' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/GR' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GR' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GW' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/GW' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GW' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GY' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/GY' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GY' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/HN' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/HN' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/HN' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/EC' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/EC' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/EC' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/HR' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/HR' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/HR' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/HT' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/HT' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/HT' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/IM' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/IM' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/IM' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/IL' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/IL' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/IL' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/tr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/tr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/tr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ID' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/ID' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ID' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/JM' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/JM' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/JM' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/05ee776ced33fc1697930e079e264805a8c06005/draft-list.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/05ee776ced33fc1697930e079e264805a8c06005/draft-list.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/05ee776ced33fc1697930e079e264805a8c06005/draft-list.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/IR' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/IR' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/IR' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/JO' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/JO' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/JO' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/IN' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/IN' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/IN' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KI' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/KI' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KI' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KG' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/KG' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KG' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KN' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/KN' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KN' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/en_GB/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/en_GB/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/en_GB/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/it/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/it/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/it/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KM' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/KM' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KM' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KP' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/KP' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KP' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/ca/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/ca/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/ca/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KR' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/KR' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KR' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KH' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/KH' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KH' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LA' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/LA' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LA' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LC' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/LC' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LC' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/JE' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/JE' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/JE' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/path-key/index.js' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/path-key/index.js' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/path-key/index.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/nl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/nl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/nl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/sk/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/sk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/sk/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/nl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/nl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/nl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LI' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/LI' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LI' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/it/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/it/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/it/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LR' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/LR' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LR' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LS' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/LS' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LS' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LK' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/LK' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LK' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LT' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/LT' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LT' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BW' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BW' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BW' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/hi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/hi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/hi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LU' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/LU' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LU' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MA' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MA' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MA' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LY' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/LY' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LY' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MD' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MD' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MD' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MH' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MH' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MH' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ME' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/ME' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ME' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ar/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ar/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/ar/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MM' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MM' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MM' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KY' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/KY' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KY' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MP' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MP' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MP' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LV' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/LV' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LV' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MN' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MN' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MN' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MQ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MQ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MQ' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/shebang-regex/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/path-key/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/p-try/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/shebang-regex/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/lcid/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/decamelize/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/get-stream/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/p-finally/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/strip-eof/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/code-point-at/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/locate-path/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/number-is-nan/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/npm-run-path/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/strip-ansi/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/p-locate/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/is-stream/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/is-fullwidth-code-point/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/path-exists/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/find-up/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/path-key/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/os-locale/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/mem/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/camelcase/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/wrap-ansi/node_modules/string-width/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/ansi-regex/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/wrap-ansi/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/wrap-ansi/node_modules/is-fullwidth-code-point/license' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/path-is-absolute/license' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MR' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MR' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MR' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MS' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MS' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MS' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MU' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MU' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MU' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MV' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MV' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MV' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MY' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MY' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MY' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MW' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MW' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MW' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MZ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MZ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MZ' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MK' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MK' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MK' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MX' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MX' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MX' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/it/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/it/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/it/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/zh_CN/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/zh_CN/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/zh_CN/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NE' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/NE' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NE' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/lv/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/lv/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/lv/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NA' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/NA' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NA' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NG' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/NG' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NG' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/sv/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/sv/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/sv/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NI' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/NI' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NI' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NO' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/NO' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NO' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NP' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/NP' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NP' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NZ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/NZ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NZ' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/OM' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/OM' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/OM' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PA' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/PA' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PA' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GD' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/GD' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GD' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PF' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/PF' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PF' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PG' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/PG' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PG' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PH' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/PH' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PH' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PS' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/PS' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PS' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PR' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/PR' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PR' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/eu/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/eu/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/eu/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/lt/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/lt/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/lt/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/sv/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/sv/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/sv/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PW' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/PW' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PW' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PT' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/PT' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PT' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PL' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/PL' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PL' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/vi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/vi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/vi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/QA' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/QA' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/QA' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PY' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/PY' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PY' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NC' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/NC' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NC' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/sk/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/sk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/sk/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/et/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/et/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/et/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ca/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ca/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ca/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ro/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ro/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ro/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/RS' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/RS' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/RS' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/RO' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/RO' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/RO' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SA' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SA' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SA' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SD' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SD' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SD' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SH' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SH' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SH' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MG' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MG' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MG' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SC' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SC' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SC' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SE' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SE' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SE' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SI' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SI' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SI' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/th/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/th/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/th/messages.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/shebang-command/index.js' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/shebang-command/index.js' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/shebang-command/index.js' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/a9075e70d5d9716019650ad735a2a841d8cbdd2e/mode-switch.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/a9075e70d5d9716019650ad735a2a841d8cbdd2e/mode-switch.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/a9075e70d5d9716019650ad735a2a841d8cbdd2e/mode-switch.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SB' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SB' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SB' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/RU' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/RU' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/RU' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/hi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/hi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/hi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SK' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SK' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SK' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GH' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/GH' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GH' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SJ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SJ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SJ' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GP' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/GP' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GP' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Network Persistent State' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Network Persistent State' '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Network Persistent State' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SL' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SL' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SL' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/el/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/el/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/el/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/th/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/th/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/th/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SM' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SM' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SM' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SN' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SN' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SN' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SO' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SO' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SO' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BE' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BE' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BE' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SR' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SR' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SR' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ar/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ar/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ar/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SS' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SS' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SS' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ST' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/ST' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ST' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/FR' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/FR' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/FR' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SV' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SV' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SV' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Local Extension Settings/ghbmnnjooekpmoecnnnilnnbdlolhkhi/000003.log' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Local Extension Settings/ghbmnnjooekpmoecnnnilnnbdlolhkhi/000003.log' '/home/garrett/.config/google-chrome-unstable/Default/Local Extension Settings/ghbmnnjooekpmoecnnnilnnbdlolhkhi/000003.log' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SX' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SX' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SX' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PM' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/PM' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PM' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TC' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/TC' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TC' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SY' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SY' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SY' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ms/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ms/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ms/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SZ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/SZ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/SZ' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/en_GB/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/en_GB/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/en_GB/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TG' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/TG' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TG' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TD' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/TD' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TD' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/nl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/nl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/nl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TL' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/TL' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TL' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/vi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/vi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/vi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TK' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/TK' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TK' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MF' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/MF' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/MF' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/IE' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/IE' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/IE' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TN' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/TN' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TN' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TO' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/TO' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TO' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TR' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/TR' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TR' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/da/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/da/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/da/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/pt_BR/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/pt_BR/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/pt_BR/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ca/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ca/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ca/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/HK' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/HK' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/HK' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TV' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/TV' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TV' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/da/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/da/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/da/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ms/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ms/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ms/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TW' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/TW' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TW' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/UG' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/UG' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/UG' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/once/README.md' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/once/README.md' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/once/README.md' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TZ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/TZ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TZ' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/UZ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/UZ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/UZ' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/inherits/inherits.js' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/inherits/inherits.js' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/inherits/inherits.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/fil/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/fil/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/fil/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/VC' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/VC' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/VC' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/VG' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/VG' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/VG' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/SSLErrorAssistant/7/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/SSLErrorAssistant/7/manifest.json' '/home/garrett/.config/google-chrome-unstable/SSLErrorAssistant/7/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/VE' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/VE' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/VE' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/VI' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/VI' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/VI' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/shebang-regex/index.js' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/shebang-regex/index.js' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/shebang-regex/index.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/WF' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/WF' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/WF' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/VU' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/VU' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/VU' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/RE' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/RE' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/RE' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/WS' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/WS' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/WS' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ar/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ar/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ar/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/HU' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/HU' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/HU' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/XK' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/XK' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/XK' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/YT' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/YT' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/YT' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/VN' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/VN' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/VN' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TH' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/TH' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TH' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/YE' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/YE' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/YE' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/OriginTrials/1.0.0.5/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/OriginTrials/1.0.0.5/manifest.json' '/home/garrett/.config/google-chrome-unstable/OriginTrials/1.0.0.5/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ZM' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/ZM' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ZM' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ZA' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/ZA' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ZA' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/sr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/sr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/sr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TT' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/TT' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TT' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/pl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/pl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/pl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NU' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/NU' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NU' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ms/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ms/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/ms/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Subresource Filter/Unindexed Rules/9.18.0/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Subresource Filter/Unindexed Rules/9.18.0/manifest.json' '/home/garrett/.config/google-chrome-unstable/Subresource Filter/Unindexed Rules/9.18.0/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/IS' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/IS' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/IS' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/SafetyTips/2533/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/SafetyTips/2533/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/SafetyTips/2533/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/Code/User/workspaceStorage/aa4cb6e533aae0ba8d2b2c92a5aa587a/workspace.json' # original
remove_cmd    '/home/garrett/.config/Code/User/workspaceStorage/0c8a52834fa9639f061480780eaacc07/workspace.json' '/home/garrett/.config/Code/User/workspaceStorage/aa4cb6e533aae0ba8d2b2c92a5aa587a/workspace.json' # duplicate
remove_cmd    '/home/garrett/.config/Code/User/workspaceStorage/a0991d3869615df564fc514afcd29b98/workspace.json' '/home/garrett/.config/Code/User/workspaceStorage/aa4cb6e533aae0ba8d2b2c92a5aa587a/workspace.json' # duplicate
remove_cmd    '/home/garrett/.config/Code/User/workspaceStorage/9e6407b5547c03e02c8addd12ee8dd4d/workspace.json' '/home/garrett/.config/Code/User/workspaceStorage/aa4cb6e533aae0ba8d2b2c92a5aa587a/workspace.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/SafetyTips/2533/safety_tips.pb' # original
remove_cmd    '/home/garrett/.config/google-chrome/SafetyTips/2533/safety_tips.pb' '/home/garrett/.config/google-chrome-unstable/SafetyTips/2533/safety_tips.pb' # duplicate

original_cmd  '/home/garrett/.config/Code/User/workspaceStorage/0c8a52834fa9639f061480780eaacc07/state.vscdb' # original
remove_cmd    '/home/garrett/.config/Code/User/workspaceStorage/0c8a52834fa9639f061480780eaacc07/state.vscdb.backup' '/home/garrett/.config/Code/User/workspaceStorage/0c8a52834fa9639f061480780eaacc07/state.vscdb' # duplicate

original_cmd  '/home/garrett/.config/Code/User/workspaceStorage/f8de2446783fa67ef05a93712c2b9970/state.vscdb' # original
remove_cmd    '/home/garrett/.config/Code/User/workspaceStorage/f8de2446783fa67ef05a93712c2b9970/state.vscdb.backup' '/home/garrett/.config/Code/User/workspaceStorage/f8de2446783fa67ef05a93712c2b9970/state.vscdb' # duplicate

original_cmd  '/home/garrett/.config/Code/User/workspaceStorage/446f417b484a5b8b3133b21fce9f7f62/state.vscdb' # original
remove_cmd    '/home/garrett/.config/Code/User/workspaceStorage/446f417b484a5b8b3133b21fce9f7f62/state.vscdb.backup' '/home/garrett/.config/Code/User/workspaceStorage/446f417b484a5b8b3133b21fce9f7f62/state.vscdb' # duplicate

original_cmd  '/home/garrett/.config/Code/User/workspaceStorage/43975e3152ea6c741d574a2a8a3be59d/state.vscdb' # original
remove_cmd    '/home/garrett/.config/Code/User/workspaceStorage/43975e3152ea6c741d574a2a8a3be59d/state.vscdb.backup' '/home/garrett/.config/Code/User/workspaceStorage/43975e3152ea6c741d574a2a8a3be59d/state.vscdb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/es/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/es/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/es/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/pl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/pl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/pl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/fr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/fr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/fr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/lt/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/lt/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/lt/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/sl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/sl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/sl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/pt_BR/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/pt_BR/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/pt_BR/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/lv/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/lv/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/lv/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/id/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/id/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/id/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/lt/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/lt/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/lt/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/fil/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/fil/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/fil/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ro/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ro/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ro/messages.json' # duplicate

original_cmd  '/home/garrett/.config/Code/User/workspaceStorage/b92824fb6cf3c0f91e182362392012e2/state.vscdb' # original
remove_cmd    '/home/garrett/.config/Code/User/workspaceStorage/b92824fb6cf3c0f91e182362392012e2/state.vscdb.backup' '/home/garrett/.config/Code/User/workspaceStorage/b92824fb6cf3c0f91e182362392012e2/state.vscdb' # duplicate

original_cmd  '/home/garrett/.config/Code/User/workspaceStorage/60d741349e778babb13b28c05e963938/state.vscdb' # original
remove_cmd    '/home/garrett/.config/Code/User/workspaceStorage/60d741349e778babb13b28c05e963938/state.vscdb.backup' '/home/garrett/.config/Code/User/workspaceStorage/60d741349e778babb13b28c05e963938/state.vscdb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ml/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/_locales/ml/messages.json' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/_locales/ml/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/sk/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/sk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/sk/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/lv/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/lv/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/lv/messages.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/genre/css/genre.css' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Raw/hub/css/hub.css' '/home/garrett/.config/spicetify/Extracted/Raw/genre/css/genre.css' # duplicate
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Raw/browse/css/browse.css' '/home/garrett/.config/spicetify/Extracted/Raw/genre/css/genre.css' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/inherits/inherits_browser.js' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/inherits/inherits_browser.js' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/inherits/inherits_browser.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/en/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/en/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/en/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/es/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/es/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/es/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GT' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/GT' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/GT' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/US' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/US' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/US' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/pnacl/0.57.44.2492/manifest.json' '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/artist/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/artist/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/artist/index.html' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/fil/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/fil/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/fil/messages.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/zlink/libs/ad-formats/images/logo_spotlight.svg' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Raw/browse/libs/ad-formats/images/logo_spotlight.svg' '/home/garrett/.config/spicetify/Extracted/Raw/zlink/libs/ad-formats/images/logo_spotlight.svg' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/browse/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/browse/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/browse/index.html' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/nb/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/nb/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/nb/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ER' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/ER' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ER' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/chart/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/chart/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/chart/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/collection/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/collection/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/collection/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/collection-album/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/collection-album/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/collection-album/index.html' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CI' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/CI' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CI' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/collection-artist/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/collection-artist/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/collection-artist/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/collection-songs/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/collection-songs/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/collection-songs/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/collection-album/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/collection-album/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/collection-album/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/concerts/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/concerts/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/concerts/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/concert/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/concert/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/concert/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/findfriends/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/findfriends/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/findfriends/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/collection-songs/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/collection-songs/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/collection-songs/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/full-screen-modal/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/full-screen-modal/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/full-screen-modal/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/full-screen-modal/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/full-screen-modal/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/full-screen-modal/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/collection-artist/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/collection-artist/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/collection-artist/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/error/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/error/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/error/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/genre/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/genre/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/genre/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/glue-resources/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/glue-resources/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/glue-resources/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/hub/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/hub/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/hub/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/hub/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/hub/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/hub/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KZ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/KZ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KZ' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/findfriends/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/findfriends/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/findfriends/index.html' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/e691db14e75304a4db4b6ca0f6adcbb43b1644cf/find-in-thread.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/e691db14e75304a4db4b6ca0f6adcbb43b1644cf/find-in-thread.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/e691db14e75304a4db4b6ca0f6adcbb43b1644cf/find-in-thread.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/legacy-lyrics/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/legacy-lyrics/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/legacy-lyrics/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/login/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/login/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/login/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Themed/browse/css/browse.css' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/genre/css/genre.css' '/home/garrett/.config/spicetify/Extracted/Themed/browse/css/browse.css' # duplicate
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/hub/css/hub.css' '/home/garrett/.config/spicetify/Extracted/Themed/browse/css/browse.css' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/it/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/it/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/it/messages.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/lyrics/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/lyrics/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/lyrics/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/legacy-lyrics/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/legacy-lyrics/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/legacy-lyrics/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/playlist/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/playlist/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/playlist/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/playlist-folder/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/playlist-folder/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/playlist-folder/index.html' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/wrappy/package.json' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/wrappy/package.json' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/wrappy/package.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/playlist-folder/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/playlist-folder/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/playlist-folder/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/queue/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/queue/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/queue/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/about/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/about/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/about/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/chart/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/chart/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/chart/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/queue/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/queue/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/queue/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/genre/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/genre/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/genre/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/error/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/error/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/error/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/login/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/login/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/login/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/artist/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/artist/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/artist/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/browse/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/browse/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/browse/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/lyrics/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/lyrics/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/lyrics/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/search/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/search/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/search/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/search/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/search/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/search/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/show/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/show/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/show/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/settings/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/settings/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/settings/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/show/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/show/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/show/index.html' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/icon_16.png' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/icon_16.png' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/icon_16.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KE' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/KE' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KE' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/vi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/vi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/_locales/vi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/JP' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/JP' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/JP' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/cs/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/cs/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/cs/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NR' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/NR' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NR' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/manifest.json' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/en_US/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/en_US/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/en_US/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/RW' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/RW' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/RW' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ru/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ru/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/ru/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CZ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/CZ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CZ' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/et/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/et/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/et/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AT' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/AT' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AT' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/station/css/station.css' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/station/css/station.css' '/home/garrett/.config/spicetify/Extracted/Raw/station/css/station.css' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/station/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/station/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/station/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/profile/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/profile/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/profile/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/concert/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/concert/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/concert/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/station/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/station/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/station/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/stations/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/stations/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/stations/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/buddy-list/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/buddy-list/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/buddy-list/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/playlist/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/playlist/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/playlist/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/stations/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/stations/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/stations/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/concerts/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/concerts/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/concerts/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/licenses/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/licenses/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/licenses/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/settings/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/settings/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/settings/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/xpui/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/xpui/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/xpui/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/xpui/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/xpui/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/xpui/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/zlink/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/zlink/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/zlink/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ML' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/ML' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ML' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/profile/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/profile/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/profile/index.html' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KW' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/KW' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/KW' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NL' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/NL' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/NL' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/UA' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/UA' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/UA' # duplicate

original_cmd  '/home/garrett/.config/nano/nano-syntax-highlighting/git.nanorc' # original
remove_cmd    '/home/garrett/.config/nano/nano-syntax-highlighting/gitcommit.nanorc' '/home/garrett/.config/nano/nano-syntax-highlighting/git.nanorc' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AF' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/AF' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AF' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/buddy-list/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/buddy-list/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/buddy-list/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/collection/manifest.json' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/collection/manifest.json' '/home/garrett/.config/spicetify/Extracted/Raw/collection/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/Code/Code Cache/js/index-dir/the-real-index' # original
remove_cmd    '/home/garrett/.config/Code/Code Cache/wasm/index-dir/the-real-index' '/home/garrett/.config/Code/Code Cache/js/index-dir/the-real-index' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/da/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/da/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/da/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/pt_BR/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/pt_BR/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/pt_BR/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/el/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/el/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/el/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/sk/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/sk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pjkljhegncpnkpknbcohdijeoejaedia/8.3_0/_locales/sk/messages.json' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/which/README.md' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/which/README.md' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/which/README.md' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/cs/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/cs/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/cs/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/es_419/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/es/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/es_419/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/es_419/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/es_419/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/es/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/apdfllckaahabafndbhieahigkjlhalf/14.5_0/_locales/es_419/messages.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/eo/6d/eo6dnu4uxnqjdwrbtpbjxqws9wa6nigh1r7cv4jiz/Unnamed Image.gif' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/nu/gt/nugtj8ne2awafkdqkiragqjou8gczanyuvfce47bp/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/eo/6d/eo6dnu4uxnqjdwrbtpbjxqws9wa6nigh1r7cv4jiz/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/kx/kn/kxknhr2n1ckenpgusdokurqbdbyrx3mwwg9i4a6ns/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/eo/6d/eo6dnu4uxnqjdwrbtpbjxqws9wa6nigh1r7cv4jiz/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/v5/ya/v5yazxuywa4ayr5dyvytusyukmw4bccpqfpmtmsnm/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/eo/6d/eo6dnu4uxnqjdwrbtpbjxqws9wa6nigh1r7cv4jiz/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/ee/6a/ee6a9es9cyaxccbh7ceeylpebsjjw56wr1uzifzbv/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/eo/6d/eo6dnu4uxnqjdwrbtpbjxqws9wa6nigh1r7cv4jiz/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/qh/5j/qh5jmuuu3p8xkdvgno4f2map3nkyqywwvzhrkq97h/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/eo/6d/eo6dnu4uxnqjdwrbtpbjxqws9wa6nigh1r7cv4jiz/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/h4/xz/h4xzfpvga867vdv9cpn9wymz7swbnfy1twnj2x3cc/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/eo/6d/eo6dnu4uxnqjdwrbtpbjxqws9wa6nigh1r7cv4jiz/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/pm/ek/pmekdpmbrin9dufzgfn4eds6tfkbgjsfg8get2onx/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/eo/6d/eo6dnu4uxnqjdwrbtpbjxqws9wa6nigh1r7cv4jiz/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/nr/qa/nrqauswjgivwbgcftqx8ifhhspzg2tygko5ptfjv7/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/eo/6d/eo6dnu4uxnqjdwrbtpbjxqws9wa6nigh1r7cv4jiz/Unnamed Image.gif' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/61/db/61dbsjnidjynvcb1wday79msh4crdqcrekhabaxw4/Unnamed Image.gif' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/mc/jl/mcjludvf48uvn6gaqvimhwgatpvz2mdaabnuzwh19/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/61/db/61dbsjnidjynvcb1wday79msh4crdqcrekhabaxw4/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/lf/wi/lfwijm3qsayukhy5xfzcfnuu5q3f4n4xxqogqcqlx/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/61/db/61dbsjnidjynvcb1wday79msh4crdqcrekhabaxw4/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/6w/dd/6wddebbfmvdlrx1cnysesv67us4k3xlr5yeteygpd/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/61/db/61dbsjnidjynvcb1wday79msh4crdqcrekhabaxw4/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/fp/bg/fpbgvg3yzwp9dgdrf15562vabste5sebmuxtuhrxu/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/61/db/61dbsjnidjynvcb1wday79msh4crdqcrekhabaxw4/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/hb/xa/hbxan4zvywfnnjyinimbaartebeewlqrj7zhm9cjr/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/61/db/61dbsjnidjynvcb1wday79msh4crdqcrekhabaxw4/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/5e/cu/5ecuvgrt3juytbtgyw7ddpmsd26q4fkn9njnslc4q/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/61/db/61dbsjnidjynvcb1wday79msh4crdqcrekhabaxw4/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/t5/dz/t5dzn53ipxmmys9q4d6zwomfedc5gvpu9ehd4obhx/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/61/db/61dbsjnidjynvcb1wday79msh4crdqcrekhabaxw4/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/mf/mh/mfmhvu7vor2kqvtqrofcrd7jif55vehv6kqular73/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/61/db/61dbsjnidjynvcb1wday79msh4crdqcrekhabaxw4/Unnamed Image.gif' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/in/xe/inxe8rdgtdhxv4mwcxblsv2gnbtn8ufbsgcsispgs/Unnamed Image.gif' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/h3/a3/h3a3hf6rgqau4sk7uyzqq9kjtzupxdgdfqls1pjkd/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/in/xe/inxe8rdgtdhxv4mwcxblsv2gnbtn8ufbsgcsispgs/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/p6/ff/p6ffxfittw7uvgaznt6aamupvezpjghzhlbdqo5ek/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/in/xe/inxe8rdgtdhxv4mwcxblsv2gnbtn8ufbsgcsispgs/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/f1/be/f1beskkz32obfqppmvpa5vrw34apcgyxpmm2y38fv/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/in/xe/inxe8rdgtdhxv4mwcxblsv2gnbtn8ufbsgcsispgs/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/uq/yg/uqygdghwhqbrrw3rtompp587vpcc3ee6rqbveackr/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/in/xe/inxe8rdgtdhxv4mwcxblsv2gnbtn8ufbsgcsispgs/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/sw/e4/swe4vokghlu5y9kur1te3kvfmpfsxxpavqisxyr7q/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/in/xe/inxe8rdgtdhxv4mwcxblsv2gnbtn8ufbsgcsispgs/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/ae/bd/aebd6nf4gqwqchzvetz7b8fln2lijvau4mbcqsh39/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/in/xe/inxe8rdgtdhxv4mwcxblsv2gnbtn8ufbsgcsispgs/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/4r/dy/4rdyxy1pyog53uygv9dggf31cdzgbu9npzefsvdgs/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/in/xe/inxe8rdgtdhxv4mwcxblsv2gnbtn8ufbsgcsispgs/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/sv/en/svenrrpngbyurkwrgpx5ar6u864p1ywj31cit15dl/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/in/xe/inxe8rdgtdhxv4mwcxblsv2gnbtn8ufbsgcsispgs/Unnamed Image.gif' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/shebang-command/license' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_voice/node_modules/shebang-command/license' '/home/garrett/.config/discord/0.0.13/modules/discord_utils/node_modules/shebang-command/license' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/ht/yz/htyzuvmt8sr9rji4w3npstjzh8pmzgqrqlcyxzp2q/Unnamed Image.png' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/rx/2q/rx2qzmlwyeg88a9gvajptjxymzxwauxbnqqyzdlta/Unnamed Image.png' '/home/garrett/.config/Mailspring/files/ht/yz/htyzuvmt8sr9rji4w3npstjzh8pmzgqrqlcyxzp2q/Unnamed Image.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/7w/cv/7wcv8den9m4vjknsnjcgpshvvyhutn5qwzsucwp54/Unnamed Image.png' '/home/garrett/.config/Mailspring/files/ht/yz/htyzuvmt8sr9rji4w3npstjzh8pmzgqrqlcyxzp2q/Unnamed Image.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/my/y1/myy1x2t6zrm4ewzgkywtpy4gumabzke9cewqgg9x6/Unnamed Image.png' '/home/garrett/.config/Mailspring/files/ht/yz/htyzuvmt8sr9rji4w3npstjzh8pmzgqrqlcyxzp2q/Unnamed Image.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/wg/2c/wg2cg22uhugqzatsermrcsm1wkach5jc7jua1fnuj/Unnamed Image.png' '/home/garrett/.config/Mailspring/files/ht/yz/htyzuvmt8sr9rji4w3npstjzh8pmzgqrqlcyxzp2q/Unnamed Image.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/3n/w3/3nw3kddrusywaqpd89jruznskgpvrphhgzooymmsx/Unnamed Image.png' '/home/garrett/.config/Mailspring/files/ht/yz/htyzuvmt8sr9rji4w3npstjzh8pmzgqrqlcyxzp2q/Unnamed Image.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/x3/jf/x3jf6k6fjsb97bf32w15bx4rd68y8cov18rhy6qzz/Unnamed Image.png' '/home/garrett/.config/Mailspring/files/ht/yz/htyzuvmt8sr9rji4w3npstjzh8pmzgqrqlcyxzp2q/Unnamed Image.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/ws/vn/wsvnrotlrnh8wwjylvq8c65puxyth34ecbutrcdb4/Unnamed Image.png' '/home/garrett/.config/Mailspring/files/ht/yz/htyzuvmt8sr9rji4w3npstjzh8pmzgqrqlcyxzp2q/Unnamed Image.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/pw/eh/pwehgjxg6m5twjsw1civm5h7vyhtyptovisrhaj2v/Unnamed Image.png' '/home/garrett/.config/Mailspring/files/ht/yz/htyzuvmt8sr9rji4w3npstjzh8pmzgqrqlcyxzp2q/Unnamed Image.png' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/3q/77/3q77mwred8px9iqu9whm19ajnyweyxk9xxtefvzwe/Unnamed Image.gif' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/8d/jw/8djw1ngcakbbzubcktdnfeykqosu3nik38djdagw7/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/3q/77/3q77mwred8px9iqu9whm19ajnyweyxk9xxtefvzwe/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/6m/hp/6mhpwyxpjdt2efbuc54dhtuidqfkltxl2e13qyysk/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/3q/77/3q77mwred8px9iqu9whm19ajnyweyxk9xxtefvzwe/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/wb/js/wbjshujrzgrn7efywxffrz7swgr46wj3yzke9s1sp/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/3q/77/3q77mwred8px9iqu9whm19ajnyweyxk9xxtefvzwe/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/n2/ht/n2ht6yfjb14deuytmycbfcqwzzfbqzew2grdg23si/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/3q/77/3q77mwred8px9iqu9whm19ajnyweyxk9xxtefvzwe/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/od/xa/odxacmv9jo6p9d951rpb1tfge6eylyhj4zp9k33uc/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/3q/77/3q77mwred8px9iqu9whm19ajnyweyxk9xxtefvzwe/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/5f/kq/5fkqptfdapycuhk2tquq5wxe9cigcgbxsslahsmgm/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/3q/77/3q77mwred8px9iqu9whm19ajnyweyxk9xxtefvzwe/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/dr/y2/dry2gkvrxeuljfzrykybu6am63u2t78wyronksebb/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/3q/77/3q77mwred8px9iqu9whm19ajnyweyxk9xxtefvzwe/Unnamed Image.gif' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/4h/wo/4hwoqpjykk721wfueckhyynqvkvzhg6lpk3pkf22c/Unnamed Image.gif' '/home/garrett/.config/Mailspring/files/3q/77/3q77mwred8px9iqu9whm19ajnyweyxk9xxtefvzwe/Unnamed Image.gif' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BJ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BJ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BJ' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PE' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/PE' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PE' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/UY' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/UY' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/UY' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/gw/oe/gwoemyynm1ybwkylpa6myouwtmjvgcbh3hwc2pwhn/SkyCode_32pct_34.png' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/qg/l5/qgl5isgiipxepen8qkiy78kgguj31whdgoupr44om/SkyCode_32pct_34.png' '/home/garrett/.config/Mailspring/files/gw/oe/gwoemyynm1ybwkylpa6myouwtmjvgcbh3hwc2pwhn/SkyCode_32pct_34.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/of/em/ofemnbs27fjv6mdrvmmfbs5z29e2cdcbqqboplhav/SkyCode_32pct_34.png' '/home/garrett/.config/Mailspring/files/gw/oe/gwoemyynm1ybwkylpa6myouwtmjvgcbh3hwc2pwhn/SkyCode_32pct_34.png' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/gg/2h/gg2hedlygeftlgkw9tecldkhazer7vwayyxtlxcfx/SkyCode_32pct_11.png' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/5b/mg/5bmgz6b6hmzbqfjt95glu8j68ppkqq1ax7x2pfyfb/SkyCode_32pct_11.png' '/home/garrett/.config/Mailspring/files/gg/2h/gg2hedlygeftlgkw9tecldkhazer7vwayyxtlxcfx/SkyCode_32pct_11.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/vi/tu/vituzp4sjy1fgfpahdmsk4icxxpkjavkeuzle5s4g/SkyCode_32pct_11.png' '/home/garrett/.config/Mailspring/files/gg/2h/gg2hedlygeftlgkw9tecldkhazer7vwayyxtlxcfx/SkyCode_32pct_11.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/9y/jd/9yjdu2xl9cwrdhjnwcwti5ch2y2qpflmdf6rosyxu/SkyCode_32pct_11.png' '/home/garrett/.config/Mailspring/files/gg/2h/gg2hedlygeftlgkw9tecldkhazer7vwayyxtlxcfx/SkyCode_32pct_11.png' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/ng/en/ngenndf2sd5bvzrj5dadm7lmrxqgq2tupt6xsyzrt/SkyCode_32pct_26.png' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/nd/d7/ndd7pnpg175vysiu9q3mc4bvitwoh4dkgl5xnnget/SkyCode_32pct_26.png' '/home/garrett/.config/Mailspring/files/ng/en/ngenndf2sd5bvzrj5dadm7lmrxqgq2tupt6xsyzrt/SkyCode_32pct_26.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/ar/w1/arw1hy9dsxt9wf3lkk3cfm78bjv2odvt5uunxtcnd/SkyCode_32pct_26.png' '/home/garrett/.config/Mailspring/files/ng/en/ngenndf2sd5bvzrj5dadm7lmrxqgq2tupt6xsyzrt/SkyCode_32pct_26.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/ru/6j/ru6jhm69yynwqnffz8txydfnzywzmnvcpphl988u8/SkyCode_32pct_26.png' '/home/garrett/.config/Mailspring/files/ng/en/ngenndf2sd5bvzrj5dadm7lmrxqgq2tupt6xsyzrt/SkyCode_32pct_26.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CH' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/CH' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CH' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/mk/vz/mkvzlxpu6fwhogwyxyhfcfclss9uo7tahuazxedtl/Election-Polling-Box-icon.png' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/cq/ga/cqgaatm7ttgdku19jmc3npbnjkgdppzjzf48mc8jn/Election-Polling-Box-icon.png' '/home/garrett/.config/Mailspring/files/mk/vz/mkvzlxpu6fwhogwyxyhfcfclss9uo7tahuazxedtl/Election-Polling-Box-icon.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/ek/c9/ekc9c9thtcpqarse2ljtpfnpqq2zzslk3xyjohcs7/Election-Polling-Box-icon.png' '/home/garrett/.config/Mailspring/files/mk/vz/mkvzlxpu6fwhogwyxyhfcfclss9uo7tahuazxedtl/Election-Polling-Box-icon.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/ow/m1/owm1gm89wt9r367awhwxbjwvgj9r5bnrsgdau16da/Election-Polling-Box-icon.png' '/home/garrett/.config/Mailspring/files/mk/vz/mkvzlxpu6fwhogwyxyhfcfclss9uo7tahuazxedtl/Election-Polling-Box-icon.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/jp/oo/jpoodjruehmdt6hpngfekqxbdppymyd6pfczbdble/Election-Polling-Box-icon.png' '/home/garrett/.config/Mailspring/files/mk/vz/mkvzlxpu6fwhogwyxyhfcfclss9uo7tahuazxedtl/Election-Polling-Box-icon.png' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/6i/kx/6ikxq48yuaw6m6xmmxrrdrxno69s9ykdtdv9az5fi/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/bj/fp/bjfpymyccaynkfkujzbyoa3wchxrdj6kyyito38av/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/w4/5r/w45rpxgr5karf143sstzygmpkvfurcmu5ablwc81i/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/eb/r5/ebr5qg48srmhdrcijp5ao1ktmt2r7jer78dd4xzzh/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/as/gz/asgzlhhen8e2gpszaqrxe8obdhjvm33ez84g4geft/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/q5/lm/q5lmnncthbcygub1rdzeskhftubg8wxipd5bqt3uk/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/8q/np/8qnpphcjrryl2vy4zvdt3qp7tcnhzsyc6maaoohhu/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/3b/en/3benst8qxvbqnppb1gghmhxm1mjhxje3dywtudp6j/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/b7/t3/b7t3ljbtzsfm5vsqar2y1kcfd9vgmd1dfhjdqmqme/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/fe/ue/feue7fnwhde8helhxn7s7x6y5cavjsikgvskn1xw1/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/38/jd/38jdoudcvdesqdy3swbk8hdtmfdcgb49u7pkmuh2y/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/4e/16/4e16ws2uxlv3xo1fa8ke1bsmjvzpkf3qnpdjuofws/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/7a/v1/7av1tzle65qyumyuupy4g42g6vdkqcf6efacbzj2z/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/na/ts/nats3fhabgbsbmxg4ht9tts76a58gmuhuzpmbwqlz/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/ze/31/ze314jhey9yvvgmhhkxcan4tgpv3n3zcmwg5yw2af/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/e5/q6/e5q6wiyu9tnggsomzqiyxxy9xa36zmpet1kjscrqk/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/kt/yg/ktygynwkxugqbtkkse9uxjnserda8dfsp7dippck2/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/p1/pm/p1pmnjfnyqx5t51vcg1jmpjt2n2mn1vxd2dvqd4ky/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/zt/gs/ztgs6weg47ywlbga72uguddkar4rb36kuvfunnux5/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/be/7f/be7fgblc87keva19eb2dgzew15xawsmv592jp7psn/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/iy/pw/iypwjcqse9gwqun1ap89o4kix2fsxx27eaij55drp/locationMarker.png' '/home/garrett/.config/Mailspring/files/s2/kk/s2kkdpzfxexwf4ayluqjldth2zpgruztpu9vhsgat/locationMarker.png' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/hs/ds/hsdsgpnrfc4pg8zcbj8gsmzupbdudk2l71hybtm9e/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/4n/td/4ntd4apkc4pekhiewwcwchzwk84zs7b5s4qerjkbd/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/pv/3j/pv3jqzkclbq7tjufw4rnigvv5nglhzshgtxtapnnq/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/cu/yr/cuyrsml6gcpmhdqgpkzjqzrcpkoa6bmxbohekgrmq/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/av/sy/avsyktah5tu3fjgbxoafy2wjqfdu8muejpmsbvyz6/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/d1/tm/d1tm6vrajrsijyqvifia7994ov1drfdacqxcdbxgw/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/cd/sv/cdsvn6otfgqrwj9ar8e76suqi2tdphxwxxjnxxpmx/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/bf/7q/bf7qzjiyhbyhfpzdjk9jszg2sxv31aqousavdtvzs/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/nx/ww/nxwwtygkehwwrlgqf3khdjn6nmgza1xcygqbbynpx/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/rk/9d/rk9dhrhmmxlfckaxdk9yjp9jgpr5ndzmlwgbxdp8g/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/uw/kn/uwknqtrdr4efprynsmfzgelt4iuksyybcnqttuzck/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/pe/5l/pe5loh2au3ixk6pwx9k7jgddc4hx2sbyzxqqmfamj/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/pn/ke/pnke7fffv83wdc489tjvdjyt4rk27u64uxvotxkcw/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/fz/xt/fzxtqx8mqgn9jqrbd8fcs3txbpiismxpj2wwd1wf3/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/5j/io/5jioxre8zd8qs3wkptnrq3qlcahayaogqwwuiofkt/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/9k/hf/9khfrqvwft5y6izyarsokd5sejygggyxemnqsqwdf/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/jj/tt/jjtte3kuyztchqr8nefttkaihp3kkv1dmzxcuprw7/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/gs/mo/gsmoh2qlvwtw4vrqjqsapr5zxa4njarnhnuakjmxw/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/n7/ej/n7ejq25trb6wy3b7gcoz3spjbyp8duzh5bhmfs4ac/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/r6/zw/r6zwbthrm6vrvynatk5yrqcydcv9st3kjgz5s4asq/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/er/ih/erihjnkqfvevgtwofdobsg4yvuxhlpvvc1z3tyfvp/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/ew/xz/ewxzzzaz5af417y8szduwgato33sktgfp56hopmbp/outlookLogo.png' '/home/garrett/.config/Mailspring/files/ea/wa/eawa5myjdszgu5jrka1jutqxfqd7ny2dpkef7ubys/outlookLogo.png' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/dg/yw/dgywg7jyeymrgcbrzzjpptxqefgwfyzvnmyuafixb/image003.jpg' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/ni/xt/nixtacz1aoxhomydfqzu2sb84cm2jb2vsvbkqi6v/image003.jpg' '/home/garrett/.config/Mailspring/files/dg/yw/dgywg7jyeymrgcbrzzjpptxqefgwfyzvnmyuafixb/image003.jpg' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/rv/jn/rvjnmny14j8htt7gbyppabbfgjuqjddqlmauwdvee/image003.jpg' '/home/garrett/.config/Mailspring/files/dg/yw/dgywg7jyeymrgcbrzzjpptxqefgwfyzvnmyuafixb/image003.jpg' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/la/nd/landfryiknsx7kym2rir2mi1dbve7dzdmjg5z2awd/image003.jpg' '/home/garrett/.config/Mailspring/files/dg/yw/dgywg7jyeymrgcbrzzjpptxqefgwfyzvnmyuafixb/image003.jpg' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/rn/gb/rngbfqwaze3rxya6ycavp1x194xicmkepykhabinz/embed1' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/5o/wp/5owp87hgzdff7eglgj4sdojapffh875mj1ip7rvuq/embed1' '/home/garrett/.config/Mailspring/files/rn/gb/rngbfqwaze3rxya6ycavp1x194xicmkepykhabinz/embed1' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/92/pc/92pcjjvonn2bgp49uszidtkwm8krf7nqjt1pbycnb/embed1' '/home/garrett/.config/Mailspring/files/rn/gb/rngbfqwaze3rxya6ycavp1x194xicmkepykhabinz/embed1' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ru/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ru/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/ru/messages.json' # duplicate

original_cmd  '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074855/6-EditorConfig.log' # original
remove_cmd    '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074905/3-EditorConfig.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074855/6-EditorConfig.log' # duplicate
remove_cmd    '/home/garrett/.config/Code/logs/20210101T112137/exthost1/output_logging_20210101T112139/4-EditorConfig.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074855/6-EditorConfig.log' # duplicate
remove_cmd    '/home/garrett/.config/Code/logs/20210101T125238/exthost1/output_logging_20210101T125242/3-EditorConfig.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074855/6-EditorConfig.log' # duplicate
remove_cmd    '/home/garrett/.config/Code/logs/20210101T125513/exthost1/output_logging_20210101T125517/5-EditorConfig.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074855/6-EditorConfig.log' # duplicate
remove_cmd    '/home/garrett/.config/Code/logs/20210101T125726/exthost1/output_logging_20210101T125729/3-EditorConfig.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074855/6-EditorConfig.log' # duplicate
remove_cmd    '/home/garrett/.config/Code/logs/20210101T131833/exthost1/output_logging_20210101T131837/3-EditorConfig.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074855/6-EditorConfig.log' # duplicate
remove_cmd    '/home/garrett/.config/Code/logs/20210102T084228/exthost1/output_logging_20210102T084231/3-EditorConfig.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074855/6-EditorConfig.log' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/qm/s4/qms4uksvmzksvcnwzcmpb7kcq9xu8mcs4nfxnzje5/CRISTY D. DONATION 2020.docx' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/rk/tc/rktc9twz61ampafzhy3gmrcwlhnus63y5azjctwfx/CRISTY D. DONATION 2020.docx' '/home/garrett/.config/Mailspring/files/qm/s4/qms4uksvmzksvcnwzcmpb7kcq9xu8mcs4nfxnzje5/CRISTY D. DONATION 2020.docx' # duplicate

original_cmd  '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074905/2-Git.log' # original
remove_cmd    '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074917/2-Git.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074905/2-Git.log' # duplicate
remove_cmd    '/home/garrett/.config/Code/logs/20210101T112137/exthost1/output_logging_20210101T112139/2-Git.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074905/2-Git.log' # duplicate
remove_cmd    '/home/garrett/.config/Code/logs/20210101T112137/exthost1/output_logging_20210101T112142/2-Git.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074905/2-Git.log' # duplicate
remove_cmd    '/home/garrett/.config/Code/logs/20210101T115114/exthost1/output_logging_20210101T115118/2-Git.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074905/2-Git.log' # duplicate
remove_cmd    '/home/garrett/.config/Code/logs/20210101T115346/exthost1/output_logging_20210101T115349/2-Git.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074905/2-Git.log' # duplicate
remove_cmd    '/home/garrett/.config/Code/logs/20210101T122042/exthost1/output_logging_20210101T122045/2-Git.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074905/2-Git.log' # duplicate
remove_cmd    '/home/garrett/.config/Code/logs/20210101T125238/exthost1/output_logging_20210101T125242/2-Git.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074905/2-Git.log' # duplicate
remove_cmd    '/home/garrett/.config/Code/logs/20210101T125513/exthost1/output_logging_20210101T125517/2-Git.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074905/2-Git.log' # duplicate
remove_cmd    '/home/garrett/.config/Code/logs/20210101T125726/exthost1/output_logging_20210101T125729/2-Git.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074905/2-Git.log' # duplicate
remove_cmd    '/home/garrett/.config/Code/logs/20210101T131833/exthost1/output_logging_20210101T131837/2-Git.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074905/2-Git.log' # duplicate
remove_cmd    '/home/garrett/.config/Code/logs/20210102T084228/exthost1/output_logging_20210102T084231/2-Git.log' '/home/garrett/.config/Code/logs/20210101T074853/exthost1/output_logging_20210101T074905/2-Git.log' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BQ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/BQ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/BQ' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/wb/zc/wbzc9htqu3xoyexmsedznzmapafwsidfmryjnr4va/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/it/xo/itxo2u535na5zcv4h7wnpqrgx4cuxrwaz5kuhhk83/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/8u/yg/8uygmbske1niadetnuz3asxgbmealmkhennfqf1hw/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/ge/bv/gebvjcartq8hfrgd1btzwhqr9ffurrtopdmao6rjr/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/eu/yc/euyc3jdzj2p7xltpw65xzdwwfsglxtnk6ct5kuewy/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/q6/kz/q6kzvhe4dtcqhbahwgauya2gma1dnhxoijufdgpjh/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/4u/ru/4uruo4nzz1rfzelqqhfxif5r9cpqej5kpwlbuyhjp/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/26/eg/26eghlaa4owaxy7bjupsrrwapg9mmm8zbo1upcxpa/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/wv/su/wvsumb9hkkdwdgavc8hynwb8mvrkqfdjxqwr9muvv/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/6y/md/6ymdbk8nkk7d4vacxqlpd5mftjy7k4gcr5hbjpx51/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/ng/vb/ngvbnwaumomhseqdydogbr7fmmg4zqukrkky29jfm/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/5s/e3/5se3epzvb5kggdt5nc9ptprhr17shbjicszqr31z4/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/zx/rf/zxrfvgxhy93hcxbrquziarhvajhhnaxfchcfut91x/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/2i/ms/2imsvmtkx828or73ftm6b7hyqrs9vyplfsf9y4kjz/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/rt/a5/rta5urxzbue6ixvjugrmxu2rxcnzfmnh42sjpudjf/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/pk/h6/pkh63ik66jd9a2fzedyjv7c3ja13tptbxxwzudh99/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/jr/3m/jr3mxjnhqspmmwvj2rpuwbmuapx6shusqav2r6jqj/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/8h/gy/8hgykcf91munp2nza3rrm2mlbzpqou1vvskg43bk3/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/pj/ia/pjiaxg77n5cwy8tqkiog8gymijv3depy9biyz8prq/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/xv/ra/xvrahp4qvviajghxbc946sdgxpfgyjawmuuhrjny5/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/jp/q3/jpq3nacnz6xaxlopvvtvh8yynfrqlllers8hajnyh/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/oz/zc/ozzcqjynwnxwzgsbsu3nnuptfducr7jjbtiq4kmyf/defaultCalendar.png' '/home/garrett/.config/Mailspring/files/kq/d6/kqd6b3ctgsmtarepgbpsugjmjwhvfbdwebxgdwup9/defaultCalendar.png' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ro/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ro/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ro/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/fil/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/fil/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/fil/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/vi/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/vi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/vi/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/sv/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/sv/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/sv/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TM' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/TM' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TM' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/fr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/fr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/fr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/sl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/sl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/sl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PK' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/PK' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/PK' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/FM' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/FM' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/FM' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/he/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/he/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/he/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/pl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/pl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/pl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/he/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/he/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/he/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ca/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ca/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ca/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/pt_PT/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/pt_PT/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/pt_PT/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/sl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/sl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/sl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # original
remove_cmd    '/home/garrett/.config/Bitwarden/Local Storage/leveldb/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/VIA/Session Storage/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/discord/Session Storage/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Sync Data/LevelDB/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Site Characteristics Database/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Local Storage/leveldb/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Platform Notifications/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Platform Notifications/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extension State/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Session Storage/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/GCM Store/Encryption/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/BudgetDatabase/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Feature Engagement Tracker/AvailabilityDB/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Feature Engagement Tracker/EventDB/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/AutofillStrikeDatabase/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/shared_proto_db/metadata/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extension Rules/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Local Storage/leveldb/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Platform Notifications/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Local Extension Settings/ghbmnnjooekpmoecnnnilnnbdlolhkhi/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Sync Extension Settings/pkedcjkdefgpdelpbcmbmeomcjbeemfm/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Session Storage/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Session Storage/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Sync Data/LevelDB/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Site Characteristics Database/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Local Storage/leveldb/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Platform Notifications/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Platform Notifications/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extension State/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/GCM Store/Encryption/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/shared_proto_db/metadata/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extension Rules/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Local Storage/leveldb/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Platform Notifications/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Local Extension Settings/ghbmnnjooekpmoecnnnilnnbdlolhkhi/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Sync Extension Settings/pkedcjkdefgpdelpbcmbmeomcjbeemfm/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Session Storage/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Session Storage/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/Database/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/Origins/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/001/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/007/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/002/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/006/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/004/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/005/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/000/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/009/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/008/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/003/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/Code/Session Storage/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/012/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/011/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/010/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/013/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/015/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/014/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/GCM Store/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/016/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/016/p/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/018/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/017/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/019/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/020/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/024/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/022/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/021/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/023/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/025/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/File System/Origins/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/File System/000/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/027/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/026/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/028/t/Paths/MANIFEST-000001' '/home/garrett/.config/Code/Local Storage/leveldb/MANIFEST-000001' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/lu/w2/luw2l6ynyzy2pkxx2ua3md3ct6xwkjz7svlea26ry/image002.jpg' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/l4/pr/l4prr4ksmemcejfmt6yzoa1vupqxqfwyt92j9nqzr/image002.jpg' '/home/garrett/.config/Mailspring/files/lu/w2/luw2l6ynyzy2pkxx2ua3md3ct6xwkjz7svlea26ry/image002.jpg' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/m9/ny/m9nyqddul7wjh1rzs3fccpe6aybvzubpgdnwqdjff/image002.jpg' '/home/garrett/.config/Mailspring/files/lu/w2/luw2l6ynyzy2pkxx2ua3md3ct6xwkjz7svlea26ry/image002.jpg' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/co/nh/conhfpc9qnkbgwmwjr8dqsnel5a7yubgbcpwyykud/image002.jpg' '/home/garrett/.config/Mailspring/files/lu/w2/luw2l6ynyzy2pkxx2ua3md3ct6xwkjz7svlea26ry/image002.jpg' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/IT' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/IT' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/IT' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/rp/hc/rphchmnxqdj6ydbvvnafr4zmzhrtcbaphsb9b6fel/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/5d/ra/5dragz4tjks4n16gnxae13b19j4awmbsmwe2muidb/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/j7/v8/j7v8zhvwzjounsrbdsdstakpyfnjqfc6k9c5xssfp/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/tm/ay/tmayw7kjcwajrzkmggs1qkvatm6y3wbwvwrxga2kg/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/ns/a7/nsa7uveituyyme4mrhaypqqjt623we1fhrmhutn6/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/au/ft/auftm6geg1kmgfzi3j7fxt9hsqfjj3fnyadntl3rt/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/h7/z9/h7z9perviekr9wkc6ntjuegrexx8sszshfvebmkwq/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/un/y8/uny8mrmt34xbgg55lo9de5c3zmcvmuktdsu3sbbsy/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/7z/2c/7z2cf7wbmga3uhzdgmgwzfgsfx7m6x67s6ffxwgor/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/nz/gp/nzgpruep1gzsjgq7tg6yirmewdu4nsmvhuxgzm9lg/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/gf/qu/gfqudyxzt3f6f2p7acco1suyrcbhtvogywg11eau9/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/ex/1e/ex1e2fhtsslmv2cqgks94jwfysamj7xzkewcdzbay/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/aq/bj/aqbjbgdmflmp773yw3abuutkd1lzvkwrrqhsgeevh/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/ny/a9/nya99qwc8by2hkbdkfve42igpeurus7qi95l2s15s/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/n8/5p/n85poqvpbcfy3hmvnxj9sfgkdeuu8of9ybjtaoio/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/ga/nf/ganfqx46kemq63n2bg5djjcrwhpuydo3pedmzisw2/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/by/jx/byjxrbj9gowkukqenwjoqhwh9zdtfrs6uwtureaao/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/tf/ue/tfueppxmkhd2zz5js12pkfgztcqszsyprzcg3uf1t/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/fm/zp/fmzpxda3jzlasfbyac7vftjz1nkesqrhymdeiyz1t/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/ag/4m/ag4mmn9haceud6tsupqf1fhwzyntvgoq9x9tv8hf6/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/lb/y2/lby2gt22hfqxqcciurjkxnrwzyy7346mufqemtcbh/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/pd/z7/pdz7kh9jpphyqxxn55dz4fmikkwp8nfbjjumy9djq/29_packagedelivery.png' '/home/garrett/.config/Mailspring/files/sp/ym/spymwf9jyiukprqy9dashhby8jnpyq7jii2qtxdh7/29_packagedelivery.png' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/7u/lv/7ulvsvwsdtpruxpnxxatqbwsjccpqnig49hf8e6h2/image001.jpg' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/a4/nf/a4nf9cgfbhurqu4lz9a3wyhzdb1wgwjvwbtdf1jnb/image001.jpg' '/home/garrett/.config/Mailspring/files/7u/lv/7ulvsvwsdtpruxpnxxatqbwsjccpqnig49hf8e6h2/image001.jpg' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/9q/yg/9qygklc3rovxxwaydbsi9bcghe4pxoyhq4jhzom5v/image001.jpg' '/home/garrett/.config/Mailspring/files/7u/lv/7ulvsvwsdtpruxpnxxatqbwsjccpqnig49hf8e6h2/image001.jpg' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/5x/na/5xnaptsuaokysgbxmsxm5nwfsedetoon1zhmnxcmg/image001.jpg' '/home/garrett/.config/Mailspring/files/7u/lv/7ulvsvwsdtpruxpnxxatqbwsjccpqnig49hf8e6h2/image001.jpg' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/zh_TW/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/zh_TW/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/zh_TW/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/zh_CN/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/zh_CN/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/zh_CN/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/zh_TW/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/zh_TW/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/zh_TW/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/FJ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/FJ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/FJ' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ET' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/ET' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ET' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/DE' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/DE' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/DE' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TJ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/TJ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/TJ' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AS' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/AS' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/AS' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/en_US/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/en_US/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aohghmighlieiainnegkcijnfilokake/0.10_0/_locales/en_US/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/CertificateRevocation/6339/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/CertificateRevocation/6339/manifest.json' '/home/garrett/.config/google-chrome-unstable/CertificateRevocation/6339/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/dasherSettingSchema.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/dasherSettingSchema.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/dasherSettingSchema.json' # duplicate

original_cmd  '/home/garrett/.config/Code/Code Cache/js/index' # original
remove_cmd    '/home/garrett/.config/Code/Code Cache/wasm/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/Code/Cache/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/Bitwarden/Code Cache/js/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/Bitwarden/Cache/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/VIA/Code Cache/js/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/VIA/Cache/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/skypeforlinux/Code Cache/js/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/discord/Code Cache/js/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/discord/Code Cache/wasm/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/discord/Cache/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/skypeforlinux/Cache/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/ScriptCache/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/8f7abdeb3486c1b8780fede76afc20e044eff1b5/b5a87917-711a-4823-adc6-c3cf228134e0/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/8f7abdeb3486c1b8780fede76afc20e044eff1b5/eb0ad154-2084-458d-825a-6a8cd52c1187/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/4c44542698286d38038cee804a17941a3cfea5f4/e5b24cfa-8762-4bda-8c2c-6a68b16a5919/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/e5b7980a04e4805673a74179633ecd675ba6a857/7ad83f9f-5b5c-4fec-ac67-03e2567a6cdc/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/6bbd051d283f46f043a9b99be9e968a0232aacf8/2b3ebeb9-f6cc-4cf2-aa13-8dcc40d818a8/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/8484c1ccb00bd0d7ed10f4d6ff24e63243a5ab4b/dc582267-a9fa-4542-b191-f1109d7e1076/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/0b3e4fcfd87091ef4124a60acd2e012695f6a5f0/8f115c14-9842-4821-9908-130ac80712d6/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/0f48a22277f64c442756e922770a3faedfa75bed/322013f9-688c-4f24-a7e7-26b85bf6629c/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/0f48a22277f64c442756e922770a3faedfa75bed/cbdcb820-2079-43d7-9c20-990ceae44f9e/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/0f48a22277f64c442756e922770a3faedfa75bed/2569384a-5cec-4dc3-b382-a52ab6c11131/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/448124daccd0345a938712298d729cd894d33f8f/d4501234-c2b9-45fc-ba44-3cb91d0ce761/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/c6a432cec80d0c030c605093e26a7faf15c00d76/ea3fcf52-974c-415c-8eac-a176acbf3cfe/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/7bb51da0e718da756547606b6c9eceea92342192/75631038-44db-4f18-acdc-c7f0bef0b942/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/7bb51da0e718da756547606b6c9eceea92342192/5f6eaef7-5519-4e35-9ef6-809e4a4f85ac/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/9098b7040027bafeab7996f8413ab5eb35a7d6f3/a8a13fe5-3fc1-4fd9-b76e-db175058f1db/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/9098b7040027bafeab7996f8413ab5eb35a7d6f3/5118aff5-c920-4da7-9428-80a0f99ddaf9/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/1984c975124833f9a40a66d95f33ee439a48679f/f828b380-887c-43a0-a0fd-509d220715ed/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/1984c975124833f9a40a66d95f33ee439a48679f/99617fe3-792d-4fef-91a4-e69c72aab61d/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/579544fd7d0441717f082c9eb123588966aa57ac/8438be57-9145-4e2f-94d7-fe0343e09022/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/0f48a22277f64c442756e922770a3faedfa75bed/0a0fe77f-fe56-4618-8c3d-fb164a3e4ef2/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/5a05b1282ea8cba3e1ccaced30db83ce9ff511de/2aad50c2-4554-445f-9601-dc47ecef1728/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/dfe0b09683fc6b3361fb01fb6ee283bf7e557c25/1e9cedc5-f38d-42a0-a30e-8c56f75cf8a7/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/76ef9e5953a1ba4578548bb32235240a9f0e0ca2/b0441848-518c-426a-8735-1674babb57e9/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/c331b6ece6174d2c54ee87fee1e5b83ff880e3a1/f330fa44-fabe-4430-85a5-5ee9a4e0db0d/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/1c070948a48a69afa1f61bd6c29cef6c686d7b64/aebdfe75-5a77-4356-b61b-796bfc3f8101/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/0f48a22277f64c442756e922770a3faedfa75bed/80eff894-76a7-4150-885d-b19db2686b10/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/5dceb26707589a12745ce1cbbdbc2c7773a2f2fb/6cce0e1a-fc07-498d-be49-548ffa9fa8b8/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/CacheStorage/5dceb26707589a12745ce1cbbdbc2c7773a2f2fb/3b65d1dc-c406-46f1-9be1-ee1913961ee2/index' '/home/garrett/.config/Code/Code Cache/js/index' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ZW' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/ZW' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/ZW' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/ZxcvbnData/1/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/IQ' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/IQ' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/IQ' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.fool.com_0.indexeddb.leveldb/MANIFEST-000001' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.youtube-nocookie.com_0.indexeddb.leveldb/MANIFEST-000001' '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.fool.com_0.indexeddb.leveldb/MANIFEST-000001' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/he/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/he/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/he/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/th/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/th/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/th/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/no/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/no/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/no/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ja/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ja/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ja/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/TLSDeprecationConfig/3/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/TLSDeprecationConfig/3/manifest.json' '/home/garrett/.config/google-chrome-unstable/TLSDeprecationConfig/3/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/TrustTokenKeyCommitments/2021.1.2.3/keys.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/TrustTokenKeyCommitments/2021.1.3.2/keys.json' '/home/garrett/.config/google-chrome-unstable/TrustTokenKeyCommitments/2021.1.2.3/keys.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/ar/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/ar/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/ar/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/hr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/tr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/th/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/sv/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/ko/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/ja/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/sk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/it/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/ro/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/id/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pt_BR/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/zh_TW/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/zh_CN/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/vi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/uk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/lv/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/he/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/sr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/sl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/ru/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pt_PT/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/hu/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/nl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/hi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/lt/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/fr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/en/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/fi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/es/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/fil/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/cs/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/da/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/el/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/de/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/ca/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/bg/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pt_BR/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/da/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/fr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/lv/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/cs/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/sl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/sk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/ru/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/ro/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/nl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/ko/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/hi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/it/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pt_PT/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/hr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/hu/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/lt/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/ja/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/id/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/el/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/he/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/fil/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/fi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/es/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/en/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/de/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/ca/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/bg/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/zh_TW/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/vi/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/th/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/tr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/zh_CN/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/uk/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/sv/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/sr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/blpcfgokakmgnkcojhhkbfbldkacnbeo/4.2.8_0/_locales/pl/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ar/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ar/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/ar/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/SafetyTips/2533/manifest.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/SafetyTips/2533/manifest.json' '/home/garrett/.config/google-chrome-unstable/SafetyTips/2533/manifest.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-be.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-be.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-be.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-be.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-be.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-bg.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-bg.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-bg.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-bg.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-bg.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-da.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-da.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-da.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-da.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-da.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-fr.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-fr.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-fr.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-fr.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-fr.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-gu.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-gu.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-gu.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-gu.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-gu.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-eu.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-eu.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-eu.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-eu.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-eu.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-es.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-es.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-es.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-es.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-es.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-hr.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-hr.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-hr.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-hr.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-hr.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-hy.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-hy.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-hy.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-hy.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-hy.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-kn.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-kn.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-kn.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-kn.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-kn.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-ml.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-ml.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-ml.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-ml.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-ml.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/hu/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/hu/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/_locales/hu/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-hi.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-mr.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-hi.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-hi.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-hi.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-mr.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-hi.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-hi.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-hi.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-mr.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-hi.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-la.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-la.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-la.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-la.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-la.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LB' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/LB' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/LB' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-or.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-or.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-or.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-or.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-or.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-pt.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-pt.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-pt.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-pt.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-pt.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-mn-cyrl.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-mn-cyrl.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-mn-cyrl.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-mn-cyrl.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-mn-cyrl.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/SafetyTips/2533/manifest.fingerprint' # original
remove_cmd    '/home/garrett/.config/google-chrome/SafetyTips/2533/manifest.fingerprint' '/home/garrett/.config/google-chrome-unstable/SafetyTips/2533/manifest.fingerprint' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/OriginTrials/1.0.0.5/manifest.fingerprint' # original
remove_cmd    '/home/garrett/.config/google-chrome/OriginTrials/1.0.0.5/manifest.fingerprint' '/home/garrett/.config/google-chrome-unstable/OriginTrials/1.0.0.5/manifest.fingerprint' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/CertificateRevocation/6339/manifest.fingerprint' # original
remove_cmd    '/home/garrett/.config/google-chrome/CertificateRevocation/6339/manifest.fingerprint' '/home/garrett/.config/google-chrome-unstable/CertificateRevocation/6339/manifest.fingerprint' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/SSLErrorAssistant/7/manifest.fingerprint' # original
remove_cmd    '/home/garrett/.config/google-chrome/SSLErrorAssistant/7/manifest.fingerprint' '/home/garrett/.config/google-chrome-unstable/SSLErrorAssistant/7/manifest.fingerprint' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/manifest.fingerprint' # original
remove_cmd    '/home/garrett/.config/google-chrome/pnacl/0.57.44.2492/manifest.fingerprint' '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/manifest.fingerprint' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/manifest.fingerprint' # original
remove_cmd    '/home/garrett/.config/google-chrome/ZxcvbnData/1/manifest.fingerprint' '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/manifest.fingerprint' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/manifest.fingerprint' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/manifest.fingerprint' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/manifest.fingerprint' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Crowd Deny/2020.12.6.1201/manifest.fingerprint' # original
remove_cmd    '/home/garrett/.config/google-chrome/Crowd Deny/2020.12.6.1201/manifest.fingerprint' '/home/garrett/.config/google-chrome-unstable/Crowd Deny/2020.12.6.1201/manifest.fingerprint' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/FileTypePolicies/43/manifest.fingerprint' # original
remove_cmd    '/home/garrett/.config/google-chrome/FileTypePolicies/43/manifest.fingerprint' '/home/garrett/.config/google-chrome-unstable/FileTypePolicies/43/manifest.fingerprint' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Subresource Filter/Unindexed Rules/9.18.0/manifest.fingerprint' # original
remove_cmd    '/home/garrett/.config/google-chrome/Subresource Filter/Unindexed Rules/9.18.0/manifest.fingerprint' '/home/garrett/.config/google-chrome-unstable/Subresource Filter/Unindexed Rules/9.18.0/manifest.fingerprint' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/TLSDeprecationConfig/3/manifest.fingerprint' # original
remove_cmd    '/home/garrett/.config/google-chrome/TLSDeprecationConfig/3/manifest.fingerprint' '/home/garrett/.config/google-chrome-unstable/TLSDeprecationConfig/3/manifest.fingerprint' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_crtbegin_for_eh_o' # original
remove_cmd    '/home/garrett/.config/google-chrome/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_crtbegin_for_eh_o' '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_crtbegin_for_eh_o' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-tk.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-tk.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-tk.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-tk.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-tk.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-et.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-et.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-et.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-et.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-et.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/TrustTokenKeyCommitments/2021.1.1.3/LICENSE' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/CertificateRevocation/6337/LICENSE' '/home/garrett/.config/google-chrome-unstable/TrustTokenKeyCommitments/2021.1.1.3/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/TrustTokenKeyCommitments/2021.1.2.3/LICENSE' '/home/garrett/.config/google-chrome-unstable/TrustTokenKeyCommitments/2021.1.1.3/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/CertificateRevocation/6339/LICENSE' '/home/garrett/.config/google-chrome-unstable/TrustTokenKeyCommitments/2021.1.1.3/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/CertificateRevocation/6339/LICENSE' '/home/garrett/.config/google-chrome-unstable/TrustTokenKeyCommitments/2021.1.1.3/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/TrustTokenKeyCommitments/2021.1.3.2/LICENSE' '/home/garrett/.config/google-chrome-unstable/TrustTokenKeyCommitments/2021.1.1.3/LICENSE' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/CertificateRevocation/6340/LICENSE' '/home/garrett/.config/google-chrome-unstable/TrustTokenKeyCommitments/2021.1.1.3/LICENSE' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/7975620f39234f1983fa2afb870bfac99333b30a/translate.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/7975620f39234f1983fa2afb870bfac99333b30a/translate.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/7975620f39234f1983fa2afb870bfac99333b30a/translate.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-und-ethi.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-und-ethi.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-und-ethi.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-und-ethi.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-und-ethi.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/es_419/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/es_419/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/es_419/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/es/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/es/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/es/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/et/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/et/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/felcaaldnbdncclmgdcncolpebgiejap/1.2_0/_locales/et/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/sr/messages.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/sr/messages.json' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/aapocclcgogkmnckokdopfmhonfmgoek/0.10_0/_locales/sr/messages.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CW' # original
remove_cmd    '/home/garrett/.config/google-chrome/AutofillStates/2020.11.2.164946/CW' '/home/garrett/.config/google-chrome-unstable/AutofillStates/2020.11.2.164946/CW' # duplicate

original_cmd  '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # original
remove_cmd    '/home/garrett/.config/Bitwarden/Local Storage/leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/VIA/Session Storage/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/discord/Local Storage/leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/skypeforlinux/Local Storage/leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/discord/Session Storage/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Sync Data/LevelDB/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Site Characteristics Database/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Local Storage/leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Local Storage/leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Platform Notifications/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Platform Notifications/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extension State/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Session Storage/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/GCM Store/Encryption/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/BudgetDatabase/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Feature Engagement Tracker/AvailabilityDB/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Feature Engagement Tracker/EventDB/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/AutofillStrikeDatabase/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/shared_proto_db/metadata/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extension Rules/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Local Storage/leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Platform Notifications/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Local Extension Settings/ghbmnnjooekpmoecnnnilnnbdlolhkhi/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Sync Extension Settings/pkedcjkdefgpdelpbcmbmeomcjbeemfm/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Session Storage/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Session Storage/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Site Characteristics Database/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Local Storage/leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Sync Data/LevelDB/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Local Storage/leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Platform Notifications/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Platform Notifications/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extension State/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Session Storage/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/GCM Store/Encryption/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/shared_proto_db/metadata/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extension Rules/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Local Storage/leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Platform Notifications/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Local Extension Settings/ghbmnnjooekpmoecnnnilnnbdlolhkhi/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Sync Extension Settings/pkedcjkdefgpdelpbcmbmeomcjbeemfm/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/Session Storage/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/Session Storage/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/shared_proto_db/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Local Extension Settings/epcnnfbjfcgphgdmggkamkmgojdagdnn/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_twitter.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Service Worker/Database/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.twitch.tv_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/Origins/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/001/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.camwhoresbay.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_bongacams.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/007/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/002/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/006/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/004/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/005/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/000/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/009/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/008/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/003/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/Code/Session Storage/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/012/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/011/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/010/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.youtube.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.tomshardware.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/013/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/015/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/014/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/GCM Store/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_mega.nz_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/016/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/016/p/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_monkeytype.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_addons.mozilla.org_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.instagram.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/018/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/017/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.techradar.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/019/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_forum.archlabslinux.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/020/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_mail.google.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_pages.ebay.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_h.online-metrix.net_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.cardboardconnection.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_theporndude.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/024/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_lpcdn.lpsnmedia.net_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.americascardroom.eu_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.frandieguez.dev_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/022/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/021/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/023/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/025/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_realpython.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.spotify.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.amazon.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_mrrobot.fandom.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_pua.emp.state.or.us_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_stockx.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.snipesusa.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/Local Storage/leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/File System/Origins/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/File System/000/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/IndexedDB/https_googleads.g.doubleclick.net_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/026/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/027/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/skypeforlinux/IndexedDB/file__0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.thesaurus.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.fool.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.nba.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/File System/028/t/Paths/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.sportingnews.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.atlassian.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_github.community_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_collegereadiness.collegeboard.org_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_app2.ged.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_sciencing.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_photos.google.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.youtube-nocookie.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.lowes.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.microsoft.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.autodesk.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/IndexedDB/https_www.nfl.com_0.indexeddb.leveldb/CURRENT' '/home/garrett/.config/Code/Local Storage/leveldb/CURRENT' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-sl.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-sl.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-sl.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-sl.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-sl.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-pa.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-pa.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-pa.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-pa.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-pa.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-as.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-bn.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-as.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-as.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-as.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-bn.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-as.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-as.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-as.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-bn.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-as.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-te.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-te.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-te.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-te.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-te.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-ta.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-ta.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-ta.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-ta.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-ta.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Subresource Filter/Unindexed Rules/9.18.0/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/Subresource Filter/Unindexed Rules/9.18.0/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/Subresource Filter/Unindexed Rules/9.18.0/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/CertificateRevocation/6339/crl-set' # original
remove_cmd    '/home/garrett/.config/google-chrome/CertificateRevocation/6339/crl-set' '/home/garrett/.config/google-chrome-unstable/CertificateRevocation/6339/crl-set' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/CertificateRevocation/6339/_metadata/verified_contents.json' # original
remove_cmd    '/home/garrett/.config/google-chrome/CertificateRevocation/6339/_metadata/verified_contents.json' '/home/garrett/.config/google-chrome-unstable/CertificateRevocation/6339/_metadata/verified_contents.json' # duplicate

original_cmd  '/home/garrett/.config/Code/User/workspaceStorage/9e6407b5547c03e02c8addd12ee8dd4d/state.vscdb' # original
remove_cmd    '/home/garrett/.config/Code/User/workspaceStorage/9e6407b5547c03e02c8addd12ee8dd4d/state.vscdb.backup' '/home/garrett/.config/Code/User/workspaceStorage/9e6407b5547c03e02c8addd12ee8dd4d/state.vscdb' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/keyboard-layout/build/Release/keyboard-layout-manager.node' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/keyboard-layout/build/Release/obj.target/keyboard-layout-manager.node' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/keyboard-layout/build/Release/keyboard-layout-manager.node' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/5af91cf1f6188ad596b86f89d8affa1a060fadad/index.json' # original
remove_cmd    '/home/garrett/.config/Mailspring/compile-cache/less/38b3624e1bba74d4999800924979aebd434bee79/content/5af91cf1f6188ad596b86f89d8affa1a060fadad/index.json' '/home/garrett/.config/Mailspring/compile-cache/less/7cce51625ccc09b034ce627fc6106361259cb1da/content/5af91cf1f6188ad596b86f89d8affa1a060fadad/index.json' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/fj/ik/fjik9hnn1upywou5trevydsxa43vvyawa2sj3kdaz/temp4cj.png' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/ha/8s/ha8s3rhj59l5wnp3xyemqkz4kk38b8r6otmsx22ca/temp4cj.png' '/home/garrett/.config/Mailspring/files/fj/ik/fjik9hnn1upywou5trevydsxa43vvyawa2sj3kdaz/temp4cj.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/tn/tp/tntpa8iha24buuhkgmws96zyqay5kpaysb9xcfqz/temp4cj.png' '/home/garrett/.config/Mailspring/files/fj/ik/fjik9hnn1upywou5trevydsxa43vvyawa2sj3kdaz/temp4cj.png' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/mg/bd/mgbdtberfznyv26kuu4wr2l3au2q3khnlfc2dhu8q/temp4cj.png' '/home/garrett/.config/Mailspring/files/fj/ik/fjik9hnn1upywou5trevydsxa43vvyawa2sj3kdaz/temp4cj.png' # duplicate

original_cmd  '/home/garrett/.config/Code/User/workspaceStorage/aa4cb6e533aae0ba8d2b2c92a5aa587a/state.vscdb' # original
remove_cmd    '/home/garrett/.config/Code/User/workspaceStorage/aa4cb6e533aae0ba8d2b2c92a5aa587a/state.vscdb.backup' '/home/garrett/.config/Code/User/workspaceStorage/aa4cb6e533aae0ba8d2b2c92a5aa587a/state.vscdb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Login Data' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Login Data For Account' '/home/garrett/.config/google-chrome-unstable/Default/Login Data' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Sessions/Tabs_13254009513814663' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Sessions/Tabs_13254079348389579' '/home/garrett/.config/google-chrome-unstable/Default/Sessions/Tabs_13254009513814663' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/eventpage_bin_prod.js' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/eventpage_bin_prod.js' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/ghbmnnjooekpmoecnnnilnnbdlolhkhi/1.21.0_0/eventpage_bin_prod.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/surnames.txt' # original
remove_cmd    '/home/garrett/.config/google-chrome/ZxcvbnData/1/surnames.txt' '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/surnames.txt' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/flapper.gif' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/flapper.gif' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/images/flapper.gif' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_libcrt_platform_a' # original
remove_cmd    '/home/garrett/.config/google-chrome/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_libcrt_platform_a' '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_libcrt_platform_a' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_libgcc_a' # original
remove_cmd    '/home/garrett/.config/google-chrome/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_libgcc_a' '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_libgcc_a' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/zlink/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/zlink/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/zlink/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/zlink/spicetifyWrapper.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/zlink/spicetifyWrapper.js' '/home/garrett/.config/spicetify/Extracted/Raw/zlink/spicetifyWrapper.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-en-gb.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-en-gb.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-en-gb.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-en-gb.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-en-gb.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-ga.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-ga.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-ga.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-ga.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-ga.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-en-us.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-en-us.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-en-us.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-en-us.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-en-us.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-cy.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-cy.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-cy.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-cy.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-cy.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-de-ch-1901.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-de-ch-1901.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-de-ch-1901.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-de-ch-1901.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-de-ch-1901.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-de-1901.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-de-1901.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-de-1901.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-de-1901.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-de-1901.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-de-1996.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-de-1996.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-de-1996.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-de-1996.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-de-1996.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-cu.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-cu.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-cu.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-cu.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-cu.hyb' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/spellchecker/build/Release/obj.target/spellchecker.node' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/spellchecker/build/Release/spellchecker.node' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/spellchecker/build/Release/obj.target/spellchecker.node' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Subresource Filter/Unindexed Rules/9.18.0/Filtering Rules' # original
remove_cmd    '/home/garrett/.config/google-chrome/Subresource Filter/Unindexed Rules/9.18.0/Filtering Rules' '/home/garrett/.config/google-chrome-unstable/Subresource Filter/Unindexed Rules/9.18.0/Filtering Rules' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Subresource Filter/Indexed Rules/27/9.18.0/Ruleset Data' # original
remove_cmd    '/home/garrett/.config/google-chrome/Subresource Filter/Indexed Rules/27/9.18.0/Ruleset Data' '/home/garrett/.config/google-chrome-unstable/Subresource Filter/Indexed Rules/27/9.18.0/Ruleset Data' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/english_wikipedia.txt' # original
remove_cmd    '/home/garrett/.config/google-chrome/ZxcvbnData/1/english_wikipedia.txt' '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/english_wikipedia.txt' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/us_tv_and_film.txt' # original
remove_cmd    '/home/garrett/.config/google-chrome/ZxcvbnData/1/us_tv_and_film.txt' '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/us_tv_and_film.txt' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/passwords.txt' # original
remove_cmd    '/home/garrett/.config/google-chrome/ZxcvbnData/1/passwords.txt' '/home/garrett/.config/google-chrome-unstable/ZxcvbnData/1/passwords.txt' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/TLSDeprecationConfig/3/tls_deprecation_config.pb' # original
remove_cmd    '/home/garrett/.config/google-chrome/TLSDeprecationConfig/3/tls_deprecation_config.pb' '/home/garrett/.config/google-chrome-unstable/TLSDeprecationConfig/3/tls_deprecation_config.pb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/GPUCache/data_1' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/GPUCache/data_1' '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/GPUCache/data_1' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/GPUCache/data_1' '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/GPUCache/data_1' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Default/Storage/ext/nmmhkkegccagdldgiimedpiccmgmieda/def/GPUCache/data_1' '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/GPUCache/data_1' # duplicate
remove_cmd    '/home/garrett/.config/VIA/GPUCache/data_1' '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/GPUCache/data_1' # duplicate
remove_cmd    '/home/garrett/.config/Bitwarden/GPUCache/data_1' '/home/garrett/.config/google-chrome-unstable/Default/Storage/ext/gfdkimpbcpahaombhbimeihdjnejgicl/def/GPUCache/data_1' # duplicate

original_cmd  '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/material_css_min.css' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8920.1214.0.0_0/material_css_min.css' '/home/garrett/.config/google-chrome/Default/Extensions/pkedcjkdefgpdelpbcmbmeomcjbeemfm/8720.1005.0.2_0/material_css_min.css' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/ds/gk/dsgkbp6ja6prxapcerrnal96yk1zetapprfjynww1/fcra_summary_of_rights.pdf' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/dk/bj/dkbjiuvfzyutr1x8nvyf4tsa24ffmfwn4v17y5eub/fcra_summary_of_rights.pdf' '/home/garrett/.config/Mailspring/files/ds/gk/dsgkbp6ja6prxapcerrnal96yk1zetapprfjynww1/fcra_summary_of_rights.pdf' # duplicate

original_cmd  '/home/garrett/.config/discord/Dictionaries/en-US-9-0.bdic' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/Dictionaries/en-US-9-0.bdic' '/home/garrett/.config/discord/Dictionaries/en-US-9-0.bdic' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome/Dictionaries/en-US-9-0.bdic' '/home/garrett/.config/discord/Dictionaries/en-US-9-0.bdic' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/craw_window.js' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/craw_window.js' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/craw_window.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/craw_background.js' # original
remove_cmd    '/home/garrett/.config/google-chrome/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/craw_background.js' '/home/garrett/.config/google-chrome-unstable/Default/Extensions/nmmhkkegccagdldgiimedpiccmgmieda/1.0.0.5_0/craw_background.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/licenses/licenses.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/licenses/licenses.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/licenses/licenses.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/login/login.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/login/login.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/login/login.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/qh/hf/qhhfq5xndcyyhqmakq9wxzjzgu1jhcej3tyebmrjf/YOUR SOCIAL SECURITY CARD.pdf' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/lt/yy/ltyyhkjcgv7t2lagb67wjq8g1zv2ixaervqnpf3ez/YOUR SOCIAL SECURITY CARD.pdf' '/home/garrett/.config/Mailspring/files/qh/hf/qhhfq5xndcyyhqmakq9wxzjzgu1jhcej3tyebmrjf/YOUR SOCIAL SECURITY CARD.pdf' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/t4/tf/t4tfaifqgzgmbzwktd2f1usgssr5q3vtjsjhoe1pf/Brittany-SOCIAL SECURITY CARD.pdf' '/home/garrett/.config/Mailspring/files/qh/hf/qhhfq5xndcyyhqmakq9wxzjzgu1jhcej3tyebmrjf/YOUR SOCIAL SECURITY CARD.pdf' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/wy/qb/wyqbqmnyfgzgda7gzifyyueszzsbr19xyfy36ofzf/ORIGINAL MOVE-IN DATE.pdf' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/cr/xa/crxa2dqe4vxcp7uzdw2tm82uuxbua8nusmz9fqkda/ORIGINAL MOVE-IN DATE.pdf' '/home/garrett/.config/Mailspring/files/wy/qb/wyqbqmnyfgzgda7gzifyyueszzsbr19xyfy36ofzf/ORIGINAL MOVE-IN DATE.pdf' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/cy/x5/cyx5euxf2k7zhsln1e63od8htca7kq6eday7v82fe/Statement.pdf' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/qi/5h/qi5hezul7hfjwrw27acejufkatdecyeyk5g5skpei/Statement.pdf' '/home/garrett/.config/Mailspring/files/cy/x5/cyx5euxf2k7zhsln1e63od8htca7kq6eday7v82fe/Statement.pdf' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/aw/uv/awuvkmexbvvx18wso5t8l5jcab9lvzkdktbwt56nx/Statement.pdf' '/home/garrett/.config/Mailspring/files/cy/x5/cyx5euxf2k7zhsln1e63od8htca7kq6eday7v82fe/Statement.pdf' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-nb.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-nb.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-nb.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-nb.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-nb.hyb' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-nn.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-nn.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-nn.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-nn.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-nn.hyb' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/gn/g5/gng5b6epo5a3slvjijb8ucxdudvtdbvoghx86gcr3/The ARCHES Project.pdf' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/ad/kn/adknortyyveevm2ga9c1mgd4kwyt9jmsf4kgcbbcr/The ARCHES Project.pdf' '/home/garrett/.config/Mailspring/files/gn/g5/gng5b6epo5a3slvjijb8ucxdudvtdbvoghx86gcr3/The ARCHES Project.pdf' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/bz/fp/bzfpyfppibyubgxnsm1h8tbjd17wlmuxjjfiqcw2s/The ARCHES Project.pdf' '/home/garrett/.config/Mailspring/files/gn/g5/gng5b6epo5a3slvjijb8ucxdudvtdbvoghx86gcr3/The ARCHES Project.pdf' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/about/about.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/about/about.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/about/about.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_ld_nexe' # original
remove_cmd    '/home/garrett/.config/google-chrome/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_ld_nexe' '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_ld_nexe' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_pnacl_sz_nexe' # original
remove_cmd    '/home/garrett/.config/google-chrome/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_pnacl_sz_nexe' '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_pnacl_sz_nexe' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/buddy-list/buddy-list.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/buddy-list/buddy-list.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/buddy-list/buddy-list.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/artist/artist.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/artist/artist.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/artist/artist.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/browse/browse.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/browse/browse.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/browse/browse.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/error/error.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/error/error.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/error/error.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/collection-album/collection-album.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/collection-album/collection-album.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/collection-album/collection-album.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/collection-artist/collection-artist.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/collection-artist/collection-artist.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/collection-artist/collection-artist.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/full-screen-modal/full-screen-modal.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/full-screen-modal/full-screen-modal.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/full-screen-modal/full-screen-modal.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/findfriends/findfriends.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/findfriends/findfriends.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/findfriends/findfriends.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/concert/concert.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/concert/concert.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/concert/concert.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/lyrics/lyrics.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/lyrics/lyrics.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/lyrics/lyrics.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/chart/chart.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/chart/chart.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/chart/chart.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/cld/build/Release/cld.node' # original
remove_cmd    '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/cld/build/Release/obj.target/cld.node' '/home/garrett/.config/discord/0.0.13/modules/discord_spellcheck/node_modules/cld/build/Release/cld.node' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/collection/collection.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/collection/collection.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/collection/collection.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/hub/hub.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/hub/hub.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/hub/hub.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/n6/1g/n61gqwafvgzchujfbf7g1ip4dwbmkin3yqgqoszzx/CERTIFICATION OF ZERO INCOME.pdf' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/gr/1f/gr1famqacvkvytviueob6ufwgzh43tkdogjkhxc8k/CERTIFICATION OF ZERO INCOME.pdf' '/home/garrett/.config/Mailspring/files/n6/1g/n61gqwafvgzchujfbf7g1ip4dwbmkin3yqgqoszzx/CERTIFICATION OF ZERO INCOME.pdf' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/nc/m6/ncm6u9d3cmvfb4d24rpj1wq5dmhnzpanwubxy3cvg/CERTIFICATION OF ZERO INCOME.pdf' '/home/garrett/.config/Mailspring/files/n6/1g/n61gqwafvgzchujfbf7g1ip4dwbmkin3yqgqoszzx/CERTIFICATION OF ZERO INCOME.pdf' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/b2/th/b2thukm2rviagqjcopm6j2mxhmssqcswzsacrx6xn/OREGON.pdf' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/6y/mk/6ymk3m7pnupnm7nutrmhllin2ub9byjzh7y2fue26/OREGON.pdf' '/home/garrett/.config/Mailspring/files/b2/th/b2thukm2rviagqjcopm6j2mxhmssqcswzsacrx6xn/OREGON.pdf' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/jk/au/jkaumgabtsilwnezsgfsdmi5ub4vr67ama8uwgfhw/OREGON.pdf' '/home/garrett/.config/Mailspring/files/b2/th/b2thukm2rviagqjcopm6j2mxhmssqcswzsacrx6xn/OREGON.pdf' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/va/zk/vazkwpeymgu6dscnmunnkjtap6c4esqmevbsgh5ft/OREGON.pdf' '/home/garrett/.config/Mailspring/files/b2/th/b2thukm2rviagqjcopm6j2mxhmssqcswzsacrx6xn/OREGON.pdf' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/zu/dt/zudtteerkkxzfudyrc6fg4kbnhknuvzsnyfgakpvb/Kelle-ID.pdf' '/home/garrett/.config/Mailspring/files/b2/th/b2thukm2rviagqjcopm6j2mxhmssqcswzsacrx6xn/OREGON.pdf' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/playlist-folder/playlist-folder.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/playlist-folder/playlist-folder.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/playlist-folder/playlist-folder.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/fh/fo/fhfopipobsbhswczghkbstbyqp4peqrkho1uehgc6/Mid-Willamette Valley Community Action Agency.pdf' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/ww/pg/wwpgggqj7ugutxgclqjhkmgulu4dlcvhquvfhsglq/Mid-Willamette Valley Community Action Agency.pdf' '/home/garrett/.config/Mailspring/files/fh/fo/fhfopipobsbhswczghkbstbyqp4peqrkho1uehgc6/Mid-Willamette Valley Community Action Agency.pdf' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/a6/sx/a6sxcpckhs1z8rxim7kcszwhcjiwcj9jqv7u1egln/Mid-Willamette Valley Community Action Agency.pdf' '/home/garrett/.config/Mailspring/files/fh/fo/fhfopipobsbhswczghkbstbyqp4peqrkho1uehgc6/Mid-Willamette Valley Community Action Agency.pdf' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/5u/eo/5ueobrehborzymb68gxbqbjbgm35uyuzigcsmcczr/YOUR SOCIAL SECURITY CARD.pdf' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/sb/t4/sbt4pxhgclmgkhhgrauqhexuv6tggu6anv4hrzn2a/YOUR SOCIAL SECURITY CARD.pdf' '/home/garrett/.config/Mailspring/files/5u/eo/5ueobrehborzymb68gxbqbjbgm35uyuzigcsmcczr/YOUR SOCIAL SECURITY CARD.pdf' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/st/y3/sty3waaxowwhhsyywmw9aq7ucwcjrhhbhyggjqvzs/Kelle-SOCIAL SECURITY CARD.pdf' '/home/garrett/.config/Mailspring/files/5u/eo/5ueobrehborzymb68gxbqbjbgm35uyuzigcsmcczr/YOUR SOCIAL SECURITY CARD.pdf' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/af/pp/afppchzvbeh4nieavyykltaff7ffcr59k8yychazk/CERTIFICATION OF VITAL RECORD.pdf' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/ds/t7/dst7l3eezs5mxadjemawxw98dtur87usu254etczj/CERTIFICATION OF VITAL RECORD.pdf' '/home/garrett/.config/Mailspring/files/af/pp/afppchzvbeh4nieavyykltaff7ffcr59k8yychazk/CERTIFICATION OF VITAL RECORD.pdf' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/ro/nj/ronjoygbmudtyhvqlvjkjwf1if2d31tmouutbvund/brittany.pdf' '/home/garrett/.config/Mailspring/files/af/pp/afppchzvbeh4nieavyykltaff7ffcr59k8yychazk/CERTIFICATION OF VITAL RECORD.pdf' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/queue/queue.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/queue/queue.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/queue/queue.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/settings/settings.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/settings/settings.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/settings/settings.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/playlist/playlist.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/playlist/playlist.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/playlist/playlist.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/collection-songs/collection-songs.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/collection-songs/collection-songs.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/collection-songs/collection-songs.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/profile/profile.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/profile/profile.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/profile/profile.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/show/show.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/show/show.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/show/show.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/5u/lu/5ulutvqxgb4zwpbkqqey6k1jynnd7gbbhkt2qhwoj/Your New Benefit Amount.pdf' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/hy/kd/hykdayrbvcjzagavhscsxgsdgqckdme3z5f7hv55v/income.pdf' '/home/garrett/.config/Mailspring/files/5u/lu/5ulutvqxgb4zwpbkqqey6k1jynnd7gbbhkt2qhwoj/Your New Benefit Amount.pdf' # duplicate
remove_cmd    '/home/garrett/.config/Mailspring/files/gt/u8/gtu8vn3s435ef1zymxs19tth3jqxaqxbcnmzcrzpd/Your New Benefit Amount.pdf' '/home/garrett/.config/Mailspring/files/5u/lu/5ulutvqxgb4zwpbkqqey6k1jynnd7gbbhkt2qhwoj/Your New Benefit Amount.pdf' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/genre/genre.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/genre/genre.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/genre/genre.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/Mailspring/files/rt/vq/rtvqkcxbfjuxbrxqdenxjf9nmrigzo4mqtp6yykbk/CERTIFICATION OF VITAL RECORD.pdf' # original
remove_cmd    '/home/garrett/.config/Mailspring/files/ku/k8/kuk8rxtbhsyhtjuzevx1kmvtq4lmp3wh1npufdexb/CERTIFICATION OF VITAL RECORD.pdf' '/home/garrett/.config/Mailspring/files/rt/vq/rtvqkcxbfjuxbrxqdenxjf9nmrigzo4mqtp6yykbk/CERTIFICATION OF VITAL RECORD.pdf' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/legacy-lyrics/legacy-lyrics.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/legacy-lyrics/legacy-lyrics.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/legacy-lyrics/legacy-lyrics.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-hu.hyb' # original
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4376.0/hyph-hu.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-hu.hyb' # duplicate
remove_cmd    '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4377.0/hyph-hu.hyb' '/home/garrett/.config/google-chrome-unstable/hyphen-data/89.0.4375.0/hyph-hu.hyb' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/stations/stations.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/stations/stations.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/stations/stations.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/licenses/index.html' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/licenses/index.html' '/home/garrett/.config/spicetify/Extracted/Raw/licenses/index.html' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/station/station.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/station/station.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/station/station.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/search/search.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/search/search.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/search/search.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/concerts/concerts.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/concerts/concerts.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/concerts/concerts.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/spicetify/Extracted/Raw/zlink/zlink.bundle.js' # original
remove_cmd    '/home/garrett/.config/spicetify/Extracted/Themed/zlink/zlink.bundle.js' '/home/garrett/.config/spicetify/Extracted/Raw/zlink/zlink.bundle.js' # duplicate

original_cmd  '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_pnacl_llc_nexe' # original
remove_cmd    '/home/garrett/.config/google-chrome/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_pnacl_llc_nexe' '/home/garrett/.config/google-chrome-unstable/pnacl/0.57.44.2492/_platform_specific/x86_64/pnacl_public_x86_64_pnacl_llc_nexe' # duplicate
                                               
                                               
                                               
######### END OF AUTOGENERATED OUTPUT #########
                                               
if [ $PROGRESS_CURR -le $PROGRESS_TOTAL ]; then
    print_progress_prefix                      
    echo "${COL_BLUE}Done!${COL_RESET}"      
fi                                             
                                               
if [ -z $DO_REMOVE ] && [ -z $DO_DRY_RUN ]     
then                                           
  echo "Deleting script " "$0"             
  rm -f '/home/garrett/rmlint.sh';                                     
fi                                             
