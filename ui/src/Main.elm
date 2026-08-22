module Main exposing (main)

import Browser
import Dag
    exposing
        ( Edge
        , Node
        , Status(..)
        , Workflow
        )
import Html exposing (Html, button, div, h1, h2, input, label, li, option, p, select, span, textarea, ul)
import Html.Attributes as Attr
import Html.Events as Events
import Json.Decode as Decode
import Svg exposing (Svg)
import Svg.Attributes as SvgAttr
import Svg.Events as SvgEvents


main : Program () Model Msg
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }


type alias Model =
    { workflow : Workflow
    , draftId : String
    , draftName : String
    , draftTaskType : String
    , draftStatus : Status
    , selected : Maybe String
    , jsonText : String
    , notice : Maybe String
    }


init : Model
init =
    { workflow = Dag.empty
    , draftId = ""
    , draftName = ""
    , draftTaskType = "shell"
    , draftStatus = Pending
    , selected = Nothing
    , jsonText = Dag.encodePretty Dag.empty
    , notice = Nothing
    }


type Msg
    = TypedId String
    | TypedName String
    | TypedTaskType String
    | PickedStatus String
    | AddNode
    | ClickNode String
    | ClearSelection
    | RemoveNode String
    | RemoveEdge String String
    | TypedJson String
    | LoadJson
    | SyncJson


update : Msg -> Model -> Model
update msg model =
    case msg of
        TypedId value ->
            { model | draftId = value }

        TypedName value ->
            { model | draftName = value }

        TypedTaskType value ->
            { model | draftTaskType = value }

        PickedStatus value ->
            { model | draftStatus = Dag.statusFromString value }

        AddNode ->
            addDraftNode model

        ClickNode id ->
            connectOrSelect id model

        ClearSelection ->
            { model | selected = Nothing, notice = Nothing }

        RemoveNode id ->
            refreshJson
                { model
                    | workflow = Dag.removeNode id model.workflow
                    , selected =
                        if model.selected == Just id then
                            Nothing

                        else
                            model.selected
                    , notice = Nothing
                }

        RemoveEdge from to ->
            refreshJson
                { model
                    | workflow = Dag.removeEdge from to model.workflow
                    , notice = Nothing
                }

        TypedJson value ->
            { model | jsonText = value }

        LoadJson ->
            case Decode.decodeString Dag.decode model.jsonText of
                Err err ->
                    { model | notice = Just (Dag.errorToString (Dag.InvalidJson (Decode.errorToString err))) }

                Ok workflow ->
                    { model
                        | workflow = workflow
                        , selected = Nothing
                        , jsonText = Dag.encodePretty workflow
                        , notice =
                            if Dag.hasCycle workflow then
                                Just "Loaded document contains a cycle. Topological order is unavailable until an edge is removed."

                            else
                                Just "Loaded workflow document."
                    }

        SyncJson ->
            refreshJson { model | notice = Just "JSON synced from the current graph." }


addDraftNode : Model -> Model
addDraftNode model =
    let
        id =
            assignId model.draftId model.draftName model.workflow
    in
    case
        Dag.addNode
            (Dag.node
                id
                (if String.isEmpty (String.trim model.draftName) then
                    id

                 else
                    String.trim model.draftName
                )
                (String.trim model.draftTaskType)
                model.draftStatus
            )
            model.workflow
    of
        Err err ->
            { model | notice = Just (Dag.errorToString err) }

        Ok workflow ->
            refreshJson
                { model
                    | workflow = workflow
                    , draftId = ""
                    , draftName = ""
                    , notice = Nothing
                }


connectOrSelect : String -> Model -> Model
connectOrSelect id model =
    case model.selected of
        Nothing ->
            { model
                | selected = Just id
                , notice = Just ("Selected " ++ id ++ ". Click a downstream task to connect.")
            }

        Just from ->
            if from == id then
                { model | selected = Nothing, notice = Nothing }

            else
                case Dag.addEdge from id model.workflow of
                    Err err ->
                        { model
                            | selected = Nothing
                            , notice = Just (Dag.errorToString err)
                        }

                    Ok workflow ->
                        refreshJson
                            { model
                                | workflow = workflow
                                , selected = Nothing
                                , notice = Just ("Connected " ++ from ++ " -> " ++ id)
                            }


