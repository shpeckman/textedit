# src/textedit/filter.cr
module Textedit
  # Transforms incoming text before it enters a document.
  module Filter
    # Returns the accepted form of *text*.
    abstract def filter(text : String) : String
  end

  # Filter that replaces line breaks and tabs with spaces and removes other control characters.
  struct SingleLine
    include Filter

    def filter(text : String) : String
      return text unless text.each_char.any?(&.control?)

      String.build do |io|
        text.each_char do |char|
          if char == '\n' || char == '\t'
            io << ' '
          elsif !char.control?
            io << char
          end
        end
      end
    end
  end

  # Filter that preserves line breaks and replaces tabs with a configured string.
  struct MultiLine
    include Filter

    getter tab : String

    # Creates a multiline filter that replaces each tab with *tab*.
    def initialize(@tab : String = " ")
    end

    def filter(text : String) : String
      String.build do |io|
        text.each_char do |char|
          if char == '\n'
            io << char
          elsif char == '\t'
            io << @tab
          elsif !char.control?
            io << char
          end
        end
      end
    end
  end
end
