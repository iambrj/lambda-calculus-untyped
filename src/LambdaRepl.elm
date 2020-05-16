module LambdaRepl exposing (main)


import Browser
import Html exposing (Html)
import Html.Attributes
import Dict exposing (Dict)
import LambdaParser exposing (Def, Expr)
import LambdaChecker
import LambdaEvaluator exposing (EvalStrategy(..))
import Location exposing (Located)
import Element as E
import Element.Input as Input
import Element.Font as Font


type alias Model =
  { defs : Dict Int (String, Result String Def)
  , editingDefIndex : Int
  , evalStrategy : EvalStrategy
  }


type Msg
  = EditDef String


main : Program () Model Msg
main =
  Browser.sandbox
    { init = init
    , view = view
    , update = update
    }


init : Model
init =
  { defs =
    Dict.singleton 0 <| ("", Err "")
  , editingDefIndex =
    0
  , evalStrategy =
    CallByValue
  }


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
      viewDef model.editingDefIndex index result
    )
    (Dict.values model.defs)


viewDef : Int -> Int -> (String, Result String Def) -> E.Element Msg
viewDef editingDefIndex currentDefIndex (src, result) =
  let
    resultDisplay =
      case result of
        Ok def ->
          E.text <| "   " ++ LambdaParser.showDef def
        
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
      , if editingDefIndex == currentDefIndex then
          Input.text
            [ E.width E.fill
            , Input.focusedOnLoad
            ]
            { onChange =
              EditDef
            , text =
              src
            , placeholder =
              Nothing
            , label =
              Input.labelHidden "edit definition"
            }
        else
          E.text src
      ]
    , resultDisplay
    ]


update : Msg -> Model -> Model
update msg model =
  case msg of
    EditDef newSrc ->
      editDef newSrc model


editDef : String -> Model -> Model
editDef newSrc model =
  { model
    | defs =
      Dict.update
        model.editingDefIndex
        (\_ ->
          let
            otherDefs =
              Dict.foldl
                (\index (_, result) others ->
                  if index /= model.editingDefIndex then
                    case result of
                      Ok def ->
                        def :: others
                      
                      Err _ ->
                        others
                  else
                    others
                )
                []
                model.defs
          in
          Just (newSrc, evalDef model.evalStrategy otherDefs newSrc)
        )
        model.defs
  }


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
  