module LambdaEvaluator exposing (evalDefs, evalDef, EvalStrategy(..))


import Dict exposing (Dict)
import LambdaParser exposing (Def, Expr(..))
import LambdaChecker exposing (sortDefs)
import Location exposing (withLocation, Located)
import Array
import List.Extra


type EvalStrategy
  = CallByName
  | CallByValue


evalDefs : EvalStrategy -> List Def -> List Def
evalDefs strategy defs =
  let
    sortedDefs =
      sortDefs defs
  in
  Tuple.first <|
  List.foldl
    (\def (resultDefs, ctx) ->
      let
        resultDef =
          internalEvalDef strategy ctx def
      in  
      ( resultDef :: resultDefs
      , Dict.insert def.name.value (exprToTerm ctx resultDef.expr) ctx
      )
    )
    ([], Dict.empty)
    sortedDefs


evalDef : EvalStrategy -> List Def -> Def -> Def
evalDef strategy otherDefs def =
  let
    resultCtx =
      List.foldl
        (\otherDef ctx ->
          Dict.insert otherDef.name.value (exprToTerm ctx otherDef.expr) ctx
        )
        Dict.empty
        otherDefs
  in
  internalEvalDef strategy resultCtx def


internalEvalDef : EvalStrategy -> Ctx -> Def -> Def
internalEvalDef strategy ctx def =
  { def
    | expr =
      evalExpr strategy ctx def.expr
  }


type Term
  = TmVariable Int
  | TmAbstraction (Located String) (Located Term)
  | TmApplication (Located Term) (Located Term)


type alias Ctx =
  Dict String (Located Term)


evalExpr : EvalStrategy -> Ctx -> Located Expr -> Located Expr
evalExpr strategy ctx expr =
  let
    _ = Debug.log "AL -> term" <| term
    term =
      exprToTerm ctx expr
  in
  termToExpr [] <|
  case strategy of
    CallByName ->
      evalTermCallByValue ctx term

    CallByValue ->
      evalTermCallByValue ctx term


termToExpr : List String -> Located Term -> Located Expr
termToExpr names t =
  withLocation t <|
  case t.value of
    TmVariable index ->
      EVariable <| withLocation t <| Maybe.withDefault "IMPOSSIBLE" <| List.Extra.getAt index names
    
    TmAbstraction boundVar t1 ->
      let
        newName =
          indexToName <| List.length names
        
        newNames =
          newName :: names
      in
      EAbstraction (withLocation boundVar newName) <| termToExpr newNames t1
  
    TmApplication t1 t2 ->
      EApplication (termToExpr names t1) (termToExpr names t2)


indexToName : Int -> String
indexToName n =
  let
    letters =
      Array.fromList [ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n"]
  in
  if 0 <= n && n < Array.length letters then
    Maybe.withDefault "IMPOSSIBLE" <| -- impossible
      Array.get n letters
  else
    let
      difference =
        n - Array.length letters
    in
    ( Maybe.withDefault "IMPOSSIBLE" <| -- impossible
      Array.get difference letters
    ) ++ String.fromInt difference


exprToTerm : Ctx -> Located Expr -> Located Term
exprToTerm ctx expr =
  withLocation expr <|
  case expr.value of
    EVariable name ->
      case Dict.get name.value ctx of
        Nothing -> -- impossible
          TmVariable -1
        
        Just s ->
          s.value

    EAbstraction boundVar e1 ->
      let
        newCtx =
          ctx |>
          Dict.map (\_ s -> termShift 1 0 s) |>
          Dict.insert boundVar.value (withLocation boundVar <| TmVariable 0)
      in
      TmAbstraction boundVar <| exprToTerm newCtx e1

    EApplication e1 e2 ->
      TmApplication
      (exprToTerm ctx e1)
      (exprToTerm ctx e2)


evalTermCallByValue : Ctx -> Located Term -> Located Term
evalTermCallByValue ctx t =
  case evalTermCallByValueHelper ctx t of
    Err _ ->
      t
    
    Ok t2 ->
      evalTermCallByValue ctx t2


evalTermCallByValueHelper : Ctx -> Located Term -> Result () (Located Term)
evalTermCallByValueHelper ctx t =
  let
    _ = Debug.log "AL -> t.value" <| t.value
  in
  case t.value of
    TmApplication t1 t2 ->
      let
        _ = Debug.log "AL -> t1" <| isValue t1
        _ = Debug.log "AL -> t2" <| isValue t2
      in
      if isValue t2 then
        case t1.value of
          TmAbstraction _ t12 ->
            Ok <| termShift -1 0 (termSubst 0 (termShift 1 0 t2) t12)
          
          _ ->
            let
              _ = Debug.log "AL -> t1" <| t1
            in
            evalTermCallByValueHelper ctx t1 |>
            Result.map
            (\newT1 ->
              withLocation t <| TmApplication newT1 t2
            )
      else if isValue t1 then
        evalTermCallByValueHelper ctx t2 |>
        Result.map
        (\newT2 ->
          withLocation t <| TmApplication t1 newT2
        )
      else
        evalTermCallByValueHelper ctx t1 |>
        Result.map
        (\newT1 ->
          withLocation t <| TmApplication newT1 t2
        )
    
    _ ->
      Err ()


isValue : Located Term -> Bool
isValue t =
  case t.value of
    TmAbstraction _ _ ->
      True
    
    _ ->
      False


termShift : Int -> Int -> Located Term -> Located Term
termShift d c t =
  withLocation t <|
  case t.value of
    TmVariable k ->
      if k < c then
        TmVariable k
      else
        TmVariable <| k + d
    
    TmAbstraction boundVar t1 ->
      TmAbstraction boundVar <| termShift d (c + 1) t1

    TmApplication t1 t2 ->
      TmApplication (termShift d c t1) (termShift d c t2)


termSubst : Int -> Located Term -> Located Term -> Located Term
termSubst j s t =
  withLocation t <|
  case t.value of
    TmVariable k ->
      if j == k then
        s.value
      else
        t.value
    
    TmAbstraction boundVar t1 ->
      TmAbstraction boundVar <| termSubst (j + 1) (termShift 1 0 s) t1

    TmApplication t1 t2 ->
      TmApplication
      (termSubst j s t1)
      (termSubst j s t2)
    