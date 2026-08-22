module Main exposing (main)

import Browser
import Dag
    exposing
        ( Edge
        , Node
        , Status(..)
        , Workflow
        )
import Html exposing (Html, button, div, h1, h2, input, label, li, option, p, select, span, text, textarea, ul)
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


type Guide
    = Hidden
    | ReadPipeline
    | ClickLoad
    | ClickExtract
    | Done


type alias Model =
    { workflow : Workflow
    , draftId : String
    , draftName : String
    , draftTaskType : String
    , draftStatus : Status
    , selected : Maybe String
    , jsonText : String
    , mutation : Maybe (Result Dag.Error String)
    , guide : Guide
    }


exampleWorkflow : Workflow
exampleWorkflow =
    { nodes =
        [ Dag.node "extract" "Extract logs" "shell" Pending
        , Dag.node "transform" "Transform" "python" Pending
        , Dag.node "load" "Load warehouse" "sql" Pending
        ]
    , edges =
        [ { from = "extract", to = "transform" }
        , { from = "transform", to = "load" }
        ]
    }


init : Model
init =
    exampleModel ReadPipeline


exampleModel : Guide -> Model
exampleModel guide =
    { workflow = exampleWorkflow
    , draftId = ""
    , draftName = ""
    , draftTaskType = "shell"
    , draftStatus = Pending
    , selected = Nothing
    , jsonText = Dag.encodePretty exampleWorkflow
    , mutation = Nothing
    , guide = guide
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
    | GuideNext
    | GuideSkip
    | GuideRestart
    | ResetExample


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
            advanceGuide { model | selected = Nothing, mutation = Nothing }

        RemoveNode id ->
            refreshJson
                { model
                    | workflow = Dag.removeNode id model.workflow
                    , selected =
                        if model.selected == Just id then
                            Nothing

                        else
                            model.selected
                    , mutation = Nothing
                }

        RemoveEdge from to ->
            refreshJson
                { model
                    | workflow = Dag.removeEdge from to model.workflow
                    , mutation = Nothing
                }

        TypedJson value ->
            { model | jsonText = value }

        LoadJson ->
            case Decode.decodeString Dag.decode model.jsonText of
                Err err ->
                    { model | mutation = Just (Err (Dag.InvalidJson (Decode.errorToString err))) }

                Ok workflow ->
                    { model
                        | workflow = workflow
                        , selected = Nothing
                        , jsonText = Dag.encodePretty workflow
                        , mutation = Just (Ok "loaded document")
                    }

        SyncJson ->
            refreshJson { model | mutation = Just (Ok "synced JSON from graph") }

        GuideNext ->
            case model.guide of
                ReadPipeline ->
                    { model | guide = ClickLoad, selected = Nothing, mutation = Nothing }

                _ ->
                    model

        GuideSkip ->
            { model | guide = Hidden }

        GuideRestart ->
            exampleModel ReadPipeline

        ResetExample ->
            exampleModel ReadPipeline


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
            { model | mutation = Just (Err err) }

        Ok workflow ->
            refreshJson
                { model
                    | workflow = workflow
                    , draftId = ""
                    , draftName = ""
                    , mutation = Just (Ok ("add_node " ++ id))
                }


connectOrSelect : String -> Model -> Model
connectOrSelect id model =
    case model.selected of
        Nothing ->
            advanceGuide
                { model
                    | selected = Just id
                    , mutation =
                        if guideOpen model.guide then
                            Nothing

                        else
                            Just (Ok ("selected " ++ id))
                }

        Just from ->
            if from == id then
                advanceGuide { model | selected = Nothing, mutation = Nothing }

            else
                case Dag.addEdge from id model.workflow of
                    Err err ->
                        advanceGuide
                            { model
                                | selected = Nothing
                                , mutation = Just (Err err)
                            }

                    Ok workflow ->
                        advanceGuide
                            (refreshJson
                                { model
                                    | workflow = workflow
                                    , selected = Nothing
                                    , mutation = Just (Ok ("add_edge " ++ from ++ " -> " ++ id))
                                }
                            )


advanceGuide : Model -> Model
advanceGuide model =
    case model.guide of
        ReadPipeline ->
            model

        ClickLoad ->
            if model.selected == Just "load" then
                { model | guide = ClickExtract }

            else
                model

        ClickExtract ->
            case model.mutation of
                Just (Err (Dag.WouldCycle "load" "extract")) ->
                    { model | guide = Done }

                _ ->
                    if model.selected == Just "load" then
                        model

                    else
                        { model | guide = ClickLoad }

        Hidden ->
            model

        Done ->
            model


guideOpen : Guide -> Bool
guideOpen guide =
    case guide of
        Hidden ->
            False

        Done ->
            False

        ReadPipeline ->
            True

        ClickLoad ->
            True

        ClickExtract ->
            True


guideTarget : Guide -> Maybe String
guideTarget guide =
    case guide of
        ClickLoad ->
            Just "load"

        ClickExtract ->
            Just "extract"

        ReadPipeline ->
            Nothing

        Hidden ->
            Nothing

        Done ->
            Nothing


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
        , resultBanner model
        , guideStrip model
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
            [ Html.text "DolphinScheduler-style DAG. Rust document, Elm editor." ]
        ]


