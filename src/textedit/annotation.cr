# src/textedit/annotation.cr
module Textedit
  enum Placement
    Before
    After
    RowEnd
  end

  class Annotation
    getter text      : String
    getter kind      : String
    getter placement : Placement
    getter source    : String

    def initialize(offset : Int32, @text : String, @placement : Placement = Placement::After,
                   @kind : String = "", @source : String = "")
      @mark = Mark.new(offset, @placement.before? ? Gravity::Right : Gravity::Left)
    end

    def offset : Int32
      @mark.offset
    end

    def before? : Bool
      @placement.before?
    end

    def after? : Bool
      @placement.after?
    end

    def row_end? : Bool
      @placement.row_end?
    end

    protected def source=(value : String) : String
      @source = value
    end

    protected def follow(change : Change) : Nil
      @mark.follow(change)
    end
  end

  class Annotations
    include Follower

    getter document : Document
    getter entries  : Array(Annotation)

    @listeners : Array(Proc(Nil))
    @untrack   : Proc(Nil)

    def initialize(@document : Document)
      @entries   = [] of Annotation
      @listeners = [] of Proc(Nil)
      @untrack   = -> { nil }
      @untrack   = @document.track(self)
    end

    def replace(source : String, entries : Array(Annotation)) : Nil
      @entries.reject!(&.source.==(source))
      entries.each do |entry|
        entry.source = source
        @entries << entry
      end
      @entries.sort_by!(&.offset)
      @listeners.dup.each(&.call)
    end

    def between(from : Int32, to : Int32) : Array(Annotation)
      @entries.select { |entry| from <= entry.offset <= to }
    end

    def at(offset : Int32) : Array(Annotation)
      @entries.select(&.offset.==(offset))
    end

    def on(line : Int32) : Array(Annotation)
      buffer = @document.buffer
      return [] of Annotation unless 0 <= line < buffer.line_count

      between(buffer.line_start(line), buffer.line_end(line))
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
