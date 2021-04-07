from SwSpotify import spotify
import spotipy
import spotipy.util as util
from config import CLIENT_ID, CLIENT_SECRET, USERNAME, SCOPE, REDIRECT_URI










#Get token

token = util.prompt_for_user_token(
    username=USERNAME,
    scope=SCOPE,
    client_id=CLIENT_ID,
    client_secret=CLIENT_SECRET,
    redirect_uri=REDIRECT_URI
)

sp = spotipy.Spotify(auth=token)





current_song = sp.currently_playing()["item"]
        #print(current_song)



play_pause = (u'  ,  ') # first character is play, second is paused

play_pause = play_pause.split(',')

if sp.current_user_saved_tracks_contains([current_song["id"]])[0]:
    play_pause = play_pause[0]
    print(play_pause)
else:
    play_pause = play_pause[1]
    print(play_pause)
       


    

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
