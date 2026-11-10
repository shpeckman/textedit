# src/textedit/caret.cr
module Textedit
  # A directional selection from *anchor* to *head*, with an optional vertical-motion goal column.
  record Caret, anchor : Int32, head : Int32, goal : Int32? = nil do
    # Returns an empty caret at *offset*.
    def self.at(offset : Int32) : Caret
      new(offset, offset)
    end

    # Returns the lower offset of the selection.
    def start : Int32
      Math.min(@anchor, @head)
    end

    # Returns the exclusive upper offset of the selection.
    def stop : Int32
      Math.max(@anchor, @head)
    end

    # Returns the selection as an exclusive range, independent of its direction.
    def range : Range(Int32, Int32)
      start...stop
    end

    def empty? : Bool
      @anchor == @head
    end

    def backward? : Bool
      @head < @anchor
    end

    def includes?(offset : Int32) : Bool
      start <= offset < stop
    end

    # :nodoc:
    def clamp(limit : Int32) : Caret
      copy_with(anchor: @anchor.clamp(0, limit), head: @head.clamp(0, limit))
    end

    # :nodoc:
    def shift(delta : Int32) : Caret
      copy_with(anchor: @anchor + delta, head: @head + delta)
    end

    # :nodoc:
    def union(other : Caret) : Caret
      low  = Math.min(start, other.start)
      high = Math.max(stop, other.stop)
      backward? ? Caret.new(high, low) : Caret.new(low, high)
    end
  end
end
