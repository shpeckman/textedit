# spec/spec_helper.cr
require "spec"
require "file_utils"
require "../src/textedit"

struct Plain
  include Textedit::Graphemes

  WIDE = [0x1100..0x115F, 0x2E80..0xA4CF, 0xAC00..0xD7A3, 0xF900..0xFAFF, 0xFF00..0xFF60, 0x1F300..0x1FAFF]

  def boundaries(text : String) : Array(Int32)
    marks = [0]
    text.each_grapheme { |grapheme| marks << marks.last + grapheme.to_s.bytesize }
    marks
  end

  def kind(cluster : Bytes) : Textedit::ClusterKind
    char = String.new(cluster)[0]? || return Textedit::ClusterKind::Other
    return Textedit::ClusterKind::Space if char.whitespace?
    return Textedit::ClusterKind::Word if char.alphanumeric? || char == '_'
    return Textedit::ClusterKind::Other if char.control?

    Textedit::ClusterKind::Punct
  end

  def width(cluster : Bytes) : Int32
    code = String.new(cluster)[0]?.try(&.ord) || return 0
    WIDE.any?(&.includes?(code)) ? 2 : 1
  end
end

class Deferred
  include Textedit::Clipboard

  getter text    : String
  getter pending : Array(Proc(String?, Nil))

  def initialize(@text : String = "")
    @pending = [] of Proc(String?, Nil)
  end

  def write(text : String) : Nil
    @text = text
  end

  def read(&block : String? -> Nil) : Nil
    @pending << block
  end

  def deliver : Nil
    @pending.each(&.call(@text))
    @pending.clear
  end
end

class DeferredHistory
  include Textedit::Clipboard
  include Textedit::ClipboardHistory

  getter entries  : Array(String)
  getter pending  : Array({Int32, Proc(String?, Nil)})

  def initialize(@entries : Array(String))
    @pending = [] of {Int32, Proc(String?, Nil)}
  end

  def size : Int32
    @entries.size
  end

  def write(text : String) : Nil
    @entries.unshift(text)
  end

  def read(&block : String? -> Nil) : Nil
    read(0, &block)
  end

  def read(index : Int32, &block : String? -> Nil) : Nil
    @pending << {index, block}
  end

  def deliver : Nil
    @pending.each { |(index, block)| block.call(@entries[index]?) }
    @pending.clear
  end
end

class Recorder
  include Textedit::Listener

  getter applied = [] of Textedit::Change
  getter edited  = [] of Array(Textedit::Change)
  getter moves   = 0
  getter last_view : Textedit::View? = nil

  def applied(document : Textedit::Document, change : Textedit::Change) : Nil
    @applied << change
  end

  def edited(document : Textedit::Document, changes : Array(Textedit::Change)) : Nil
    @edited << changes
  end

  def moved(view : Textedit::View) : Nil
    @moves += 1
    @last_view = view
  end
end

GRAPHEMES = Plain.new

def buffer(text : String) : Textedit::Buffer
  Textedit::Buffer.new(GRAPHEMES, text)
end

def line(text : String) : Textedit::Line
  Textedit::Line.new(text, GRAPHEMES)
end

def editor(text : String = "", **options) : Textedit::Editor
  Textedit::Editor.new(GRAPHEMES, text, **{filter: Textedit::SingleLine.new}.merge(options))
end

def lines(text : String = "", **options) : Textedit::Editor
  Textedit::Editor.new(GRAPHEMES, text, **options)
end

def code(text : String = "", **options) : Textedit::Editor
  subject = Textedit::Editor.new(GRAPHEMES, text, **{filter: Textedit::MultiLine.new("  ")}.merge(options))
  subject.auto_indent = true
  subject
end

def heads(view : Textedit::View) : Array(Int32)
  view.carets.map(&.head)
end

def change(from : Int32, removed : String, inserted : String) : Textedit::Change
  Textedit::Change.new(from, removed, inserted, GRAPHEMES.boundaries(removed).size - 1, GRAPHEMES.boundaries(inserted).size - 1)
end
