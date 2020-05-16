module LambdaRepl exposing (main)


import Browser
import Browser.Dom
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Keyboard.Event exposing (KeyboardEvent)
import Keyboard.Key
import Task
import Json.Decode
import Dict exposing (Dict)
import LambdaParser exposing (Def, Expr)
import LambdaChecker
import LambdaEvaluator exposing (EvalStrategy(..))
import Location exposing (Located)
import Element as E
import Element.Input as Input
import Element.Font as Font
import Element.Border as Border
import Element.Events


type alias Model =
  { cells : Dict Int Cell
  , activeCellIndex : Int
  , evalStrategy : EvalStrategy
  }


type Msg
  = EditCell String
  | ActivateCell Int
  | HandleKeyDown KeyboardEvent
  | NoOp


type alias Cell =
  (String, Result String Def)


colors =
  { lightGrey =
    E.rgb255 220 220 220
  }


main : Program () Model Msg
main =
  Browser.element
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }


init : () -> (Model, Cmd Msg)
init _ =
  ( { cells =
      Dict.singleton 0 emptyCell
    , activeCellIndex =
      0
    , evalStrategy =
      CallByValue
    }
  , Cmd.none
  )


emptyCell : Cell
emptyCell =
  ("", Err "")


view : Model -> Html Msg
view model =
  E.layout
  [ Font.family
    [ Font.monospace
    ]
  , E.padding 30
  , E.width ( E.fill |> E.maximum 700 )
  , E.htmlAttribute <| Html.Attributes.style "margin" "auto"
  ] <|
  E.column
  [ E.spacing 15
  , E.width E.fill
  ] <|
  List.indexedMap
    (\index result ->
      viewCell model.activeCellIndex index result
    )
    (Dict.values model.cells)


viewCell : Int -> Int -> (String, Result String Def) -> E.Element Msg
viewCell activeCellIndex currentCellIndex (src, result) =
  let
    resultDisplay =
      case result of
        Ok def ->
          E.text <| "  " ++ LambdaParser.showDef def
        
        Err msg ->
          E.text <| msg
  in
  E.column
    [ E.spacing 15
    , E.width E.fill
    ]
    [ E.row
      [ E.width E.fill]
      [ E.text <| "> "
      , if activeCellIndex == currentCellIndex then
          Input.text
            [ E.width E.fill
            , Input.focusedOnLoad
            , E.htmlAttribute <|
              Html.Events.on "keydown" <|
              Json.Decode.map HandleKeyDown Keyboard.Event.decodeKeyboardEvent
            , E.htmlAttribute <| Html.Attributes.id <| "cell" ++ String.fromInt currentCellIndex
            ]
            { onChange =
              EditCell
            , text =
              src
            , placeholder =
              Nothing
            , label =
              Input.labelHidden "edit definition"
            }
        else
          E.el
          [ E.htmlAttribute <| Html.Attributes.id <| "cell" ++ String.fromInt currentCellIndex
          , E.padding 10
          , E.htmlAttribute <| Html.Attributes.style "line-height" "calc(1em + 24px)"
          , E.htmlAttribute <| Html.Attributes.style "height" "calc(1em + 24px)"
          , Border.width 1
          , Border.rounded 5
          , Border.color colors.lightGrey
          , E.width E.fill
          , Element.Events.onClick <| ActivateCell currentCellIndex
          ] <|
          E.text src
      ]
    , resultDisplay
    ]


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    EditCell newSrc ->
      editCell newSrc model

    ActivateCell index ->
      activateCell index model

    HandleKeyDown event ->
      handleKeyDown event model
      
    NoOp ->
      (model, Cmd.none)


activateCell : Int -> Model -> (Model, Cmd Msg)
activateCell index model =
  ( { model
      | activeCellIndex =
        index
    }
  , focusCell index
  )


handleKeyDown : KeyboardEvent -> Model -> (Model, Cmd Msg)
handleKeyDown { keyCode } model =
  case keyCode of
    Keyboard.Key.Enter ->
      addCell model
    
    Keyboard.Key.Backspace ->
      removeCell model
    
    _ ->
      (model, Cmd.none)


removeCell : Model -> (Model, Cmd Msg)
removeCell model =
  let
    (activeSrc, _) =
      getActiveCell model
  in
  if activeSrc == "" && Dict.size model.cells > 1 then
    let
      oldActiveCellIndex =
        model.activeCellIndex

      newActiveCellIndex =
        -- first cell
        if oldActiveCellIndex == 0 then
          oldActiveCellIndex
        else -- any cell after the first one
          oldActiveCellIndex - 1

      filterCell : Int -> Cell -> Dict Int Cell -> Dict Int Cell
      filterCell index cell cells =
        if index > oldActiveCellIndex then
          Dict.insert (index - 1) cell cells
        else if index == oldActiveCellIndex then
          cells
        else
          Dict.insert index cell cells
    in
    ( { model
        | cells =
          Dict.foldr
            filterCell
            Dict.empty
            model.cells
        , activeCellIndex =
          newActiveCellIndex
      }
    , focusCell newActiveCellIndex
    )
  else
    ( model
    , Cmd.none
    )


getActiveCell : Model -> Cell
getActiveCell model =
  Maybe.withDefault emptyCell <| -- impossible
  Dict.get model.activeCellIndex model.cells


addCell : Model -> (Model, Cmd Msg)
addCell model =
  let
    newActiveCellIndex =
      model.activeCellIndex + 1
  in
  ( { model
      | cells =
        Dict.foldl
          (\index cell cells ->
            if index > model.activeCellIndex then
              Dict.insert (index + 1) cell cells
            else
              Dict.insert index cell cells
          )
          (Dict.singleton newActiveCellIndex emptyCell)
          model.cells
      , activeCellIndex =
        newActiveCellIndex
    }
  , focusCell newActiveCellIndex
  )


focusCell : Int -> Cmd Msg
focusCell index =
  Task.attempt (\_ -> NoOp) <| Browser.Dom.focus <| "cell" ++ String.fromInt index


editCell : String -> Model -> (Model, Cmd Msg)
editCell newSrc model =
  ( { model
      | cells =
        Dict.update
          model.activeCellIndex
          (\_ ->
            let
              otherCells =
                Dict.foldl
                  (\index (_, result) others ->
                    if index /= model.activeCellIndex then
                      case result of
                        Ok def ->
                          def :: others
                        
                        Err _ ->
                          others
                    else
                      others
                  )
                  []
                  model.cells
            in
            Just (newSrc, evalDef model.evalStrategy otherCells newSrc)
          )
          model.cells
    }
  , Cmd.none
  )


evalDef : LambdaEvaluator.EvalStrategy -> List Def -> String -> Result String Def
evalDef strategy otherDefs src =
  case LambdaParser.parseDef src of
    Err problems ->
      Err <| LambdaParser.showProblems src problems
    
    Ok def ->
      case LambdaChecker.checkDefs <| def :: otherDefs of
        [] ->
          Ok <| LambdaEvaluator.evalDef strategy otherDefs def

        problems ->
          Err <| LambdaChecker.showProblems src problems
  

subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none