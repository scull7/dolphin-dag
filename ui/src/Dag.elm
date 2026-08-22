module Dag exposing
    ( Edge
    , Error(..)
    , Node
    , Status(..)
    , Workflow
    , addEdge
    , addNode
    , decode
    , empty
    , encodePretty
    , errorToString
    , hasCycle
    , incoming
    , node
    , removeEdge
    , removeNode
    , statusFromString
    , statusToString
    , successors
    , topologicalOrder
    )

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


type Status
    = Pending
    | Running
    | Success
    | Failure


type alias Node =
    { id : String
    , name : String
    , taskType : String
    , status : Status
    }


type alias Edge =
    { from : String
    , to : String
    }


type alias Workflow =
    { nodes : List Node
    , edges : List Edge
    }


type Error
    = EmptyNodeId
    | DuplicateNode String
    | UnknownNode String
    | DuplicateEdge String String
    | Cycle String String
    | InvalidJson String


empty : Workflow
empty =
    { nodes = [], edges = [] }


node : String -> String -> String -> Status -> Node
node id name taskType status =
    { id = id
    , name = name
    , taskType = taskType
    , status = status
    }


addNode : Node -> Workflow -> Result Error Workflow
addNode newNode workflow =
    if String.isEmpty newNode.id then
        Err EmptyNodeId

    else if List.any (\existing -> existing.id == newNode.id) workflow.nodes then
        Err (DuplicateNode newNode.id)

    else
        Ok { workflow | nodes = workflow.nodes ++ [ newNode ] }


addEdge : String -> String -> Workflow -> Result Error Workflow
addEdge from to workflow =
    if not (containsNode from workflow) then
        Err (UnknownNode from)

    else if not (containsNode to workflow) then
        Err (UnknownNode to)

    else if List.any (\edge -> edge.from == from && edge.to == to) workflow.edges then
        Err (DuplicateEdge from to)

    else if from == to || reaches to from workflow then
        Err (Cycle from to)

    else
        Ok { workflow | edges = workflow.edges ++ [ { from = from, to = to } ] }


removeNode : String -> Workflow -> Workflow
removeNode id workflow =
    { nodes = List.filter (\item -> item.id /= id) workflow.nodes
    , edges =
        List.filter
            (\edge -> edge.from /= id && edge.to /= id)
            workflow.edges
    }


removeEdge : String -> String -> Workflow -> Workflow
removeEdge from to workflow =
    { workflow
        | edges =
            List.filter
                (\edge -> not (edge.from == from && edge.to == to))
                workflow.edges
    }


containsNode : String -> Workflow -> Bool
containsNode id workflow =
    List.any (\item -> item.id == id) workflow.nodes


successors : String -> Workflow -> List String
successors id workflow =
    workflow.edges
        |> List.filter (\edge -> edge.from == id)
        |> List.map .to


incoming : String -> Workflow -> List String
incoming id workflow =
    workflow.edges
        |> List.filter (\edge -> edge.to == id)
        |> List.map .from


reaches : String -> String -> Workflow -> Bool
reaches start goal workflow =
    let
        walk : List String -> List String -> Bool
        walk queue seen =
            case queue of
                [] ->
                    False

                current :: rest ->
                    if List.member current seen then
                        walk rest seen

                    else
                        let
                            next =
                                successors current workflow
                        in
                        if List.member goal next then
                            True

                        else
                            walk (rest ++ next) (current :: seen)
    in
    if start == goal then
        True

    else
        walk [ start ] []


hasCycle : Workflow -> Bool
hasCycle workflow =
    case topologicalOrder workflow of
        Err _ ->
            True

        Ok _ ->
            False


