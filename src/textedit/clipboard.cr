# src/textedit/clipboard.cr
module Textedit
  # Clipboard interface supporting synchronous or deferred reads.
  module Clipboard
    # Writes *text* to the clipboard.
    abstract def write(text : String) : Nil

    # Reads the clipboard and yields its text, or `nil` when unavailable.
    #
    # The implementation may yield later, allowing terminal and GUI round trips.
    abstract def read(&block : String? -> Nil) : Nil
  end

  # Optional clipboard history used for paste cycling.
  module ClipboardHistory
    # Returns the number of retained entries, newest first.
    abstract def size : Int32

    # Yields the entry at *index*, or `nil` when it does not exist.
    abstract def read(index : Int32, &block : String? -> Nil) : Nil
  end

  # Bounded in-memory clipboard with unique entries ordered newest first.
  class Register
    include Clipboard
    include ClipboardHistory

    # Default maximum number of retained entries.
    LIMIT = 100

    getter text    : String
    getter entries : Array(String)

    @limit : Int32

    # Creates a register with optional initial *text* and a nonnegative history *limit*.
    def initialize(@text : String = "", limit : Int32 = LIMIT)
      @entries = @text.empty? ? [] of String : [@text]
      @limit   = Math.max(limit, 0)
    end

    # Returns the number of retained entries.
    def size : Int32
      @entries.size
    end

    # Stores *text* as the current clipboard value and newest history entry.
    def write(text : String) : Nil
      @text = text
      @entries.delete(text)
      @entries.unshift(text)
      while @entries.size > @limit
        @entries.pop
      end
    end

    # Yields the newest entry immediately.
    def read(&block : String? -> Nil) : Nil
      read(0, &block)
    end

    # Yields the entry at *index* immediately, or `nil` when absent.
    def read(index : Int32, &block : String? -> Nil) : Nil
      block.call(@entries[index]?)
    end
  end
end
