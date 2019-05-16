module Tracks.Collection.Internal.Arrange exposing (arrange)

import Conditional exposing (ifThenElse)
import Dict exposing (Dict)
import List.Extra as List
import Maybe.Extra as Maybe
import Time
import Time.Ext as Time
import Tracks exposing (..)
import Tracks.Sorting as Sorting



-- 🍯


arrange : Parcel -> Parcel
arrange ( deps, collection ) =
    case deps.grouping of
        Just AddedOnGroups ->
            ( deps, groupByInsertedAt deps collection )

        Just Directory ->
            ( deps, groupByDirectory deps collection )

        Just TrackYearGroups ->
            ( deps, groupByYear deps collection )

        Nothing ->
            collection.identified
                |> Sorting.sort deps.sortBy deps.sortDirection
                |> (\x -> { collection | arranged = x })
                |> (\x -> ( deps, x ))



-- GROUPING


addToList : a -> Maybe (List a) -> Maybe (List a)
addToList item maybeList =
    case maybeList of
        Just list ->
            Just (item :: list)

        Nothing ->
            Just [ item ]


groupBy : { reversed : Bool } -> (IdentifiedTrack -> Dict a (List IdentifiedTrack) -> Dict a (List IdentifiedTrack)) -> CollectionDependencies -> Collection -> Collection
groupBy { reversed } folder deps collection =
    collection.identified
        |> List.foldl folder Dict.empty
        |> Dict.values
        |> ifThenElse reversed List.reverse identity
        |> List.concatMap (Sorting.sort deps.sortBy deps.sortDirection)
        |> (\arranged -> { collection | arranged = arranged })



-- GROUPING  ░░  INSERTED AT


groupByInsertedAt : CollectionDependencies -> Collection -> Collection
groupByInsertedAt =
    groupBy { reversed = True } groupByInsertedAtFolder


groupByInsertedAtFolder : IdentifiedTrack -> Dict Int (List IdentifiedTrack) -> Dict Int (List IdentifiedTrack)
groupByInsertedAtFolder ( i, t ) =
    let
        ( year, month ) =
            ( Time.toYear Time.utc t.insertedAt
            , Time.toMonth Time.utc t.insertedAt
            )

        group =
            { name = insertedAtGroupName year month
            , firstInGroup = False
            }

        item =
            ( { i | group = Just group }
            , t
            )
    in
    Dict.update
        (year * 1000 + Time.monthNumber month)
        (addToList item)


insertedAtGroupName : Int -> Time.Month -> String
insertedAtGroupName year month =
    if year == 1970 then
        "I HONESTLY CAN'T REMEMBER"

    else
        Time.monthName month ++ " " ++ String.fromInt year



-- GROUPING  ░░  DIRECTORY


groupByDirectory : CollectionDependencies -> Collection -> Collection
groupByDirectory =
    groupBy { reversed = False } groupByDirectoryFolder


groupByDirectoryFolder : IdentifiedTrack -> Dict String (List IdentifiedTrack) -> Dict String (List IdentifiedTrack)
groupByDirectoryFolder ( i, t ) =
    -- TODO:
    -- When directory playlists are added, and if one is active,
    -- remove the first (ie. root) directory.
    let
        directory =
            t.path
                |> String.split "/"
                |> List.init
                |> Maybe.map (String.join " / ")
                |> Maybe.withDefault t.path

        group =
            { name = directory
            , firstInGroup = False
            }

        item =
            ( { i | group = Just group }
            , t
            )
    in
    Dict.update
        directory
        (addToList item)



-- GROUPING  ░░  YEAR


groupByYear : CollectionDependencies -> Collection -> Collection
groupByYear =
    groupBy { reversed = True } groupByYearFolder


groupByYearFolder : IdentifiedTrack -> Dict Int (List IdentifiedTrack) -> Dict Int (List IdentifiedTrack)
groupByYearFolder ( i, t ) =
    let
        group =
            { name = Maybe.unwrap "0000 - Unknown" String.fromInt t.tags.year
            , firstInGroup = False
            }

        item =
            ( { i | group = Just group }
            , t
            )
    in
    Dict.update
        (Maybe.withDefault 0 t.tags.year)
        (addToList item)
