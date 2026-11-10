# src/textedit/features/typing.cr
module Textedit
  # Inserts and pastes text at every caret, with optional automatic bracket pairing.
  module Typing
    property? auto_close : Bool = false

    # Inserts filtered *text* at every caret and returns whether text changed.
    #
    # Automatic pairing applies only to single opening or closing characters.
    def insert(text : String) : Bool
      typed(text)
      prepared = @document.prepare(text)
      if @auto_close && (Brackets::PAIRS.has_key?(prepared) || Brackets::CLOSING.includes?(prepared))
        return pair(prepared)
      end

      put(prepared)
    end

    # Pastes *text* without automatic pairing.
    #
    # With multiple carets and a matching number of lines, pastes one line per caret.
    def paste(text : String) : Bool
      normal = LineEnding.normalize(text)
      parts  = normal.chomp.split('\n')
      ranges = @carets.map(&.range)
      size   = @buffer.size

      if multiple? && parts.size == @carets.size
        pieces  = parts.map { |part| @document.filter.filter(part) }
        applied = @document.apply(self, Gesture::Other) { |caret, index| Stroke.new(caret.range, pieces[index]) }
      else
        prepared = @document.filter.filter(normal)
        pieces   = Array.new(@carets.size, prepared)
        applied  = put(prepared)
      end
      pasted(ranges, size, applied ? pieces : nil)
      applied
    end

    private def pairing? : Bool
      @auto_close
    end

    private def pair(char : String) : Bool
      closer = Brackets::PAIRS[char]?

      @document.apply(self, Gesture::Typing) do |caret, _index|
        if caret.empty? && Brackets::CLOSING.includes?(char) && @buffer.cluster(caret.head) == char
          Stroke.new(caret.head...(caret.head + 1), char)
        elsif closer.nil?
          Stroke.new(caret.range, char)
        elsif !caret.empty?
          Stroke.new(caret.range, char + @buffer.slice_text(caret.range) + closer, 1, 1 + caret.range.size)
        elsif closer == char && kind_at(caret.head - 1).try(&.word?)
          Stroke.new(caret.range, char)
        else
          Stroke.new(caret.range, char + closer, 1, 1)
        end
      end
    end
  end
end
