# src/textedit/token.cr
module Textedit
  # A host-produced syntax token whose start and length count grapheme clusters.
  record Token, start : Int32, count : Int32, kind : String do
    # Returns the exclusive end column of the token.
    def stop : Int32
      @start + @count
    end
  end
end
