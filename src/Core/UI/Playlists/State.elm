module UI.Playlists.State exposing (..)

import Conditional exposing (ifThenElse)
import Coordinates
import Html.Events.Extra.Mouse as Mouse
import List.Ext as List
import List.Extra as List
import Maybe.Extra as Maybe
import Notifications
import Playlists exposing (..)
import Return exposing (andThen)
import Tracks exposing (IdentifiedTrack)
import Tracks.Collection
import UI.Alfred.State as Alfred
import UI.Common.State as Common
import UI.Page as Page
import UI.Playlists.Alfred
import UI.Playlists.ContextMenu as Playlists
import UI.Playlists.Page exposing (..)
import UI.Tracks.State as Tracks
import UI.Types exposing (..)
import UI.User.State.Export as User



-- 🔱


activate : Playlist -> Manager
activate playlist model =
    model
        |> select playlist
        |> andThen (Common.changeUrlUsingPage Page.Index)


addTracksToPlaylist : { collection : Bool, playlistName : String, tracks : List PlaylistTrackWithoutMetadata } -> Manager
addTracksToPlaylist { collection, playlistName, tracks } model =
    let
        properPlaylistName =
            String.trim playlistName

        playlistIndex =
            List.findIndex
                (\p -> Maybe.isNothing p.autoGenerated && p.name == properPlaylistName)
                model.playlists

        ( tracksAlreadyInPlaylist, newTracks ) =
            playlistIndex
                |> Maybe.andThen
                    (\a ->
                        if collection then
                            Just a

                        else
                            Nothing
                    )
                |> Maybe.andThen (\idx -> List.getAt idx model.playlists)
                |> Maybe.map
                    (\p ->
                        List.foldl
                            (\track ( a, b, c ) ->
                                case
                                    List.findIndex
                                        (\x ->
                                            track.title == x.title && track.album == x.album && track.artist == x.artist
                                        )
                                        c
                                of
                                    Just idx ->
                                        ( track :: a, b, List.removeAt idx c )

                                    Nothing ->
                                        ( a, track :: b, c )
                            )
                            ( [], [], p.tracks )
                            tracks
                    )
                |> Maybe.map (\( a, b, _ ) -> ( a, b ))
                |> Maybe.withDefault ( [], tracks )
                |> Tuple.mapSecond
                    (List.map
                        (\track ->
                            let
                                newTrack : PlaylistTrack
                                newTrack =
                                    { album = track.album
                                    , artist = track.artist
                                    , title = track.title

                                    --
                                    , insertedAt = model.currentTime
                                    }
                            in
                            newTrack
                        )
                    )

        newInventory =
            case playlistIndex of
                Just idx ->
                    List.updateAt
                        idx
                        (\p -> { p | tracks = p.tracks ++ newTracks })
                        model.playlists

                Nothing ->
                    { autoGenerated = Nothing
                    , collection = collection
                    , name = properPlaylistName
                    , public = False
                    , tracks = newTracks
                    }
                        :: model.playlists

        newModel =
            { model
                | playlists = newInventory
                , lastModifiedPlaylist =
                    Just
                        { collection = collection
                        , name = properPlaylistName
                        }
            }

        subject =
            ifThenElse collection "collection" "playlist"
    in
    case newTracks of
        [] ->
            if collection then
                (case tracksAlreadyInPlaylist of
                    [ t ] ->
                        "__" ++ t.title ++ "__ was"

                    l ->
                        "__" ++ String.fromInt (List.length l) ++ " tracks__ were"
                )
                    |> (\s -> s ++ " already added to the __" ++ properPlaylistName ++ "__ collection")
                    |> Notifications.casual
                    |> Common.showNotificationWithModel model

            else
                Return.singleton model

        _ ->
            (case newTracks of
                [ t ] ->
                    "Added __" ++ t.title ++ "__"

                l ->
                    "Added __" ++ String.fromInt (List.length l) ++ " tracks__"
            )
                |> (\s -> s ++ " to the __" ++ properPlaylistName ++ "__ " ++ subject)
                |> Notifications.success
                |> Common.showNotificationWithModel newModel
                |> andThen User.savePlaylists


assistWithAddingTracksToCollection : List IdentifiedTrack -> Manager
assistWithAddingTracksToCollection tracks model =
    model.playlists
        |> List.filter (\p -> p.autoGenerated == Nothing && p.collection == True)
        |> UI.Playlists.Alfred.create { collectionMode = True } tracks
        |> (\a -> Alfred.assign a model)


