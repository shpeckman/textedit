# src/textedit/mark.cr
module Textedit
  # A grapheme-cluster offset that follows document edits according to its `Gravity`.
  #
  # Prefer `Document#mark`, which registers the mark for automatic updates.
  class Mark
    getter offset  : Int32
    getter gravity : Gravity

    # Creates a mark at *offset* with the given *gravity*.
    def initialize(@offset : Int32, @gravity : Gravity = Gravity::Left)
    end

    protected def follow(change : Change) : Nil
      from = change.from
      stop = from + change.removed_size

      @offset =
        if @offset < from
          @offset
        elsif @offset > stop || (@offset == stop && change.removed_size > 0)
          @offset + change.delta
        elsif @gravity.right?
          from + change.inserted_size
        else
          from
        end
    end
  end
end
