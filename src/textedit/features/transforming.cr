# src/textedit/features/transforming.cr
module Textedit
  enum Transform
    DuplicateSelection
    Sort
    Reverse
    Unique
    Join
    TrimTrailingWhitespace
    UpperCase
    LowerCase
    TitleCase

    def edits? : Bool
      true
    end
  end

  module Transforming
    def run(command : Transform, selecting : Bool = false) : Bool
      return false unless enter(command)

      case command
      in .duplicate_selection?      then duplicate_selection
      in .sort?                     then transform_lines(&.sort)
      in .reverse?                  then transform_lines(&.reverse)
      in .unique?                   then transform_lines(&.uniq)
      in .join?                     then join_lines
      in .trim_trailing_whitespace? then transform_lines { |rows| rows.map { |row| row.rstrip(" \t") } }
      in .upper_case?               then recase(&.upcase)
      in .lower_case?               then recase(&.downcase)
      in .title_case?               then recase { |text| titlecase(text) }
      end
    end

    def surround(opener : String) : Bool
      closer = Brackets::PAIRS[opener]? || return false

      @document.apply(self, Gesture::Other) do |caret, _index|
        next nil if caret.empty?

        Stroke.new(caret.range, opener + @buffer.slice_text(caret.range) + closer, 1, 1 + caret.range.size)
      end
    end

    def unsurround : Bool
      @document.apply(self, Gesture::Other) do |caret, _index|
        next nil if caret.range.size < 2

        opener = @buffer.cluster(caret.start) || next nil
        next nil unless Brackets::PAIRS[opener]? == @buffer.cluster(caret.stop - 1)

        inner = @buffer.slice_text((caret.start + 1)...(caret.stop - 1))
        Stroke.new(caret.range, inner, 0, caret.range.size - 2)
      end
    end

    private def duplicate_selection : Bool
      @document.apply(self, Gesture::Other) do |caret, _index|
        next nil if caret.empty?

        size = caret.range.size
        text = @buffer.slice_text(caret.range)
        if caret.head >= caret.anchor
          Stroke.new(caret.stop...caret.stop, text, 0, size)
        else
          Stroke.new(caret.stop...caret.stop, text, size, 0)
        end
      end
    end

    private def transform_lines(& : Array(String) -> Array(String)) : Bool
      edits = [] of Edit

      blocks.each do |(first, last)|
        rows  = (first..last).map { |line| @buffer.line(line).text }
        fresh = yield rows
        next if fresh == rows

        edits << Edit.new(@buffer.line_start(first)...@buffer.line_end(last), fresh.join(Buffer::BREAK))
      end

      return false if edits.empty?

      revise(edits)
    end

    private def join_lines : Bool
      edits = [] of Edit

      blocks.each do |(first, last)|
        stop = first == last ? Math.min(first + 1, @buffer.line_count - 1) : last
        next if stop == first

        rows   = (first..stop).map { |line| @buffer.line(line).text }
        joined = rows.first.rstrip(" \t")
        rows.skip(1).each do |row|
          piece = row.lstrip(" \t")
          next if piece.empty?

          joined = joined.empty? ? piece : "#{joined} #{piece}"
        end

        edits << Edit.new(@buffer.line_start(first)...@buffer.line_end(stop), joined)
      end

      return false if edits.empty?

      revise(edits)
    end

    private def recase(& : String -> String) : Bool
      @document.apply(self, Gesture::Other) do |caret, _index|
        next nil if caret.empty?

        text  = @buffer.slice_text(caret.range)
        fresh = yield text
        next nil if fresh == text

        Stroke.new(caret.range, fresh, 0, count(fresh))
      end
    end

    private def titlecase(text : String) : String
      String.build do |io|
        start = true
        text.each_char do |char|
          io << (start ? char.upcase : char.downcase)
          start = !(char.alphanumeric? || char == '_')
        end
      end
    end
  end
end
