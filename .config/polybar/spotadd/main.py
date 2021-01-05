from SwSpotify import spotify
import spotipy
import spotipy.util as util
from config import CLIENT_ID, CLIENT_SECRET, USERNAME, SCOPE, REDIRECT_URI, PLAYLIST_ID

#Get token
print("Retrieving user token...")
token = util.prompt_for_user_token(
    username=USERNAME,
    scope=SCOPE,
    client_id=CLIENT_ID,
    client_secret=CLIENT_SECRET,
    redirect_uri=REDIRECT_URI
)

#Instantiate object
#print("Creating spotipy obj...")
sp = spotipy.Spotify(auth=token)

#Get song name and artist name
#print("Getting song info...")
try:
    song = spotify.song()
    artist = spotify.artist()
except:
    #print("--No song found")
    quit()

#Define query
#print("Defining search query...")
q = song + " artist:" + artist

#Get song id
#print("Retrieving query[0] id...")
try:
    song_id = str(sp.search(q, limit=1, type="track")["tracks"]["items"][0]["id"])
   # print(song_id)
except:
    #print("--Retrieval failed.")
    exit()

#Check if playlist contains song
# print("Checking for duplicates...")
# playlist_items = sp.playlist_items(PLAYLIST_ID)
# for item in playlist_items["items"]:
#     if song_id == item["track"]["id"]:
#         print("--Duplicate found.")
#         exit()
#         #Check if playlist contains song
# print("Checking for duplicates...")
# results = sp.current_user_saved_tracks()
# for item in results['items']:
#     track = item['track']
#     print(track)
#     exit()

current_song = sp.currently_playing()["item"]
#print(current_song)

if sp.current_user_saved_tracks_contains([current_song["id"]])[0]:
    print("already added...")
else:
    print("Adding song to playlist...")
    sp.current_user_saved_tracks_add([song_id])
    print("--Done!")
exit()

    # current_song = sp.currently_playing()["item"]
    # print(current_song)
    # if current_song == sp.current_user_saved_tracks_contains([current_song["id"]])[0]:
    #    print("yes")
    # else:
    #     print("no")
    #     exit()
#https://spotipy.readthedocs.io/en/2.12.0/#more-examples
#https://developer.spotify.com/documentation/general/guides/scopes/#scopes

# #Add to playlist
# print("Adding song to playlist...")
# sp.current_user_saved_tracks_add([song_id])
# print("--Done!")