assistWithAddingTracksToPlaylist : List IdentifiedTrack -> Manager
assistWithAddingTracksToPlaylist tracks model =
    model.playlists
        |> List.filter (\p -> p.autoGenerated == Nothing && p.collection == False)
        |> UI.Playlists.Alfred.create { collectionMode = False } tracks
        |> (\a -> Alfred.assign a model)


assistWithSelectingPlaylist : Manager
assistWithSelectingPlaylist model =
    model.playlists
        |> UI.Playlists.Alfred.select
        |> (\a -> Alfred.assign a model)


convertCollectionToPlaylist : { name : String } -> Manager
convertCollectionToPlaylist { name } model =
    case
        List.findIndex
            (\p -> Maybe.isNothing p.autoGenerated && p.name == name)
            model.playlists
    of
        Just playlistIndex ->
            model.playlists
                |> List.updateAt
                    playlistIndex
                    (\p -> { p | collection = False })
                |> (\newInventory ->
                        { model
                            | playlists = newInventory
                            , selectedPlaylist =
                                Maybe.map
                                    (\p ->
                                        if p.name == name then
                                            { p | collection = False }

                                        else
                                            p
                                    )
                                    model.selectedPlaylist
                        }
                   )
                |> Return.singleton
                |> andThen User.savePlaylists

        Nothing ->
            Return.singleton model


convertPlaylistToCollection : { name : String } -> Manager
convertPlaylistToCollection { name } model =
    case
        List.findIndex
            (\p -> Maybe.isNothing p.autoGenerated && p.name == name)
            model.playlists
    of
        Just playlistIndex ->
            model.playlists
                |> List.updateAt
                    playlistIndex
                    (\p -> { p | collection = True })
                |> (\newInventory ->
                        { model
                            | playlists = newInventory
                            , selectedPlaylist =
                                Maybe.map
                                    (\p ->
                                        if p.name == name then
                                            { p | collection = True }

                                        else
                                            p
                                    )
                                    model.selectedPlaylist
                        }
                   )
                |> Return.singleton
                |> andThen User.savePlaylists

        Nothing ->
            Return.singleton model


create : { collection : Bool } -> Manager
create { collection } model =
    case model.newPlaylistContext of
        Just playlistName ->
            let
                alreadyExists =
                    List.find
                        (.name >> (==) playlistName)
                        (List.filterNot (.autoGenerated >> Maybe.isJust) model.playlists)

                playlist =
                    { autoGenerated = Nothing
                    , collection = collection
                    , name = playlistName
                    , public = False
                    , tracks = []
                    }
            in
            case alreadyExists of
                Just existingPlaylist ->
                    (if existingPlaylist.collection then
                        "There's already a collection using this name"

                     else
                        "There's already a playlist using this name"
                    )
                        |> Notifications.error
                        |> Common.showNotificationWithModel model

                Nothing ->
                    { model
                        | lastModifiedPlaylist =
                            Just
                                { collection = playlist.collection
                                , name = playlist.name
                                }
                        , newPlaylistContext = Nothing
                        , playlists = playlist :: model.playlists
                    }
                        |> User.savePlaylists
                        |> andThen redirectToPlaylistIndexPage

        Nothing ->
            Return.singleton model


createCollection : Manager
createCollection =
    create { collection = True }


createPlaylist : Manager
createPlaylist =
    create { collection = False }


deactivate : Manager
deactivate =
    deselect


deselect : Manager
deselect model =
    { model | selectedPlaylist = Nothing }
        |> Tracks.reviseCollection Tracks.Collection.arrange
        |> andThen User.saveEnclosedUserData


delete : { playlistName : String } -> Manager
delete { playlistName } model =
    let
        selectedPlaylist =
            Maybe.map
                (\p -> ( p.autoGenerated, p.name ))
                model.selectedPlaylist

        ( selectedPlaylistChanged, newSelectedPlaylist ) =
            if selectedPlaylist == Just ( Nothing, playlistName ) then
                ( True, Nothing )

            else
                ( False, model.selectedPlaylist )
    in
    model.playlists
        |> List.filter
            (\p ->
                if Maybe.isJust p.autoGenerated then
                    True

                else
                    p.name /= playlistName
            )
        |> (\col ->
                { model
                    | playlists = col
                    , selectedPlaylist = newSelectedPlaylist
                }
           )
        |> (if selectedPlaylistChanged then
                Tracks.reviseCollection Tracks.Collection.arrange

            else
                Return.singleton
           )
        |> andThen User.savePlaylists