refreshJson : Model -> Model
refreshJson model =
    { model | jsonText = Dag.encodePretty model.workflow }


assignId : String -> String -> Workflow -> String
assignId draftId draftName workflow =
    let
        trimmed =
            String.trim draftId

        base =
            if not (String.isEmpty trimmed) then
                trimmed

            else
                let
                    slug =
                        draftName
                            |> String.trim
                            |> String.toLower
                            |> String.map
                                (\char ->
                                    if Char.isAlphaNum char then
                                        char

                                    else
                                        '-'
                                )
                            |> String.filter (\char -> Char.isAlphaNum char || char == '-')
                in
                if String.isEmpty slug then
                    "task"

                else
                    slug
    in
    uniqueId base workflow 1


uniqueId : String -> Workflow -> Int -> String
uniqueId base workflow n =
    let
        candidate =
            if n == 1 then
                base

            else
                base ++ "-" ++ String.fromInt n
    in
    if List.any (\item -> item.id == candidate) workflow.nodes then
        uniqueId base workflow (n + 1)

    else
        candidate


view : Model -> Html Msg
view model =
    div [ Attr.class "app" ]
        [ Html.node "link" [ Attr.rel "stylesheet", Attr.href "/styles.css" ] []
        , header
        , noticeBanner model
        , div [ Attr.class "workspace" ]
            [ toolbox model
            , canvasPanel model
            , documentPanel model
            ]
        ]


header : Html Msg
header =
    Html.header [ Attr.class "masthead" ]
        [ h1 [] [ Html.text "dolphin-dag" ]
        , p []
            [ Html.text "DolphinScheduler-style workflow DAG editor. Rust owns the document; this Elm canvas edits the same JSON." ]
        ]


noticeBanner : Model -> Html Msg
noticeBanner model =
    let
        cycle =
            Dag.hasCycle model.workflow

        ( className, body ) =
            if cycle then
                ( "banner banner-cycle"
                , Maybe.withDefault "This graph has a cycle." model.notice
                )

            else
                case model.notice of
                    Nothing ->
                        ( "banner banner-quiet", "Add tasks, then click two nodes to draw an edge. Cycles are rejected." )

                    Just text ->
                        if String.contains "Cycle rejected" text then
                            ( "banner banner-cycle", text )

                        else
                            ( "banner banner-ok", text )
    in
    div [ Attr.class className ] [ Html.text body ]


toolbox : Model -> Html Msg
toolbox model =
    div [ Attr.class "panel toolbox" ]
        [ h2 [] [ Html.text "Add task" ]
        , labeledInput "Id" "extract" model.draftId TypedId
        , labeledInput "Name" "Extract logs" model.draftName TypedName
        , labeledInput "Task type" "shell" model.draftTaskType TypedTaskType
        , label [ Attr.class "field" ]
            [ span [] [ Html.text "Status" ]
            , select [ Events.onInput PickedStatus ]
                (List.map
                    (statusOption model.draftStatus)
                    [ Pending, Running, Success, Failure ]
                )
            ]
        , button [ Attr.class "primary", Events.onClick AddNode ] [ Html.text "Add node" ]
        , p [ Attr.class "hint" ]
            [ Html.text "Leave id blank to slug the name. Click a source node, then a target node, to connect." ]
        , h2 [] [ Html.text "Nodes" ]
        , ul [ Attr.class "item-list" ]
            (List.map nodeRow model.workflow.nodes)
        , h2 [] [ Html.text "Edges" ]
        , ul [ Attr.class "item-list" ]
            (List.map edgeRow model.workflow.edges)
        ]


labeledInput : String -> String -> String -> (String -> Msg) -> Html Msg
labeledInput title placeholder value toMsg =
    label [ Attr.class "field" ]
        [ span [] [ Html.text title ]
        , input
            [ Attr.type_ "text"
            , Attr.placeholder placeholder
            , Attr.value value
            , Events.onInput toMsg
            ]
            []
        ]


statusOption : Status -> Status -> Html Msg
statusOption current status =
    option
        [ Attr.value (Dag.statusToString status)
        , Attr.selected (current == status)
        ]
        [ Html.text (Dag.statusToString status) ]


