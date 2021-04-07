# spotify-song-grabber
Get your currently playing song and add to a playlist of your choice with keyboard shortcut. Feel free to modify or use however you please.

DISCLAIMER: the jpg file provided is NOT the official spotipy logo

This is by no means flawless but I thought I'd just put it out there if anyone actually wants it :^)

Dependencies:

--pip install SwSpotify

--pip install spotipy

In order for this to work FOLLOW THE STEPS BELOW:

--For basic functionality
1. Obtain a Spotify developer account by visiting this website: https://developer.spotify.com/
2. Create a new app and under settings set redirect_uri to "http://localhost:8888/callback"
3. Copy and paste the client id and secret from the developer website into the config file
4. Modify the scope accordingly
5. Find the playlist you want to use, go to the options menu of the playlist and under "Share" click "Copy Spotify URI"
6. Paste this text into PLAYLIST_ID in config, BUT don't forget to take out the "spotify:playlist:" part

--For keyboard shortcut
1. Create new desktop shortcut
2. Under properties set "target" to path_to_folder/src/main.py
3. Set shortcut key to whatever you'd like
4. Set it to run minimized
5. (Optional): Set icon to "spotipy icon.ico"
6. (Optional): Set playlist icon to "spotipy icon.jpg"

---NOTE: The program will require browser authentication the first/couple times it's run. This is not a permanent effect though.
