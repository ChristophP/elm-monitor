module OutputParser exposing (parse)

import Char
import Html exposing (Html)
import Json.Encode as JE
import Parser exposing (..)
import Set


parse : String -> Result (List DeadEnd) JE.Value
parse =
    Parser.run parser



-- STRING


string : Parser JE.Value
string =
    succeed JE.string
        |. symbol "\""
        |= (getChompedString <| chompWhile ((/=) '"'))
        |. symbol "\""



-- BOOL


bool : Parser JE.Value
bool =
    oneOf
        [ keyword "True" |> map (\_ -> JE.bool True)
        , keyword "False" |> map (\_ -> JE.bool False)
        ]



-- NUMBER


float : Parser JE.Value
float =
    number
        { int = Just toFloat
        , hex = Nothing
        , octal = Nothing
        , binary = Nothing
        , float = Just identity
        }
        |> map JE.float



-- UNIT


unit : Parser JE.Value
unit =
    symbol "()" |> map (\_ -> JE.null)



-- LIST


list : Parser JE.Value
list =
    sequence
        { start = "["
        , separator = ","
        , end = "]"
        , spaces = spaces
        , item = value
        , trailing = Forbidden
        }
        |> map (JE.list identity)



-- OBJECT


key : Parser String
key =
    variable
        { start = Char.isLower
        , inner = \c -> Char.isAlphaNum c || c == '_'
        , reserved = Set.empty
        }


keyValue : Parser ( String, JE.Value )
keyValue =
    succeed Tuple.pair
        |= key
        |. spaces
        |. symbol "="
        |. spaces
        |= value


record : Parser JE.Value
record =
    sequence
        { start = "{"
        , separator = ","
        , end = "}"
        , spaces = spaces
        , item = keyValue
        , trailing = Forbidden
        }
        |> map JE.object



-- INTERNALS


internals : Parser JE.Value
internals =
    map JE.string <|
        getChompedString <|
            succeed ()
                |. symbol "<"
                |. chompWhile ((/=) '>')
                |. symbol ">"



-- TUPLES


tuple : Parser JE.Value
tuple =
    sequence
        { start = "("
        , separator = ","
        , end = ")"
        , spaces = spaces
        , item = value
        , trailing = Forbidden
        }
        |> map (JE.list identity)



-- UNION


ctor : Parser JE.Value
ctor =
    map (JE.string << formatCtor) <|
        variable
            { start = Char.isUpper
            , inner = \c -> Char.isAlphaNum c || c == '_'
            , reserved = Set.empty
            }


formatCtor : String -> String
formatCtor str =
    "⟨" ++ str ++ "⟩"


ctorArgsHelp : List JE.Value -> Parser (Step (List JE.Value) (List JE.Value))
ctorArgsHelp state =
    succeed identity
        |. spaces
        |= oneOf
            [ succeed
                (\call -> Loop (call :: state))
                |. symbol "("
                |= lazy (\_ -> union)
                |. symbol ")"
            , succeed
                (\call -> Loop (call :: state))
                |= value
            , succeed (Done (List.reverse state))
            ]


type NonEmptyList a
    = NonEmptyList a (List a)


{-| turn ctor only to String, ctor with args to array
-}
nonEmptyListToValue : NonEmptyList JE.Value -> JE.Value
nonEmptyListToValue nonEmptyList =
    case nonEmptyList of
        NonEmptyList head [] ->
            head

        NonEmptyList head tail ->
            JE.list identity (head :: tail)


ctorWithArgs : Parser (NonEmptyList JE.Value)
ctorWithArgs =
    succeed NonEmptyList
        |= ctor
        |= loop [] ctorArgsHelp


union : Parser JE.Value
union =
    map nonEmptyListToValue ctorWithArgs



-- VALUE


value : Parser JE.Value
value =
    oneOf
        [ bool
        , float
        , unit
        , string
        , internals
        , lazy (\() -> union)
        , lazy (\() -> tuple)
        , lazy (\() -> record)
        , lazy (\() -> list)
        ]



-- FINAL PARSER


parser : Parser JE.Value
parser =
    succeed identity
        |. spaces
        |= value
        |. spaces
