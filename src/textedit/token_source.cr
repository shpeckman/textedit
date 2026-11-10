# src/textedit/token_source.cr
module Textedit
  # Produces syntax tokens for one line of a buffer.
  module TokenSource
    # Shared empty token result; callers must not mutate it.
    NO_TOKENS = [] of Token

    # Returns tokens for *line* in *buffer*, with columns counted in clusters.
    abstract def tokens(buffer : Buffer, line : Int32) : Array(Token)
  end

  # Produces syntax tokens for standalone text without a document.
  module Tokenizer
    # Returns one token array per line in *text*.
    abstract def tokens(text : String) : Array(Array(Token))
  end
end
