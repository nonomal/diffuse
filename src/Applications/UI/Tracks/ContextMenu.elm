module UI.Tracks.ContextMenu exposing (trackMenu, viewMenu)

import Conditional exposing (ifThenElse)
import ContextMenu exposing (..)
import Coordinates exposing (Coordinates)
import Material.Icons.Action as Icons
import Material.Icons.Av as Icons
import Material.Icons.Content as Icons
import Maybe.Extra as Maybe
import Playlists exposing (Playlist)
import Tracks exposing (Grouping(..), IdentifiedTrack)
import UI.Core exposing (Msg(..))
import UI.Queue.Core as Queue
import UI.Reply
import UI.Tracks.Core as Tracks



-- TRACK MENU


trackMenu : List IdentifiedTrack -> Maybe Playlist -> Maybe String -> Coordinates -> ContextMenu Msg
trackMenu tracks selectedPlaylist lastModifiedPlaylist =
    [ queueActions tracks
    , playlistActions tracks selectedPlaylist lastModifiedPlaylist
    ]
        |> List.concat
        |> ContextMenu


playlistActions : List IdentifiedTrack -> Maybe Playlist -> Maybe String -> List (ContextMenu.Item Msg)
playlistActions tracks selectedPlaylist lastModifiedPlaylist =
    let
        maybeCustomPlaylist =
            Maybe.andThen
                (\p -> ifThenElse p.autoGenerated Nothing (Just p))
                selectedPlaylist

        maybeAddToLastModifiedPlaylist =
            Maybe.andThen
                (\n ->
                    if Maybe.map .name selectedPlaylist /= Just n then
                        justAnItem
                            { icon = Icons.waves
                            , label = "Add to \"" ++ n ++ "\""
                            , msg =
                                { playlistName = n, tracks = Tracks.toPlaylistTracks tracks }
                                    |> UI.Reply.AddTracksToPlaylist
                                    |> Reply
                            , active = False
                            }

                    else
                        Nothing
                )
                lastModifiedPlaylist
    in
    case maybeCustomPlaylist of
        -----------------------------------------
        -- In a custom playlist
        -----------------------------------------
        Just playlist ->
            Maybe.values
                [ justAnItem
                    { icon = Icons.waves
                    , label = "Remove from playlist"
                    , msg = RemoveFromSelectedPlaylist playlist tracks
                    , active = False
                    }
                , maybeAddToLastModifiedPlaylist
                , justAnItem
                    { icon = Icons.waves
                    , label = "Add to another playlist"
                    , msg = RequestAssistanceForPlaylists tracks
                    , active = False
                    }
                ]

        -----------------------------------------
        -- Otherwise
        -----------------------------------------
        _ ->
            Maybe.values
                [ maybeAddToLastModifiedPlaylist
                , justAnItem
                    { icon = Icons.waves
                    , label = "Add to playlist"
                    , msg = RequestAssistanceForPlaylists tracks
                    , active = False
                    }
                ]


queueActions : List IdentifiedTrack -> List (ContextMenu.Item Msg)
queueActions identifiedTracks =
    [ Item
        { icon = Icons.update
        , label = "Play next"
        , msg = QueueMsg (Queue.InjectFirst { showNotification = True } identifiedTracks)
        , active = False
        }
    , Item
        { icon = Icons.update
        , label = "Add to queue"
        , msg = QueueMsg (Queue.InjectLast { showNotification = True } identifiedTracks)
        , active = False
        }
    ]



-- VIEW MENU


viewMenu : Maybe Grouping -> Coordinates -> ContextMenu Msg
viewMenu maybeGrouping =
    ContextMenu
        [ groupByDirectory (maybeGrouping == Just Directory)
        , groupByProcessingDate (maybeGrouping == Just AddedOnGroups)
        , groupByTrackYear (maybeGrouping == Just TrackYearGroups)
        ]


groupByDirectory isActive =
    Item
        { icon = ifThenElse isActive Icons.clear Icons.library_music
        , label = "Group by directory"
        , active = isActive

        --
        , msg =
            if isActive then
                TracksMsg Tracks.DisableGrouping

            else
                TracksMsg (Tracks.GroupBy Directory)
        }


groupByProcessingDate isActive =
    Item
        { icon = ifThenElse isActive Icons.clear Icons.library_music
        , label = "Group by processing date"
        , active = isActive

        --
        , msg =
            if isActive then
                TracksMsg Tracks.DisableGrouping

            else
                TracksMsg (Tracks.GroupBy AddedOnGroups)
        }


groupByTrackYear isActive =
    Item
        { icon = ifThenElse isActive Icons.clear Icons.library_music
        , label = "Group by track year"
        , active = isActive

        --
        , msg =
            if isActive then
                TracksMsg Tracks.DisableGrouping

            else
                TracksMsg (Tracks.GroupBy TrackYearGroups)
        }
