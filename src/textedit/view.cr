# src/textedit/view.cr
module Textedit
  enum Motion
    Left
    Right
    WordLeft
    WordRight
    SubwordLeft
    SubwordRight
    RowStart
    SmartRowStart
    RowEnd
    Up
    Down
    PageUp
    PageDown
    DocumentStart
    DocumentEnd

    def edits? : Bool
      false
    end
  end

  class View
    getter document : Document
    getter buffer   : Buffer
    getter carets   : Array(Caret)
    getter primary  : Int32
    getter layout   : Layout

    property? dragging : Bool

    @graphemes : Graphemes

    def self.new(graphemes : Graphemes, text : String = "", **options)
      new(Document.new(graphemes, text, **defaults.merge(options)))
    end

    def self.defaults
      NamedTuple.new
    end

    def initialize(@document : Document, *, layout : Layout? = nil)
      @buffer    = @document.buffer
      @graphemes = @document.graphemes
      @carets    = [Caret.at(@buffer.size)]
      @primary   = 0
      @dragging  = false
      @layout    = layout || LineLayout.new(@buffer)
      @document.attach(self)
    end

    def layout=(value : Layout) : Layout
      @layout = value
    end

    def close : Nil
      @document.detach(self)
    end

    def value : String
      @document.value
    end

    def value=(value : String) : String
      @document.assign(value, self)
    end

    def clear : Nil
      self.value = ""
    end

    def length : Int32
      @buffer.size
    end

    def primary_caret : Caret
      @carets[@primary]
    end

    def cursor : Int32
      primary_caret.head
    end

    def selection? : Bool
      !primary_caret.empty?
    end

    def selection : Range(Int32, Int32)
      primary_caret.range
    end

    def selected_text : String
      @buffer.slice_text(selection)
    end

    def selected_texts : Array(String)
      @carets.reject(&.empty?).map { |caret| @buffer.slice_text(caret.range) }
    end

    def selected?(offset : Int32) : Bool
      index = @carets.bsearch_index { |caret| caret.stop > offset } || return false
      @carets.unsafe_fetch(index).includes?(offset)
    end

    def multiple? : Bool
      @carets.size > 1
    end

    def move(index : Int32, selecting : Bool = false) : Nil
      anchor = selecting ? primary_caret.anchor : index
      seat([Caret.new(anchor, index)], 0)
      selected if selecting && !@dragging
    end

    def move_carets(selecting : Bool, & : Caret -> Int32) : Nil
      list = @carets.map do |caret|
        head = yield caret
        selecting ? Caret.new(caret.anchor, head) : Caret.at(head)
      end
      seat(list, @primary)
      selected if selecting && !@dragging
    end

    def select_range(from : Int32, to : Int32) : Nil
      seat([Caret.new(from, to)], 0)
    end

    def place_carets(carets : Array(Caret), primary : Int32 = carets.size - 1) : Nil
      seat(carets, primary)
    end

    def add_caret(head : Int32, anchor : Int32 = head) : Nil
      list = @carets + [Caret.new(anchor, head)]
      seat(list, list.size - 1)
    end

    def replace_ranges(edits : Array(Edit), gesture : Gesture = Gesture::Other, after : Array(Caret)? = nil) : Bool
      @document.replace_ranges(edits, gesture, after, view: self)
    end

    def transaction(& : -> T) : T forall T
      @document.transaction(self) { yield }
    end

    def run(command : Motion, selecting : Bool = false) : Bool
      return false unless enter(command)

      case command
      in .left?            then move_carets(selecting) { |caret| step(caret, -1, false, selecting) }
      in .right?           then move_carets(selecting) { |caret| step(caret, 1, false, selecting) }
      in .word_left?       then move_carets(selecting) { |caret| step(caret, -1, true, selecting) }
      in .word_right?      then move_carets(selecting) { |caret| step(caret, 1, true, selecting) }
      in .subword_left?    then move_carets(selecting) { |caret| subword_edge(caret.head, -1) }
      in .subword_right?   then move_carets(selecting) { |caret| subword_edge(caret.head, 1) }
      in .row_start?       then move_carets(selecting) { |caret| @layout.row_start(@layout.row_of(caret.head)) }
      in .smart_row_start? then move_carets(selecting) { |caret| smart_start(caret.head) }
      in .row_end?         then move_carets(selecting) { |caret| @layout.row_end(@layout.row_of(caret.head)) }
      in .up?              then move_vertically(-1, selecting)
      in .down?            then move_vertically(1, selecting)
      in .page_up?         then move_vertically(-page, selecting)
      in .page_down?       then move_vertically(page, selecting)
      in .document_start?  then move_carets(selecting) { |_caret| 0 }
      in .document_end?    then move_carets(selecting) { |_caret| length }
      end
      true
    end

    protected def seat(list : Array(Caret), lead : Int32) : Nil
      list   = [Caret.at(length)] if list.empty?
      limit  = length
      leader = list[lead.clamp(0, list.size - 1)].clamp(limit)
      sorted = list.map(&.clamp(limit)).sort_by! { |caret| {caret.start, caret.stop} }
      merged = [] of Caret

      sorted.each do |caret|
        last = merged.last?
        if last && (caret.start < last.stop || caret.start == last.start)
          merged[-1] = last.union(caret)
        else
          merged << caret
        end
      end

      @carets  = merged
      @primary = merged.index { |caret| caret.start <= leader.head <= caret.stop } || merged.size - 1
      @document.stirred(self)
    end

    protected def follow(change : Change) : Nil
      @carets  = @carets.map { |caret| caret.copy_with(anchor: trail(caret.anchor, change), head: trail(caret.head, change), goal: nil) }
      @primary = @primary.clamp(0, @carets.size - 1)
    end

    private def enter(command) : Bool
      return false if command.edits? && !@document.admits?

      commanded(command)
      true
    end

    private def commanded(command) : Nil
    end

    private def typed(text : String) : Nil
    end

    private def pasted(ranges : Array(Range(Int32, Int32)), size : Int32, pieces : Array(String)?) : Nil
    end

    private def selected : Nil
    end

    private def pairing? : Bool
      false
    end

    private def put(prepared : String) : Bool
      return false if prepared.empty?

      gesture = count(prepared) == 1 && prepared != Buffer::BREAK ? Gesture::Typing : Gesture::Other
      @document.apply(self, gesture) { |caret, _index| Stroke.new(caret.range, prepared) }
    end

    private def revise(edits : Array(Edit), after : Array(Caret)? = nil) : Bool
      @document.replace_ranges(edits, Gesture::Other, after, view: self, origin: Origin::User)
    end

    private def trail(offset : Int32, change : Change) : Int32
      return offset if offset <= change.from

      stop = change.from + change.removed_size
      return change.from + change.inserted_size if offset <= stop

      offset + change.delta
    end

    private def count(text : String) : Int32
      text.empty? ? 0 : @graphemes.boundaries(text).size - 1
    end
  end
end
