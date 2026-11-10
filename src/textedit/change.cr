# src/textedit/change.cr
module Textedit
  # One reversible buffer replacement, with offsets and sizes counted in grapheme clusters.
  #
  # Point conversion methods expect the buffer state immediately after the change,
  # as provided during `Listener#applied`.
  record Change, from : Int32, removed : String, inserted : String, removed_size : Int32, inserted_size : Int32 do
    # Returns the number of line breaks removed by the change.
    def removed_lines : Int32
      @removed.count('\n')
    end

    # Returns the number of line breaks inserted by the change.
    def inserted_lines : Int32
      @inserted.count('\n')
    end

    # Returns the change in grapheme-cluster count.
    def delta : Int32
      @inserted_size - @removed_size
    end

    # Returns the start position in *unit* against the post-change *buffer*.
    def start_point(buffer : Buffer, unit : Units) : Point
      buffer.point(@from, unit)
    end

    # Returns the end of the removed text in *unit*.
    def old_end_point(buffer : Buffer, unit : Units) : Point
      advance(buffer, start_point(buffer, unit), @removed, unit)
    end

    # Returns the end of the inserted text in *unit*.
    def new_end_point(buffer : Buffer, unit : Units) : Point
      advance(buffer, start_point(buffer, unit), @inserted, unit)
    end

    # :nodoc:
    def undo(buffer : Buffer) : Change
      buffer.replace(@from...(@from + @inserted_size), @removed)
    end

    # :nodoc:
    def redo(buffer : Buffer) : Change
      buffer.replace(@from...(@from + @removed_size), @inserted)
    end

    private def advance(buffer : Buffer, start : Point, text : String, unit : Units) : Point
      last = text.to_slice.rindex(0x0A_u8) || return Point.new(start.line, start.column + buffer.measure(text, unit))

      tail = text.byte_slice(last + 1, text.bytesize - last - 1)
      Point.new(start.line + text.count('\n'), buffer.measure(tail, unit))
    end
  end
end