nodeRow : Node -> Html Msg
nodeRow item =
    li []
        [ button [ Attr.class "link", Events.onClick (ClickNode item.id) ]
            [ Html.text item.name
            , span [ Attr.class "muted" ] [ Html.text (" · " ++ item.id) ]
            ]
        , button [ Attr.class "danger-quiet", Events.onClick (RemoveNode item.id) ]
            [ Html.text "remove" ]
        ]


edgeRow : Edge -> Html Msg
edgeRow edge =
    li []
        [ span [] [ Html.text (edge.from ++ " → " ++ edge.to) ]
        , button [ Attr.class "danger-quiet", Events.onClick (RemoveEdge edge.from edge.to) ]
            [ Html.text "remove" ]
        ]


canvasPanel : Model -> Html Msg
canvasPanel model =
    let
        placed =
            placeNodes model.workflow

        width =
            placed
                |> List.map (\item -> item.x + nodeWidth + 48)
                |> List.maximum
                |> Maybe.withDefault 640
                |> max 640

        height =
            placed
                |> List.map (\item -> item.y + nodeHeight + 48)
                |> List.maximum
                |> Maybe.withDefault 360
                |> max 360
    in
    div [ Attr.class "panel canvas-panel" ]
        [ div [ Attr.class "canvas-head" ]
            [ h2 [] [ Html.text "Workflow canvas" ]
            , button [ Events.onClick ClearSelection ] [ Html.text "Clear selection" ]
            ]
        , if List.isEmpty model.workflow.nodes then
            div [ Attr.class "empty-canvas" ]
                [ Html.text "No tasks yet. Add extract, transform, and load from the left, then connect them." ]

          else
            Svg.svg
                [ SvgAttr.class "canvas"
                , SvgAttr.viewBox ("0 0 " ++ String.fromFloat width ++ " " ++ String.fromFloat height)
                , SvgAttr.width (String.fromFloat width)
                , SvgAttr.height (String.fromFloat height)
                ]
                (arrowDef
                    :: List.map (drawEdge placed) model.workflow.edges
                    ++ List.map (drawNode model.selected) placed
                )
        , topoLine model.workflow
        ]


type alias Placed =
    { node : Node
    , x : Float
    , y : Float
    }


nodeWidth : Float
nodeWidth =
    168


nodeHeight : Float
nodeHeight =
    78


placeNodes : Workflow -> List Placed
placeNodes workflow =
    case Dag.topologicalOrder workflow of
        Err _ ->
            gridLayout workflow.nodes

        Ok ordered ->
            layerLayout workflow ordered


