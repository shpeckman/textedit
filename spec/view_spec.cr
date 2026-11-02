# spec/view_spec.cr
require "./spec_helper"

describe Textedit::View do
  it "builds its own document from text and attaches to it" do
    text = editor("hello world")
    text.document.views.should eq([text] of Textedit::View)
    text.document.value.should eq("hello world")
    text.select_range(0, 5)
    text.selection.should eq(0...5)
  end

  it "keeps carets independent between views of one document" do
    text  = editor("one two three")
    other = Textedit::Editor.new(text.document)

    text.select_range(0, 3)
    other.select_range(4, 7)

    text.selection.should eq(0...3)
    other.selection.should eq(4...7)
    text.selected_text.should eq("one")
    other.selected_text.should eq("two")
  end

  it "carries the other views' carets through an edit" do
    text  = editor("one two three")
    other = Textedit::Reader.new(text.document)
    other.select_range(8, 13)

    text.run(Textedit::Motion::DocumentStart)
    text.insert("zero ")

    text.value.should eq("zero one two three")
    text.cursor.should eq(5)
    other.selection.should eq(13...18)
    other.selected_text.should eq("three")
  end

  it "carries every view's carets through an edit made from code" do
    text = editor("one two")
    text.select_range(4, 7)
    text.document.replace_ranges([Textedit::Edit.new(0...0, "zero ")]).should be_true
    text.selection.should eq(9...12)
    text.document.undo.should be_true
    text.value.should eq("one two")
    text.selection.should eq(4...7)
  end

  it "collapses a carried caret that sat inside removed text" do
    text  = editor("alpha beta gamma")
    other = Textedit::Editor.new(text.document)
    other.select_range(6, 10)

    text.select_range(0, 11)
    text.run(Textedit::Deletion::Forward)

    text.value.should eq("gamma")
    other.cursor.should eq(0)
    other.selection.should eq(0...0)
  end

  it "seats the undoing view's carets and carries the rest" do
    text  = editor("one two")
    other = Textedit::Editor.new(text.document)
    other.select_range(4, 7)

    text.run(Textedit::Motion::DocumentEnd)
    text.insert("!")
    other.cursor.should eq(7)

    text.undo.should be_true
    text.value.should eq("one two")
    text.cursor.should eq(7)
    other.selection.should eq(4...7)
  end

  it "lets a second view undo with its own carets" do
    text  = editor("abc")
    other = Textedit::Editor.new(text.document)

    other.run(Textedit::Motion::DocumentEnd)
    other.insert("d")
    text.value.should eq("abcd")

    other.undo.should be_true
    text.value.should eq("abc")
    other.cursor.should eq(3)
  end

  it "shares one history across the views of a document" do
    text  = editor("a")
    other = Textedit::Editor.new(text.document)

    text.run(Textedit::Motion::DocumentEnd)
    text.replace_ranges([Textedit::Edit.new(1...1, "b")])
    other.run(Textedit::Motion::DocumentEnd)
    other.replace_ranges([Textedit::Edit.new(2...2, "c")])
    text.value.should eq("abc")

    other.undo.should be_true
    text.value.should eq("ab")
    text.undo.should be_true
    text.value.should eq("a")
    text.undo.should be_false
  end

  it "gives each view its own layout and box selection" do
    text  = editor("one\ntwo\nthree")
    other = Textedit::Editor.new(text.document)

    text.start_box(0, 0)
    text.select_box(0, 0, 1, 2)
    text.box.should eq({0, 0, 1, 2})
    other.box.should be_nil
  end

  it "stops following the document once closed" do
    text  = editor("one two")
    other = Textedit::Editor.new(text.document)
    text.document.views.size.should eq(2)

    other.close
    text.document.views.size.should eq(1)

    other.select_range(0, 3)
    text.select_range(0, 7)
    text.insert("x")
    other.selection.should eq(0...3)
  end

  it "reports caret moves per view to listeners" do
    text   = editor("one two")
    events = Recorder.new
    other  = Textedit::Editor.new(text.document)
    text.document.listen(events)

    other.run(Textedit::Motion::DocumentEnd)
    events.moves.should eq(1)
    events.last_view.should be(other)

    text.run(Textedit::Motion::DocumentStart)
    events.moves.should eq(2)
    events.last_view.should be(text)
  end

  it "reports each view that moved once at the end of a transaction" do
    text   = editor("one two")
    other  = Textedit::Editor.new(text.document)
    events = Recorder.new
    text.document.listen(events)

    text.document.transaction do
      text.move(0)
      text.move(1)
      other.move(2)
    end
    events.moves.should eq(2)
  end
end
