# src/textedit/wrap_layout.cr
module Textedit
  # Layout that wraps each line onto as many display rows as `#width`
  # needs, breaking after the last whitespace cluster that fits and inside
  # a word only when a row has none.
  #
  # The rows follow edits, width changes and the view's folds without
  # further calls. The end of a row that continues on the next one is the
  # offset before its last cluster, so `Motion::RowEnd` stays on the row.
  class WrapLayout
    include Layout

    getter width : Int32
    property page_rows : Int32
    property folds : Folds?

    # Creates a layout over *buffer* that wraps at *width* display columns
    # (at least 1) and pages by *page_rows*.
    def initialize(@buffer : Buffer, width : Int32, *, @page_rows : Int32 = 1, @folds : Folds? = nil)
      @width = Math.max(width, 1)
      # Line of each row, and the cluster column it starts at in that line.
      @lines = [] of Int32
      @starts = [] of Int32
      # Buffer revision, width, folds revision and folds identity the rows
      # were counted for.
      @counted = {-1, 0, 0, 0_u64}
    end

    # Sets the display width rows wrap at, at least 1.
    def width=(value : Int32) : Int32
      @width = Math.max(value, 1)
    end

    def row_count : Int32
      count
      @lines.size
    end

    def row_of(offset : Int32) : Int32
      count
      found = @buffer.position(offset.clamp(0, @buffer.size))
      first = @lines.bsearch_index { |line| line >= found.line }
      return Math.max((first || @lines.size) - 1, 0) unless first && @lines[first] == found.line

      row = first
      while continued?(row) && @starts[row + 1] <= found.column
        row += 1
      end
      row
    end

    def row_start(row : Int32) : Int32
      row = clamp(row)
      @buffer.line_start(@lines[row]) + @starts[row]
    end

    def row_end(row : Int32) : Int32
      row = clamp(row)
      line = @lines[row]
      continued?(row) ? @buffer.line_start(line) + @starts[row + 1] - 1 : @buffer.line_end(line)
    end

    def cell_of(offset : Int32) : Cell
      row = row_of(offset)
      found = @buffer.position(offset.clamp(0, @buffer.size))
      line = @lines[row]
      Cell.new(found.line == line ? @buffer.width(line, @starts[row], found.column) : 0, row)
    end

    def offset_in(row : Int32, column : Int32) : Int32
      row = clamp(row)
      line = @lines[row]
      stop = continued?(row) ? @starts[row + 1] - 1 : Int32::MAX
      @buffer.line_start(line) + @buffer.index(line, column, @starts[row], stop)
    end

    private def clamp(row : Int32) : Int32
      count
      row.clamp(0, @lines.size - 1)
    end

    # Whether the next row continues the line of *row*.
    private def continued?(row : Int32) : Bool
      row + 1 < @lines.size && @lines[row + 1] == @lines[row]
    end

    # Recounts the rows when the buffer, the width or the folds changed.
    private def count : Nil
      folds = @folds
      counted = {@buffer.revision, @width, folds.try(&.revision) || 0, folds.object_id}
      return if counted == @counted

      @counted = counted
      @lines.clear
      @starts.clear
      if folds && !folds.empty?
        folds.rows.each { |line| wrap(line) }
      else
        @buffer.line_count.times { |line| wrap(line) }
      end
    end

    # Appends the rows of *line*.
    private def wrap(line : Int32) : Nil
      graphemes = @buffer.graphemes
      @lines << line
      @starts << 0
      start = 0
      used = 0
      gap = -1
      @buffer.line(line).each_cluster do |bytes, column|
        extent = graphemes.width(bytes)
        while used + extent > @width && column > start
          start = gap > start ? gap : column
          @lines << line
          @starts << start
          used = @buffer.width(line, start, column)
          gap = -1
        end
        used += extent
        gap = column + 1 if graphemes.kind(bytes).space?
      end
    end
  end
end