resultBanner : Model -> Html Msg
resultBanner model =
    case model.guide of
        Done ->
            div [ Attr.class "result result-error" ]
                [ div [] [ Html.text "Can't connect Load warehouse to Extract logs. That would loop." ] ]

        ReadPipeline ->
            text ""

        ClickLoad ->
            text ""

        ClickExtract ->
            text ""

        Hidden ->
            rustResultBanner model


rustResultBanner : Model -> Html Msg
rustResultBanner model =
    let
        topo =
            Dag.topologicalOrder model.workflow

        ( className, body ) =
            case ( model.mutation, topo ) of
                ( Just (Err err), _ ) ->
                    ( "result result-error", Dag.formatError err )

                ( _, Err err ) ->
                    ( "result result-error", "topological_order " ++ Dag.formatError err )

                ( Just (Ok okText), Ok _ ) ->
                    ( "result result-ok", "Ok (" ++ okText ++ ")" )

                ( Nothing, Ok _ ) ->
                    ( "result result-quiet", "add_edge : Result WouldCycle (). Select two nodes to connect." )
    in
    div [ Attr.class className ]
        [ div [] [ Html.text body ]
        , div [ Attr.class "result-line" ]
            [ Html.text ("topological_order : " ++ Dag.formatTopo topo) ]
        ]


guideStrip : Model -> Html Msg
guideStrip model =
    case model.guide of
        Hidden ->
            text ""

        ReadPipeline ->
            guideRow "This is a one-way pipeline. Extract logs feeds Transform, which feeds Load warehouse."
                [ button [ Attr.class "primary", Events.onClick GuideNext ] [ Html.text "Next" ]
                , ghost "Skip" GuideSkip
                ]

        ClickLoad ->
            guideRow "Now try sending work backward. Click Load warehouse."
                [ ghost "Skip" GuideSkip
                ]

        ClickExtract ->
            guideRow "Click Extract logs. That would send Load warehouse back into Extract logs and loop forever."
                [ ghost "Skip" GuideSkip
                ]

        Done ->
            guideRow "Stopped. That would loop forever. The real pipeline is unchanged: extract → transform → load. You can keep editing."
                [ ghost "Restart" GuideRestart
                , ghost "Skip" GuideSkip
                ]


guideRow : String -> List (Html Msg) -> Html Msg
guideRow copy actions =
    div [ Attr.class "guide" ]
        [ div [ Attr.class "guide-copy" ] [ Html.text copy ]
        , div [ Attr.class "guide-actions" ] actions
        ]


ghost : String -> Msg -> Html Msg
ghost label msg =
    button [ Attr.class "ghost", Events.onClick msg ] [ Html.text label ]


