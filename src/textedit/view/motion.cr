# src/textedit/view/motion.cr
module Textedit
  class View
    private def step(caret : Caret, delta : Int32, word : Bool, grow : Bool) : Int32
      if !caret.empty? && !grow && !word
        return delta < 0 ? caret.start : caret.stop
      end

      return (caret.head + delta).clamp(0, length) unless word

      word_edge(caret.head, delta)
    end

    private def word_edge(from : Int32, delta : Int32) : Int32
      index = from

      if delta < 0
        while index > 0 && kind_at(index - 1).try(&.space?)
          index -= 1
        end
        while index > 0 && kind_at(index - 1).try(&.word?)
          index -= 1
        end
      else
        total = length
        while index < total && kind_at(index).try(&.space?)
          index += 1
        end
        while index < total && kind_at(index).try(&.word?)
          index += 1
        end
      end

      index
    end

    private def subword_edge(from : Int32, delta : Int32) : Int32
      total = length

      if delta < 0
        index = from - 1
        return 0 if index <= 0

        while index > 0 && !subword_start?(index)
          index -= 1
        end
        index
      else
        index = from + 1
        return total if index >= total

        while index < total && !subword_start?(index)
          index += 1
        end
        index
      end
    end

    private def subword_start?(index : Int32) : Bool
      here = char_at(index) || return true
      back = char_at(index - 1) || return true
      return true if (kind_at(index).try(&.word?) || false) && !(kind_at(index - 1).try(&.word?) || false)
      return true if here != '_' && back == '_'

      here.uppercase? && !back.uppercase?
    end

    private def char_at(offset : Int32) : Char?
      return nil unless 0 <= offset < length

      found = @buffer.position(offset)
      row   = @buffer.line(found.line)
      found.column < row.size ? row.char(found.column) : '\n'
    end

    private def smart_start(head : Int32) : Int32
      row   = @layout.row_of(head)
      start = @layout.row_start(row)
      stop  = @layout.row_end(row)
      first = start
      while first < stop && kind_at(first).try(&.space?)
        first += 1
      end
      head == first ? start : first
    end

    private def move_vertically(rows : Int32, selecting : Bool) : Nil
      last = Math.max(@layout.row_count - 1, 0)
      list = @carets.map do |caret|
        cell = @layout.cell_of(caret.head)
        goal = caret.goal || cell.column
        head = @layout.offset_in((cell.row + rows).clamp(0, last), goal)
        Caret.new(selecting ? caret.anchor : head, head, goal)
      end
      seat(list, @primary)
      selected if selecting && !@dragging
    end

    private def vertical(offset : Int32, rows : Int32) : Int32
      cell = @layout.cell_of(offset)
      @layout.offset_in((cell.row + rows).clamp(0, Math.max(@layout.row_count - 1, 0)), cell.column)
    end

    private def page : Int32
      Math.max(@layout.page_rows, 1)
    end

    private def kind_at(offset : Int32) : ClusterKind?
      @buffer.kind(offset)
    end

    private def word_at(offset : Int32) : Range(Int32, Int32)?
      left  = offset
      right = offset
      total = length

      while left > 0 && kind_at(left - 1).try(&.word?)
        left -= 1
      end
      while right < total && kind_at(right).try(&.word?)
        right += 1
      end

      left < right ? left...right : nil
    end

    private def blocks : Array({Int32, Int32})
      spans = [] of {Int32, Int32}

      @carets.each do |caret|
        first = @buffer.position(caret.start).line
        stop  = @buffer.position(caret.stop)
        last  = stop.line
        last -= 1 if last > first && stop.column == 0 && !caret.empty?

        if (previous = spans.last?) && first <= previous[1] + 1
          spans[-1] = {previous[0], Math.max(previous[1], last)}
        else
          spans << {first, last}
        end
      end

      spans
    end
  end
end