gridLayout : List Node -> List Placed
gridLayout nodes =
    List.indexedMap
        (\index item ->
            { node = item
            , x = 32 + toFloat (modBy 3 index) * (nodeWidth + 56)
            , y = 32 + toFloat (index // 3) * (nodeHeight + 36)
            }
        )
        nodes


layerLayout : Workflow -> List Node -> List Placed
layerLayout workflow ordered =
    let
        layerOf : Node -> Int
        layerOf item =
            Dag.incoming item.id workflow
                |> List.filterMap
                    (\parentId ->
                        List.filter (\other -> other.id == parentId) ordered
                            |> List.head
                            |> Maybe.map layerOf
                    )
                |> List.maximum
                |> Maybe.map ((+) 1)
                |> Maybe.withDefault 0

        layers : List ( Int, Node )
        layers =
            List.map (\item -> ( layerOf item, item )) ordered

        column : Int -> List Node
        column depth =
            layers
                |> List.filter (\( layer, _ ) -> layer == depth)
                |> List.map Tuple.second
    in
    layers
        |> List.map
            (\( layer, item ) ->
                let
                    siblings =
                        column layer

                    row =
                        siblings
                            |> List.indexedMap Tuple.pair
                            |> List.filter (\( _, sib ) -> sib.id == item.id)
                            |> List.head
                            |> Maybe.map Tuple.first
                            |> Maybe.withDefault 0
                in
                { node = item
                , x = 32 + toFloat layer * (nodeWidth + 72)
                , y = 32 + toFloat row * (nodeHeight + 36)
                }
            )


arrowDef : Svg Msg
arrowDef =
    Svg.defs []
        [ Svg.marker
            [ SvgAttr.id "arrow"
            , SvgAttr.viewBox "0 0 10 10"
            , SvgAttr.refX "10"
            , SvgAttr.refY "5"
            , SvgAttr.markerWidth "8"
            , SvgAttr.markerHeight "8"
            , SvgAttr.orient "auto"
            ]
            [ Svg.path
                [ SvgAttr.d "M 0 0 L 10 5 L 0 10 z"
                , SvgAttr.fill "#4a5d82"
                ]
                []
            ]
        ]


drawEdge : List Placed -> Edge -> Svg Msg
drawEdge placed edge =
    case ( findPlace edge.from placed, findPlace edge.to placed ) of
        ( Just source, Just target ) ->
            let
                x1 =
                    source.x + nodeWidth

                y1 =
                    source.y + nodeHeight / 2

                x2 =
                    target.x

                y2 =
                    target.y + nodeHeight / 2
            in
            Svg.line
                [ SvgAttr.x1 (String.fromFloat x1)
                , SvgAttr.y1 (String.fromFloat y1)
                , SvgAttr.x2 (String.fromFloat x2)
                , SvgAttr.y2 (String.fromFloat y2)
                , SvgAttr.class "edge"
                , SvgAttr.markerEnd "url(#arrow)"
                ]
                []

        _ ->
            Svg.g [] []


findPlace : String -> List Placed -> Maybe Placed
findPlace id placed =
    List.filter (\item -> item.node.id == id) placed
        |> List.head


drawNode : Maybe String -> Placed -> Svg Msg
drawNode selected placed =
    let
        active =
            selected == Just placed.node.id

        className =
            "task-card status-"
                ++ Dag.statusToString placed.node.status
                ++ (if active then
                        " selected"

                    else
                        ""
                   )
    in
    Svg.g
        [ SvgEvents.onClick (ClickNode placed.node.id)
        , SvgAttr.class className
        , SvgAttr.transform
            ("translate(" ++ String.fromFloat placed.x ++ " " ++ String.fromFloat placed.y ++ ")")
        ]
        [ Svg.rect
            [ SvgAttr.width (String.fromFloat nodeWidth)
            , SvgAttr.height (String.fromFloat nodeHeight)
            , SvgAttr.rx "8"
            ]
            []
        , Svg.text_
            [ SvgAttr.x "12"
            , SvgAttr.y "26"
            , SvgAttr.class "task-name"
            ]
            [ Svg.text placed.node.name ]
        , Svg.text_
            [ SvgAttr.x "12"
            , SvgAttr.y "46"
            , SvgAttr.class "task-meta"
            ]
            [ Svg.text (placed.node.taskType ++ " · " ++ placed.node.id) ]
        , Svg.text_
            [ SvgAttr.x "12"
            , SvgAttr.y "64"
            , SvgAttr.class "task-status"
            ]
            [ Svg.text (Dag.statusToString placed.node.status) ]
        ]


topoLine : Workflow -> Html Msg
topoLine workflow =
    case Dag.topologicalOrder workflow of
        Err _ ->
            p [ Attr.class "topo cycle" ] [ Html.text "Topological order: unavailable (cycle)." ]

        Ok order ->
            if List.isEmpty order then
                p [ Attr.class "topo" ] [ Html.text "Topological order: (empty)" ]

            else
                p [ Attr.class "topo" ]
                    [ Html.text
                        ("Topological order: "
                            ++ String.join " → " (List.map .id order)
                        )
                    ]


documentPanel : Model -> Html Msg
documentPanel model =
    div [ Attr.class "panel document" ]
        [ h2 [] [ Html.text "JSON document" ]
        , p [ Attr.class "hint" ]
            [ Html.text "Same shape Rust serde uses. Save by copying. Load pastes a document back into the graph." ]
        , textarea
            [ Attr.class "json"
            , Attr.value model.jsonText
            , Events.onInput TypedJson
            , Attr.spellcheck False
            ]
            []
        , div [ Attr.class "row" ]
            [ button [ Attr.class "primary", Events.onClick LoadJson ] [ Html.text "Load JSON" ]
            , button [ Events.onClick SyncJson ] [ Html.text "Reset from graph" ]
            ]
        ]