toolbox : Model -> Html Msg
toolbox model =
    div [ Attr.class "panel toolbox" ]
        [ h2 [] [ Html.text "Task" ]
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
        , button [ Attr.class "primary", Events.onClick AddNode ] [ Html.text "Add" ]
        , p [ Attr.class "hint" ]
            [ Html.text "Blank id slugs the name. Select a source, then a target." ]
        , h2 [] [ Html.text "Nodes" ]
        , ul [ Attr.class "item-list" ]
            (List.map (nodeRow model.selected (guideTarget model.guide)) model.workflow.nodes)
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


nodeRow : Maybe String -> Maybe String -> Node -> Html Msg
nodeRow selected target item =
    let
        rowClass =
            String.join " "
                (List.filter (not << String.isEmpty)
                    [ if selected == Just item.id then
                        "selected-row"

                      else
                        ""
                    , if target == Just item.id then
                        "target"

                      else
                        ""
                    ]
                )
    in
    li [ Attr.class rowClass ]
        [ button [ Attr.class "ghost row-action", Events.onClick (ClickNode item.id) ]
            [ Html.text item.name
            , span [ Attr.class "muted" ] [ Html.text (" · " ++ item.id) ]
            ]
        , if target == Just item.id then
            span [ Attr.class "target-label" ] [ Html.text "Click" ]

          else
            text ""
        , button [ Attr.class "danger", Events.onClick (RemoveNode item.id) ]
            [ Html.text "Remove" ]
        ]


edgeRow : Edge -> Html Msg
edgeRow edge =
    li []
        [ span [] [ Html.text (edge.from ++ " → " ++ edge.to) ]
        , button [ Attr.class "danger", Events.onClick (RemoveEdge edge.from edge.to) ]
            [ Html.text "Remove" ]
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
            [ h2 [] [ Html.text "Graph" ]
            , div [ Attr.class "guide-actions" ]
                [ button [ Attr.class "ghost", Events.onClick ClearSelection ] [ Html.text "Clear" ]
                , button [ Attr.class "ghost", Events.onClick ResetExample ] [ Html.text "Reset example" ]
                ]
            ]
        , if List.isEmpty model.workflow.nodes then
            div [ Attr.class "empty-canvas" ]
                [ Html.text "Add extract, transform, and load, then connect them." ]

          else
            Svg.svg
                [ SvgAttr.class "canvas"
                , SvgAttr.viewBox ("0 0 " ++ String.fromFloat width ++ " " ++ String.fromFloat height)
                , SvgAttr.width (String.fromFloat width)
                , SvgAttr.height (String.fromFloat height)
                ]
                (arrowDef
                    :: List.map (drawEdge placed) model.workflow.edges
                    ++ List.map (drawNode model.selected (guideTarget model.guide)) placed
                )
        , topoLine model.guide model.workflow
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
                , SvgAttr.class "edge-arrow"
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


drawNode : Maybe String -> Maybe String -> Placed -> Svg Msg
drawNode selected target placed =
    let
        active =
            selected == Just placed.node.id

        targeted =
            target == Just placed.node.id

        className =
            "task-card status-"
                ++ Dag.statusToString placed.node.status
                ++ (if active then
                        " selected"

                    else
                        ""
                   )
                ++ (if targeted then
                        " target"

                    else
                        ""
                   )

        clickMark =
            if targeted then
                [ Svg.text_
                    [ SvgAttr.x (String.fromFloat (nodeWidth - 12))
                    , SvgAttr.y "18"
                    , SvgAttr.class "task-click"
                    , SvgAttr.textAnchor "end"
                    ]
                    [ Svg.text "Click" ]
                ]

            else
                []
    in
    Svg.g
        [ SvgEvents.onClick (ClickNode placed.node.id)
        , SvgAttr.class className
        , SvgAttr.transform
            ("translate(" ++ String.fromFloat placed.x ++ " " ++ String.fromFloat placed.y ++ ")")
        ]
        ([ Svg.rect
            [ SvgAttr.width (String.fromFloat nodeWidth)
            , SvgAttr.height (String.fromFloat nodeHeight)
            , SvgAttr.rx "4"
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
            ++ clickMark
        )


topoLine : Guide -> Workflow -> Html Msg
topoLine guide workflow =
    case guide of
        Hidden ->
            rustTopoLine workflow

        _ ->
            text ""


rustTopoLine : Workflow -> Html Msg
rustTopoLine workflow =
    let
        result =
            Dag.topologicalOrder workflow

        className =
            case result of
                Err _ ->
                    "topo cycle"

                Ok _ ->
                    "topo"
    in
    p [ Attr.class className ]
        [ Html.text ("topological_order : " ++ Dag.formatTopo result) ]


documentPanel : Model -> Html Msg
documentPanel model =
    div [ Attr.class "panel document" ]
        [ h2 [] [ Html.text "Document" ]
        , p [ Attr.class "hint" ]
            [ Html.text "Shared JSON. Copy to save; Load applies the textarea." ]
        , textarea
            [ Attr.class "json"
            , Attr.value model.jsonText
            , Events.onInput TypedJson
            , Attr.spellcheck False
            ]
            []
        , div [ Attr.class "row" ]
            [ button [ Attr.class "primary", Events.onClick LoadJson ] [ Html.text "Load" ]
            , button [ Attr.class "ghost", Events.onClick SyncJson ] [ Html.text "Reset" ]
            ]
        ]