modify : Manager
modify model =
    case model.editPlaylistContext of
        Just { oldName, newName } ->
            let
                properName =
                    String.trim newName

                validName =
                    String.isEmpty properName == False

                ( autoGenerated, notAutoGenerated ) =
                    List.partition (.autoGenerated >> Maybe.isJust) model.playlists

                alreadyExists =
                    List.find
                        (.name >> (==) properName)
                        notAutoGenerated

                newCollection =
                    List.map
                        (\p -> ifThenElse (p.name == oldName) { p | name = properName } p)
                        notAutoGenerated
            in
            case alreadyExists of
                Just existingPlaylist ->
                    (if existingPlaylist.collection then
                        "There's already a collection using this name"

                     else
                        "There's already a playlist using this name"
                    )
                        |> Notifications.error
                        |> Common.showNotificationWithModel
                            { model | editPlaylistContext = Nothing }

                Nothing ->
                    if validName then
                        { model
                            | editPlaylistContext = Nothing
                            , lastModifiedPlaylist =
                                case model.lastModifiedPlaylist of
                                    Just l ->
                                        if l.name == oldName then
                                            Just { l | name = newName }

                                        else
                                            Just l

                                    Nothing ->
                                        Nothing
                            , playlists = newCollection ++ autoGenerated
                        }
                            |> User.savePlaylists
                            |> andThen redirectToPlaylistIndexPage

                    else
                        redirectToPlaylistIndexPage model

        Nothing ->
            redirectToPlaylistIndexPage model


moveTrackInSelected : { to : Int } -> Manager
moveTrackInSelected { to } model =
    case model.selectedPlaylist of
        Just playlist ->
            let
                moveParams =
                    { from = Maybe.withDefault 0 (List.head model.selectedTrackIndexes)
                    , to = to
                    , amount = List.length model.selectedTrackIndexes
                    }

                updatedPlaylist =
                    { playlist | tracks = List.move moveParams playlist.tracks }

                updatedPlaylistCollection =
                    List.map
                        (\p ->
                            ifThenElse
                                (p.autoGenerated == Nothing && p.name == updatedPlaylist.name)
                                updatedPlaylist
                                p
                        )
                        model.playlists
            in
            { model
                | playlists = updatedPlaylistCollection
                , selectedPlaylist = Just updatedPlaylist
            }
                |> Tracks.reviseCollection Tracks.Collection.arrange
                |> andThen User.savePlaylists

        Nothing ->
            Return.singleton model


removeTracks : Playlist -> List IdentifiedTrack -> Manager
removeTracks playlist tracks model =
    let
        updatedPlaylist =
            Tracks.removeFromPlaylist tracks playlist
    in
    model.playlists
        |> List.map
            (\p ->
                if p.name == playlist.name then
                    updatedPlaylist

                else
                    p
            )
        |> (\c -> { model | playlists = c })
        |> select updatedPlaylist
        |> andThen User.savePlaylists


select : Playlist -> Manager
select playlist model =
    { model | page = Page.Index, selectedPlaylist = Just playlist }
        |> Tracks.reviseCollection Tracks.Collection.arrange
        |> andThen User.saveEnclosedUserData


setCreationContext : String -> Manager
setCreationContext playlistName model =
    Return.singleton { model | newPlaylistContext = Just playlistName }


setModificationContext : String -> String -> Manager
setModificationContext oldName newName model =
    let
        context =
            { oldName = oldName
            , newName = newName
            }
    in
    Return.singleton { model | editPlaylistContext = Just context }


showListMenu : Playlist -> Mouse.Event -> Manager
showListMenu playlist mouseEvent model =
    let
        coordinates =
            Coordinates.fromTuple mouseEvent.clientPos

        contextMenu =
            Playlists.listMenu
                playlist
                model.tracks.identified
                model.confirmation
                coordinates
    in
    Return.singleton { model | contextMenu = Just contextMenu }


toggleVisibility : Playlist -> Manager
toggleVisibility playlist model =
    let
        updatedPlaylist =
            { playlist | public = not playlist.public }
    in
    model.playlists
        |> List.map
            (\p ->
                if p.name == playlist.name then
                    updatedPlaylist

                else
                    p
            )
        |> (\c -> { model | playlists = c })
        |> User.savePlaylists



-- ㊙️


redirectToPlaylistIndexPage : Manager
redirectToPlaylistIndexPage =
    Common.changeUrlUsingPage (Page.Playlists Index)
