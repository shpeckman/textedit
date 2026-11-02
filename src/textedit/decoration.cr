# src/textedit/decoration.cr
module Textedit
  class Decoration
    getter kind    : String
    getter message : String
    getter source  : String

    def initialize(range : Range(Int32, Int32), @kind : String, @message : String = "", @source : String = "")
      @start = Mark.new(range.begin, Gravity::Right)
      @stop  = Mark.new(Math.max(range.end, range.begin), Gravity::Left)
    end

    def start : Int32
      @start.offset
    end

    def stop : Int32
      Math.max(@stop.offset, @start.offset)
    end

    def range : Range(Int32, Int32)
      start...stop
    end

    def covers?(offset : Int32) : Bool
      start <= offset < stop || (start == stop && offset == start)
    end

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

  class Decorations
    include Follower

    getter document : Document
    getter entries  : Array(Decoration)

    @listeners : Array(Proc(Nil))
    @untrack   : Proc(Nil)

    def initialize(@document : Document)
      @entries   = [] of Decoration
      @listeners = [] of Proc(Nil)
      @untrack   = -> { nil }
      @untrack   = @document.track(self)
    end

    def replace(source : String, entries : Array(Decoration)) : Nil
      @entries.reject!(&.source.==(source))
      entries.each do |entry|
        entry.source = source
        @entries << entry
      end
      @entries.sort_by!(&.start)
      @listeners.dup.each(&.call)
    end

    def between(from : Int32, to : Int32) : Array(Decoration)
      @entries.select(&.overlaps?(from, to))
    end

    def at(offset : Int32) : Array(Decoration)
      @entries.select(&.covers?(offset))
    end

    def listen(&block : -> Nil) : Proc(Nil)
      @listeners << block
      -> { @listeners.delete(block); nil }
    end

    def close : Nil
      @untrack.call
    end

    def follow(change : Change) : Nil
      @entries.each(&.follow(change))
    end
  end
end
