# src/textedit/recollection.cr
module Textedit
  # Bounded single-line input history that remembers the current draft while browsing.
  class Recollection
    # Default maximum number of retained entries.
    LIMIT = 100

    getter entries : Array(String)
    getter limit   : Int32

    @index : Int32
    @draft : String

    # Creates a history from *entries*, with *limit* clamped to at least one.
    def initialize(entries : Array(String) = [] of String, @limit : Int32 = LIMIT)
      @limit   = Math.max(@limit, 1)
      @entries = entries.last(@limit)
      @index   = @entries.size
      @draft   = ""
    end

    # Changes the retention limit, trims older entries, and ends browsing.
    def limit=(value : Int32) : Int32
      @limit = Math.max(value, 1)
      @entries.shift(@entries.size - @limit) if @entries.size > @limit
      reset
      @limit
    end

    # Adds a nonblank entry, moves duplicates to the newest position, and ends browsing.
    def push(entry : String) : Nil
      unless entry.strip.empty?
        @entries.delete(entry)
        @entries << entry
        @entries.shift if @entries.size > @limit
      end
      reset
    end

    # Returns the previous entry and saves *current* as the draft when browsing starts.
    def back(current : String) : String?
      return nil if @index == 0

      @draft = current if @index == @entries.size
      @index -= 1
      @entries[@index]
    end

    # Returns the next entry, the saved draft after the newest entry, or `nil`.
    def forward : String?
      return nil if @index >= @entries.size

      @index += 1
      @index == @entries.size ? @draft : @entries[@index]
    end

    def browsing? : Bool
      @index < @entries.size
    end

    # Ends browsing and discards the saved draft.
    def reset : Nil
      @index = @entries.size
      @draft = ""
    end
  end
end
