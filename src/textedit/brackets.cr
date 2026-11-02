# src/textedit/brackets.cr
module Textedit
  module Brackets
    PAIRS   = {"(" => ")", "[" => "]", "{" => "}", "\"" => "\"", "'" => "'"}
    CLOSING = {")", "]", "}", "\"", "'"}
    OPENERS = {"(" => ")", "[" => "]", "{" => "}"}
    CLOSERS = {")" => "(", "]" => "[", "}" => "{"}
    REACH   = 20_000
  end
end
