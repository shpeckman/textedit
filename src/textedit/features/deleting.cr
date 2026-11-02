# src/textedit/features/deleting.cr
module Textedit
  enum Deletion
    Backward
    Forward
    WordBackward
    WordForward
    SubwordBackward
    SubwordForward
    ToRowStart
    ToRowEnd

    def edits? : Bool
      true
    end
  end

  module Deleting
    def run(command : Deletion, selecting : Bool = false) : Bool
      return false unless enter(command)

      case command
      in .backward?         then delete_backward
      in .forward?          then delete_forward
      in .word_backward?    then delete_toward(-1) { |head| word_edge(head, -1) }
      in .word_forward?     then delete_toward(1) { |head| word_edge(head, 1) }
      in .subword_backward? then delete_toward(-1) { |head| subword_edge(head, -1) }
      in .subword_forward?  then delete_toward(1) { |head| subword_edge(head, 1) }
      in .to_row_start?     then delete_toward(-1) { |head| @layout.row_start(@layout.row_of(head)) }
      in .to_row_end?       then delete_toward(1) { |head| @layout.row_end(@layout.row_of(head)) }
      end
      true
    end

    private def delete_backward : Nil
      @document.apply(self, Gesture::Deleting) do |caret, _index|
        head = caret.head
        if !caret.empty?
          Stroke.new(caret.range, "")
        elsif head > 0
          before = @buffer.cluster(head - 1)
          paired = pairing? && before && Brackets::PAIRS[before]? == @buffer.cluster(head)
          Stroke.new((head - 1)...(paired ? head + 1 : head), "")
        end
      end
    end

    private def delete_forward : Nil
      @document.apply(self, Gesture::Deleting) do |caret, _index|
        if !caret.empty?
          Stroke.new(caret.range, "")
        elsif caret.head < length
          Stroke.new(caret.head...(caret.head + 1), "")
        end
      end
    end

    private def delete_toward(direction : Int32, & : Int32 -> Int32) : Nil
      @document.apply(self, Gesture::Deleting) do |caret, _index|
        if !caret.empty?
          Stroke.new(caret.range, "")
        else
          edge = yield caret.head
          edge == caret.head ? nil : Stroke.new(Math.min(edge, caret.head)...Math.max(edge, caret.head), "")
        end
      end
    end
  end
end
