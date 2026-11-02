# spec/composition_spec.cr
require "./spec_helper"

private class Pin < Textedit::View
  alias Command = Textedit::Motion | Textedit::Deletion

  include Textedit::Typing
  include Textedit::Deleting
end

private class Everything < Textedit::View
  alias Command = Textedit::Motion | Textedit::Selection | Textedit::Carets | Textedit::Box | Textedit::Deletion |
                  Textedit::Whitespace | Textedit::Lines | Textedit::Transform | Textedit::Copy | Textedit::Clip |
                  Textedit::UndoRedo

  include Textedit::Typing
  include Textedit::Deleting
  include Textedit::Spacing
  include Textedit::LineEditing
  include Textedit::Transforming
  include Textedit::Selecting
  include Textedit::Multicaret
  include Textedit::Boxing
  include Textedit::Copying
  include Textedit::Pasting
  include Textedit::Undoing
  include Textedit::Finding
  include Textedit::Replacing
  include Textedit::Folding
  include Textedit::Snipping
  include Textedit::Recording(Command)
end

private class Keeping
  include Textedit::History

  getter commits = [] of Textedit::Commit

  def record(commit : Textedit::Commit) : Nil
    @commits << commit
  end

  def undo : Textedit::History::Restore?
    nil
  end

  def redo : Textedit::History::Restore?
    nil
  end

  def can_undo? : Bool
    false
  end

  def can_redo? : Bool
    false
  end

  def modified? : Bool
    !@commits.empty?
  end

  def mark_saved : Nil
    @commits.clear
  end

  def clear : Nil
    @commits.clear
  end
end

private struct Digits
  include Textedit::Filter

  def filter(text : String) : String
    text.delete { |char| !char.ascii_number? }
  end
end

describe "composed views" do
  it "gives each preset the document defaults it needs" do
    Textedit::Field.new(GRAPHEMES, "a\nb").value.should eq("a b")
    Textedit::Area.new(GRAPHEMES, "a\nb").value.should eq("a\nb")
    Textedit::Editor.new(GRAPHEMES, "a\nb").value.should eq("a\nb")
    reader = Textedit::Reader.new(GRAPHEMES, "a\nb")
    reader.value.should eq("a\nb")
    reader.document.history.should be_nil
  end

  it "lets options override a preset's defaults" do
    Textedit::Area.new(GRAPHEMES, "a\nb", filter: Textedit::SingleLine.new).value.should eq("a b")
    Textedit::Field.new(GRAPHEMES, "x", history: nil).document.history.should be_nil
  end

  it "includes only the features a preset composes" do
    reader = Textedit::Reader.new(GRAPHEMES, "one two")
    reader.responds_to?(:insert).should be_false
    reader.responds_to?(:undo).should be_false
    reader.responds_to?(:find).should be_true
    reader.responds_to?(:folds).should be_true

    field = Textedit::Field.new(GRAPHEMES, "x")
    field.responds_to?(:insert).should be_true
    field.responds_to?(:folds).should be_false
    field.responds_to?(:replay).should be_false
  end

  it "dispatches a preset's command union to its features" do
    field = Textedit::Field.new(GRAPHEMES, "one two")
    keys  = [Textedit::Motion::WordLeft, Textedit::Deletion::WordBackward, Textedit::Selection::All] of Textedit::Field::Command
    keys.each { |command| field.run(command, selecting: false) }
    field.value.should eq("two")
    field.selected_text.should eq("two")
  end

  it "builds a host widget from just the features it names" do
    pin = Pin.new(GRAPHEMES, "", filter: Digits.new, history: nil, constraints: [Textedit::MaxLength.new(4)])
    pin.insert("12a345").should be_true
    pin.value.should eq("1234")
    pin.run(Textedit::Deletion::Backward).should be_true
    pin.value.should eq("123")
    pin.responds_to?(:undo).should be_false
    pin.document.undo.should be_false
  end

  it "composes every feature into a host widget outside the namespace" do
    view = Everything.new(GRAPHEMES, "one\ntwo", filter: Textedit::MultiLine.new)
    view.record
    view.run(Textedit::Selection::All)
    view.run(Textedit::Copy::Selection)
    view.run(Textedit::Motion::DocumentEnd)
    view.run(Textedit::Whitespace::NewLine)
    view.run(Textedit::Clip::Paste)
    view.stop
    view.value.should eq("one\ntwo\none\ntwo")
    view.folds.fold(0, 1).should_not be_nil
    view.run(Textedit::Box::Down)
    view.box.should_not be_nil
    view.run(Textedit::UndoRedo::Undo).should be_true
    view.replay.should be_true
    view.macros.size.should eq(5)
  end

  it "edits without a history and still knows when it was modified" do
    field = Textedit::Field.new(GRAPHEMES, "a", history: nil)
    field.document.modified?.should be_false
    field.insert("b")
    field.document.modified?.should be_true
    field.undo.should be_false
    field.run(Textedit::UndoRedo::Undo).should be_false
    field.document.mark_saved
    field.document.modified?.should be_false
  end

  it "feeds every commit, with its gesture and origin, to a history the host supplies" do
    kept  = Keeping.new
    field = Textedit::Field.new(GRAPHEMES, "", history: kept)
    field.insert("a")
    field.value = "set"
    field.run(Textedit::Deletion::Backward)
    kept.commits.map(&.origin).should eq([Textedit::Origin::User, Textedit::Origin::Code, Textedit::Origin::User])
    kept.commits.map(&.gesture).should eq([Textedit::Gesture::Typing, Textedit::Gesture::Other, Textedit::Gesture::Deleting])
    kept.commits.last.before.should eq([Textedit::Caret.at(3)])
    kept.commits.last.after.should eq([Textedit::Caret.at(2)])
    field.document.modified?.should be_true
  end

  it "swaps the history of a live document" do
    field = Textedit::Field.new(GRAPHEMES, "a")
    field.insert("b")
    field.document.history = nil
    field.undo.should be_false
    field.document.history = Textedit::History::Linear.new(GRAPHEMES, limit: 1)
    field.insert("c")
    field.undo.should be_true
    field.value.should eq("ab")
  end

  it "passes a view to another feature set over the same document" do
    reader = Textedit::Reader.new(GRAPHEMES, "one two")
    reader.select_range(4, 7)
    editor = Textedit::Editor.new(reader.document)
    editor.place_carets(reader.carets, reader.primary)
    reader.close
    editor.insert("2")
    editor.value.should eq("one 2")
    reader.document.views.should eq([editor] of Textedit::View)
  end
end
