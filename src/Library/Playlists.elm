module Playlists exposing (..)

import Time



-- 🌳


type alias Playlist =
    { autoGenerated : Maybe { level : Int }
    , collection : Bool
    , name : String
    , public : Bool
    , tracks : List PlaylistTrack
    }


type alias PlaylistTrackWithoutMetadata =
    { album : Maybe String
    , artist : Maybe String
    , title : String
    }


type alias PlaylistTrack =
    { album : Maybe String
    , artist : Maybe String
    , title : String

    --
    , insertedAt : Time.Posix
    }


type alias IdentifiedPlaylistTrack =
    ( Identifiers, PlaylistTrack )


type alias Identifiers =
    { index : Int }
