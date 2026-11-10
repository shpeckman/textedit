# src/textedit/decoration.cr
module Textedit
  # A source-owned text range with a kind and optional message that follows edits.
  class Decoration
    getter kind    : String
    getter message : String
    getter source  : String

    # Creates a decoration over an exclusive grapheme-cluster *range*.
    def initialize(range : Range(Int32, Int32), @kind : String, @message : String = "", @source : String = "")
      @start = Mark.new(range.begin, Gravity::Right)
      @stop  = Mark.new(Math.max(range.end, range.begin), Gravity::Left)
    end

    # Returns the current inclusive start offset.
    def start : Int32
      @start.offset
    end

    # Returns the current exclusive stop offset.
    def stop : Int32
      Math.max(@stop.offset, @start.offset)
    end

    # Returns the current exclusive range.
    def range : Range(Int32, Int32)
      start...stop
    end

    # Returns whether *offset* lies in the range, including an empty range's position.
    def covers?(offset : Int32) : Bool
      start <= offset < stop || (start == stop && offset == start)
    end

    # Returns whether the decoration overlaps an offset interval.
    def overlaps?(from : Int32, to : Int32) : Bool
      start < to && from < stop || (start == stop && from <= start <= to)
    end

    protected def source=(value : String) : String
      @source = value
    end

    protected def follow(change : Change) : Nil
      @start.follow(change)
      @stop.follow(change)
    end
  end

  # Document-following decoration store whose entries are replaced independently per source.
  class Decorations
    include Follower

    getter document : Document
    getter entries  : Array(Decoration)

    @listeners : Array(Proc(Nil))
    @untrack   : Proc(Nil)

    # Creates an empty store and starts following *document*.
    def initialize(@document : Document)
      @entries   = [] of Decoration
      @listeners = [] of Proc(Nil)
      @untrack   = -> { nil }
      @untrack   = @document.track(self)
    end

    # Replaces every entry from *source* and notifies listeners.
    def replace(source : String, entries : Array(Decoration)) : Nil
      @entries.reject!(&.source.==(source))
      entries.each do |entry|
        entry.source = source
        @entries << entry
      end
      @entries.sort_by!(&.start)
      @listeners.dup.each(&.call)
    end

    # Returns decorations overlapping the interval between *from* and *to*.
    def between(from : Int32, to : Int32) : Array(Decoration)
      @entries.select(&.overlaps?(from, to))
    end

    # Returns decorations covering *offset*.
    def at(offset : Int32) : Array(Decoration)
      @entries.select(&.covers?(offset))
    end

    # Calls the block after each source replacement and returns a proc that removes it.
    def listen(&block : -> Nil) : Proc(Nil)
      @listeners << block
      -> { @listeners.delete(block); nil }
    end

    # Stops following the document.
    def close : Nil
      @untrack.call
    end

    def follow(change : Change) : Nil
      @entries.each(&.follow(change))
    end
  end
end
