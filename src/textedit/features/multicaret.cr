# src/textedit/features/multicaret.cr
module Textedit
  # Commands that add, remove, or move between multiple carets.
  enum Carets
    Collapse
    AddNextOccurrence
    SkipOccurrence
    SelectAllOccurrences
    AddAbove
    AddBelow
    AddPerLine
    RemoveLast

    # Returns `false`; caret commands never change text.
    def edits? : Bool
      false
    end
  end

  # Manages multiple carets and selections by rows, lines, and occurrences.
  module Multicaret
    # Runs a caret command and returns whether it changed the carets.
    def run(command : Carets, selecting : Bool = false) : Bool
      return false unless enter(command)

      case command
      in .collapse?               then return collapse
      in .add_next_occurrence?    then return add_next_occurrence
      in .skip_occurrence?        then return skip_occurrence
      in .select_all_occurrences? then return select_all_occurrences
      in .add_above?              then add_beside(@carets.first.head, -1)
      in .add_below?              then add_beside(@carets.last.head, 1)
      in .add_per_line?           then return add_caret_per_line
      in .remove_last?            then return remove_last_caret
      end
      true
    end

    # Removes every caret except the primary caret.
    def collapse : Bool
      return false unless multiple?

      seat([primary_caret], 0)
      true
    end

    # Removes the primary caret and makes the preceding caret primary.
    def remove_last_caret : Bool
      return false unless multiple?

      list = @carets.dup
      list.delete_at(@primary)
      seat(list, Math.max(@primary - 1, 0))
      true
    end

    # Selects the word under an empty primary caret or adds its next occurrence.
    def add_next_occurrence : Bool
      lead = primary_caret

      if lead.empty?
        span = word_at(lead.head) || return false
        list = @carets.dup
        list[@primary] = Caret.new(span.begin, span.end)
        seat(list, @primary)
        return true
      end

      found = @buffer.find(@buffer.slice_text(lead.range), lead.stop) || return false
      return false if @carets.any? { |caret| caret.range == found }

      add_caret(found.end, found.begin)
      true
    end

    # Replaces the primary selection with its next occurrence.
    def skip_occurrence : Bool
      lead = primary_caret
      return false if lead.empty?

      found = @buffer.find(@buffer.slice_text(lead.range), lead.stop) || return false
      return false if @carets.any? { |caret| caret.range == found }

      list = @carets.reject { |caret| caret == lead } + [Caret.new(found.begin, found.end)]
      seat(list, list.size - 1)
      true
    end

    # Selects every occurrence of the primary selection or word under the caret.
    def select_all_occurrences : Bool
      lead = primary_caret.range

      if lead.empty?
        lead = word_at(lead.begin) || return false
      end

      found = @buffer.find_all(@buffer.slice_text(lead))
      return false if found.empty?

      seat(found.map { |range| Caret.new(range.begin, range.end) }, found.index(lead) || 0)
      true
    end

    # Places a caret at the end of every line touched by a multiline selection.
    def add_caret_per_line : Bool
      spread = [] of Caret

      @carets.each do |caret|
        first = @buffer.position(caret.start).line
        stop  = @buffer.position(caret.stop)
        last  = stop.line
        last -= 1 if last > first && stop.column == 0 && !caret.empty?

        if first == last
          spread << caret
        else
          (first..last).each { |line| spread << Caret.at(@buffer.line_end(line)) }
        end
      end

      return false if spread.size <= @carets.size

      seat(spread, spread.size - 1)
      true
    end

    private def add_beside(edge : Int32, rows : Int32) : Nil
      target = vertical(edge, rows)
      add_caret(target) unless @layout.row_of(target) == @layout.row_of(edge)
    end
  end
end
