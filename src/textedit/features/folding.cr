# src/textedit/features/folding.cr
module Textedit
  module Folding
    @folds : ::Textedit::Folds? = nil

    def folds : Folds
      found = @folds
      return found if found

      made    = Folds.new(@document)
      @folds  = made
      @layout.folds = made
      made
    end

    def folds? : Folds?
      @folds
    end

    def layout=(value : Layout) : Layout
      @folds.try { |found| value.folds = found }
      super
    end

    def lift_carets : Bool
      found = @folds || return false
      moved = false
      list  = @carets.map do |caret|
        line = @buffer.position(caret.head).line
        next caret unless found.hidden?(line)

        moved = true
        while line > 0 && found.hidden?(line)
          line -= 1
        end
        Caret.at(@buffer.line_end(line))
      end
      place_carets(list, @primary) if moved
      moved
    end
  end
end