topologicalOrder : Workflow -> Result Error (List Node)
topologicalOrder workflow =
    let
        bump : String -> List ( String, Int ) -> List ( String, Int )
        bump id counts =
            List.map
                (\( other, degree ) ->
                    if other == id then
                        ( other, degree + 1 )

                    else
                        ( other, degree )
                )
                counts

        startDegrees : List ( String, Int )
        startDegrees =
            List.foldl
                (\edge counts -> bump edge.to counts)
                (List.map (\item -> ( item.id, 0 )) workflow.nodes)
                workflow.edges

        nodeById : String -> Maybe Node
        nodeById id =
            List.filter (\item -> item.id == id) workflow.nodes
                |> List.head

        step :
            List ( String, Int )
            -> List Node
            -> Result Error (List Node)
        step degrees acc =
            let
                ready =
                    degrees
                        |> List.filter (\( _, degree ) -> degree == 0)
                        |> List.map Tuple.first
                        |> List.sort
            in
            case ready of
                [] ->
                    if List.isEmpty degrees then
                        Ok acc

                    else
                        Err (Cycle "?" "?")

                id :: _ ->
                    let
                        remaining =
                            List.filter (\( other, _ ) -> other /= id) degrees

                        lowered =
                            List.map
                                (\( other, degree ) ->
                                    if List.member other (successors id workflow) then
                                        ( other, degree - 1 )

                                    else
                                        ( other, degree )
                                )
                                remaining
                    in
                    case nodeById id of
                        Nothing ->
                            Err (UnknownNode id)

                        Just item ->
                            step lowered (acc ++ [ item ])
    in
    if List.any (\item -> String.isEmpty item.id) workflow.nodes then
        Err EmptyNodeId

    else
        step startDegrees []


errorToString : Error -> String
errorToString err =
    case err of
        EmptyNodeId ->
            "Node id must not be empty."

        DuplicateNode id ->
            "Duplicate node id: " ++ id

        UnknownNode id ->
            "Unknown node id: " ++ id

        DuplicateEdge from to ->
            "Edge already exists: " ++ from ++ " -> " ++ to

        Cycle from to ->
            "Cycle rejected: " ++ from ++ " -> " ++ to ++ " would close a loop."

        InvalidJson reason ->
            "Invalid JSON: " ++ reason


statusToString : Status -> String
statusToString status =
    case status of
        Pending ->
            "pending"

        Running ->
            "running"

        Success ->
            "success"

        Failure ->
            "failure"


statusFromString : String -> Status
statusFromString raw =
    case raw of
        "running" ->
            Running

        "success" ->
            Success

        "failure" ->
            Failure

        _ ->
            Pending


encodePretty : Workflow -> String
encodePretty workflow =
    Encode.encode 2 (encode workflow)


encode : Workflow -> Encode.Value
encode workflow =
    Encode.object
        [ ( "nodes", Encode.list encodeNode workflow.nodes )
        , ( "edges", Encode.list encodeEdge workflow.edges )
        ]


encodeNode : Node -> Encode.Value
encodeNode item =
    Encode.object
        [ ( "id", Encode.string item.id )
        , ( "name", Encode.string item.name )
        , ( "task_type", Encode.string item.taskType )
        , ( "status", Encode.string (statusToString item.status) )
        ]


encodeEdge : Edge -> Encode.Value
encodeEdge edge =
    Encode.object
        [ ( "from", Encode.string edge.from )
        , ( "to", Encode.string edge.to )
        ]


decode : Decoder Workflow
decode =
    Decode.map2 Workflow
        (Decode.field "nodes" (Decode.list decodeNode))
        (Decode.field "edges" (Decode.list decodeEdge))


decodeNode : Decoder Node
decodeNode =
    Decode.map4 Node
        (Decode.field "id" Decode.string)
        (Decode.field "name" Decode.string)
        (Decode.field "task_type" Decode.string)
        (Decode.field "status" decodeStatus)


decodeEdge : Decoder Edge
decodeEdge =
    Decode.map2 Edge
        (Decode.field "from" Decode.string)
        (Decode.field "to" Decode.string)


decodeStatus : Decoder Status
decodeStatus =
    Decode.string
        |> Decode.andThen
            (\raw ->
                case raw of
                    "pending" ->
                        Decode.succeed Pending

                    "running" ->
                        Decode.succeed Running

                    "success" ->
                        Decode.succeed Success

                    "failure" ->
                        Decode.succeed Failure

                    other ->
                        Decode.fail ("unknown status: " ++ other)
            )
