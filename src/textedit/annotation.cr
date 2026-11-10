# src/textedit/annotation.cr
module Textedit
  # Display position of an annotation relative to its document offset or row.
  enum Placement
    Before
    After
    RowEnd
  end

  # Source-owned text displayed beside a document offset without changing the text.
  class Annotation
    getter text      : String
    getter kind      : String
    getter placement : Placement
    getter source    : String

    # Creates an annotation at a grapheme-cluster *offset*.
    def initialize(offset : Int32, @text : String, @placement : Placement = Placement::After,
                   @kind : String = "", @source : String = "")
      @mark = Mark.new(offset, @placement.before? ? Gravity::Right : Gravity::Left)
    end

    # Returns the current offset after document edits.
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

  # Document-following annotation store whose entries are replaced independently per source.
  class Annotations
    include Follower

    getter document : Document
    getter entries  : Array(Annotation)

    @listeners : Array(Proc(Nil))
    @untrack   : Proc(Nil)

    # Creates an empty store and starts following *document*.
    def initialize(@document : Document)
      @entries   = [] of Annotation
      @listeners = [] of Proc(Nil)
      @untrack   = -> { nil }
      @untrack   = @document.track(self)
    end

    # Replaces every entry from *source* and notifies listeners.
    def replace(source : String, entries : Array(Annotation)) : Nil
      @entries.reject!(&.source.==(source))
      entries.each do |entry|
        entry.source = source
        @entries << entry
      end
      @entries.sort_by!(&.offset)
      @listeners.dup.each(&.call)
    end

    # Returns annotations whose offsets are inclusively between *from* and *to*.
    def between(from : Int32, to : Int32) : Array(Annotation)
      @entries.select { |entry| from <= entry.offset <= to }
    end

    # Returns annotations exactly at *offset*.
    def at(offset : Int32) : Array(Annotation)
      @entries.select(&.offset.==(offset))
    end

    # Returns annotations whose offsets lie on *line*.
    def on(line : Int32) : Array(Annotation)
      buffer = @document.buffer
      return [] of Annotation unless 0 <= line < buffer.line_count

      between(buffer.line_start(line), buffer.line_end(line))
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
