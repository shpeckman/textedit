# src/textedit/features/selecting.cr
module Textedit
  # Commands that expand selections to text objects.
  enum Selection
    All
    Word
    Line
    InsideBrackets
    AroundBrackets
    InsideQuotes
    AroundQuotes

    # Returns `false`; selection commands never change text.
    def edits? : Bool
      false
    end
  end

  # Selects documents, words, lines, brackets, and quoted text.
  module Selecting
    # Runs a selection command and returns whether it found its target.
    def run(command : Selection, selecting : Bool = false) : Bool
      return false unless enter(command)

      case command
      in .all?             then select_all
      in .word?            then select_word
      in .line?            then select_line
      in .inside_brackets? then return select_objects { |caret| bracket_object(caret, false) }
      in .around_brackets? then return select_objects { |caret| bracket_object(caret, true) }
      in .inside_quotes?   then return select_objects { |caret| quote_object(caret, false) }
      in .around_quotes?   then return select_objects { |caret| quote_object(caret, true) }
      end
      true
    end

    # Selects the entire document.
    def select_all : Nil
      select_range(0, length)
      selected
    end

    # Selects the word under every caret that has one.
    def select_word : Nil
      list = @carets.map do |caret|
        span = word_at(caret.head)
        span ? Caret.new(span.begin, span.end) : caret
      end
      seat(list, @primary)
      selected
    end

    # Selects every line touched by a caret or selection.
    def select_line : Nil
      list = @carets.map do |caret|
        first = @buffer.position(caret.start).line
        stop  = @buffer.position(caret.stop)
        last  = stop.line
        last -= 1 if last > first && stop.column == 0 && !caret.empty?
        tail  = last + 1 < @buffer.line_count ? @buffer.line_start(last + 1) : @buffer.line_end(last)
        Caret.new(@buffer.line_start(first), tail)
      end
      seat(list, @primary)
      selected
    end

    # Returns offsets of the bracket pair beside the empty primary caret.
    def brackets : {Int32, Int32}?
      lead = primary_caret
      return nil unless lead.empty?

      {lead.head - 1, lead.head}.each do |offset|
        cluster = @buffer.cluster(offset) || next
        if closer = Brackets::OPENERS[cluster]?
          found = scan(offset, 1, cluster, closer)
          return {offset, found} if found
        elsif opener = Brackets::CLOSERS[cluster]?
          found = scan(offset, -1, cluster, opener)
          return {found, offset} if found
        end
      end
      nil
    end

    private def select_objects(& : Caret -> Range(Int32, Int32)?) : Bool
      list = @carets.map do |caret|
        found = yield caret
        found ? Caret.new(found.begin, found.end) : caret
      end
      return false if list == @carets

      seat(list, @primary)
      selected
      true
    end

    private def bracket_object(caret : Caret, around : Bool) : Range(Int32, Int32)?
      best = nil.as({Int32, Int32}?)

      Brackets::OPENERS.each do |opener, closer|
        opening_before(caret, opener, closer).each do |start|
          stop = scan(start, 1, opener, closer) || next
          next unless stop >= caret.stop
          best = {start, stop} if best.nil? || start > best[0]
          break
        end
      end

      best.try do |(start, stop)|
        around ? start...(stop + 1) : (start + 1)...stop
      end
    end

    private def opening_before(caret : Caret, opener : String, closer : String) : Array(Int32)
      direct = caret.empty? ? [caret.head, caret.start, caret.start - 1] : [caret.start, caret.start - 1]
      direct.each do |offset|
        return [offset] if @buffer.cluster(offset) == opener
      end

      depth  = 0
      offset = caret.start - 1
      limit  = Brackets::REACH
      while offset >= 0 && limit > 0
        cluster = @buffer.cluster(offset)
        if cluster == closer
          depth += 1
        elsif cluster == opener
          return [offset] if depth == 0
          depth -= 1
        end
        offset -= 1
        limit -= 1
      end
      [] of Int32
    end

    private def quote_object(caret : Caret, around : Bool) : Range(Int32, Int32)?
      first = @buffer.position(caret.start)
      last  = @buffer.position(caret.stop)
      return nil unless first.line == last.line

      start = @buffer.line_start(first.line)
      stop  = @buffer.line_end(first.line)
      {'"', '\''}.each do |quote|
        marks  = [] of Int32
        offset = start
        while offset < stop
          marks << offset if @buffer.cluster(offset) == quote.to_s && !escaped?(offset, start)
          offset += 1
        end
        marks.each_slice(2) do |pair|
          next unless pair.size == 2
          opening, closing = pair
          next unless opening <= caret.start && closing >= caret.stop
          return around ? opening...(closing + 1) : (opening + 1)...closing
        end
      end
      nil
    end

    private def escaped?(offset : Int32, floor : Int32) : Bool
      count  = 0
      offset -= 1
      while offset >= floor && @buffer.cluster(offset) == "\\"
        count += 1
        offset -= 1
      end
      count.odd?
    end

    private def scan(from : Int32, step : Int32, own : String, other : String) : Int32?
      depth  = 0
      offset = from
      limit  = Brackets::REACH

      while limit > 0
        offset += step
        cluster = @buffer.cluster(offset) || return
        if cluster == own
          depth += 1
        elsif cluster == other
          return offset if depth == 0
          depth -= 1
        end
        limit -= 1
      end
      nil
    end
  end
end
