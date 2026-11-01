# src/textedit/token.cr
module Textedit
  record Token, start : Int32, count : Int32, kind : String do
    def stop : Int32
      @start + @count
    end
  end
end
