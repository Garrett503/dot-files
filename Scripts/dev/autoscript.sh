#!/bin/bash

SCRIPT_FOLDER="$HOME/Scripts"
SCRIPT_FILE="$SCRIPT_FOLDER/$1"

if [[ -f $SCRIPT_FILE ]]; then
  nano $SCRIPT_FILE
else
  echo '#!/bin/bash' > $SCRIPT_FILE
  chmod +x $SCRIPT_FILE
  nano $SCRIPT_FILE
fi
