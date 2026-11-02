# spec/transforms_spec.cr
require "./spec_helper"

describe "Textedit::View subword motion" do
  it "steps through camelCase, snake_case and punctuation" do
    text = editor("fooBarBaz snake_case_name")
    text.run(Textedit::Motion::DocumentStart)
    text.run(Textedit::Motion::SubwordRight)
    text.cursor.should eq(3)
    text.run(Textedit::Motion::SubwordRight)
    text.cursor.should eq(6)
    text.run(Textedit::Motion::SubwordRight)
    text.cursor.should eq(10)
    text.run(Textedit::Motion::SubwordRight)
    text.cursor.should eq(16)
    text.run(Textedit::Motion::SubwordRight)
    text.cursor.should eq(21)
  end

  it "steps back the same way and selects while shifted" do
    text = editor("fooBarBaz")
    text.run(Textedit::Motion::DocumentEnd)
    text.run(Textedit::Motion::SubwordLeft)
    text.cursor.should eq(6)
    text.run(Textedit::Motion::SubwordLeft, true)
    text.selection.should eq(3...6)
  end

  it "deletes a subword either way" do
    text = editor("fooBarBaz")
    text.run(Textedit::Motion::DocumentEnd)
    text.run(Textedit::Deletion::SubwordBackward).should be_true
    text.value.should eq("fooBar")

    text.run(Textedit::Motion::DocumentStart)
    text.run(Textedit::Deletion::SubwordForward)
    text.value.should eq("Bar")
  end
end

describe "Textedit::Transforming line transforms" do
  it "sorts, reverses and uniques the lines under the carets" do
    text = lines("c\na\nb\na")
    text.select_range(0, 7)
    text.run(Textedit::Transform::Sort).should be_true
    text.value.should eq("a\na\nb\nc")

    text.run(Textedit::Transform::Reverse)
    text.value.should eq("c\nb\na\na")

    text.run(Textedit::Transform::Unique)
    text.value.should eq("c\nb\na")
  end

  it "trims trailing whitespace and reports when there is none" do
    text = lines("one  \ntwo\t\nthree")
    text.select_all
    text.run(Textedit::Transform::TrimTrailingWhitespace).should be_true
    text.value.should eq("one\ntwo\nthree")
    text.run(Textedit::Transform::TrimTrailingWhitespace).should be_false
  end

  it "joins the lines in the block, or the next line with an empty caret" do
    text = lines("one\n  two\nthree")
    text.select_range(0, 9)
    text.run(Textedit::Transform::Join).should be_true
    text.value.should eq("one two\nthree")

    text.run(Textedit::Motion::DocumentStart)
    text.run(Textedit::Transform::Join)
    text.value.should eq("one two three")
    text.run(Textedit::Transform::Join).should be_false
  end

  it "leaves sorted lines alone" do
    text = lines("a\nb")
    text.select_all
    text.run(Textedit::Transform::Sort).should be_false
  end
end

describe "Textedit::Transforming case transforms" do
  it "upper, lower and title case every selection" do
    text = editor("hello wide world")
    text.select_range(0, 5)
    text.run(Textedit::Transform::UpperCase).should be_true
    text.value.should eq("HELLO wide world")
    text.selection.should eq(0...5)

    text.run(Textedit::Transform::LowerCase)
    text.value.should eq("hello wide world")

    text.select_range(0, 16)
    text.run(Textedit::Transform::TitleCase)
    text.value.should eq("Hello Wide World")
  end

  it "does nothing without a selection" do
    text = editor("abc")
    text.run(Textedit::Transform::UpperCase).should be_false
  end
end

describe "Textedit::Multicaret and Textedit::Finding carets" do
  it "puts a caret on every line of a spanning selection" do
    text = lines("one\ntwo\nthree")
    text.select_range(0, 13)
    text.run(Textedit::Carets::AddPerLine).should be_true
    text.carets.size.should eq(3)
    text.carets.map(&.head).should eq([3, 7, 13])
    text.run(Textedit::Carets::AddPerLine).should be_false
  end

  it "puts a caret on every match of a search" do
    text   = lines("one two\none")
    search = Textedit::Search.new("one")
    text.add_caret_at_every_match(search).should be_true
    text.carets.size.should eq(2)
    text.selected_texts.should eq(["one", "one"])
    text.add_caret_at_every_match(Textedit::Search.new("zzz")).should be_false
  end
end

describe "Textedit::Transforming surround" do
  it "wraps each selection and keeps it selected" do
    text = editor("one two")
    text.select_range(0, 3)
    text.surround("(").should be_true
    text.value.should eq("(one) two")
    text.selected_text.should eq("one")
  end

  it "removes a matching pair around the selection" do
    text = editor("(one) two")
    text.select_range(0, 5)
    text.unsurround.should be_true
    text.value.should eq("one two")
    text.selected_text.should eq("one")
  end

  it "refuses an unknown opener and a selection without a pair" do
    text = editor("one")
    text.select_range(0, 3)
    text.surround("<").should be_false
    text.unsurround.should be_false
  end
end

describe Textedit::Recording do
  it "records commands and typed text, then replays them" do
    text = lines("alpha\nbeta")

    text.record
    text.run(Textedit::Motion::DocumentStart)
    text.run(Textedit::Motion::RowEnd)
    text.insert("!")
    text.stop
    text.macros.size.should eq(3)

    text.run(Textedit::Motion::DocumentEnd)
    text.replay.should be_true
    text.value.should eq("alpha!!\nbeta")
  end

  it "replays several times as one undo step each and never records itself" do
    text = lines("a")

    text.record
    text.insert("x")
    text.stop
    text.macros.size.should eq(1)

    text.replay(3).should be_true
    text.value.should eq("axxxx")
    text.macros.size.should eq(1)
    text.undo
    text.value.should eq("axxx")
  end

  it "records a tab as one command, not also as the text it inserts" do
    text = lines("")

    text.record
    text.run(Textedit::Whitespace::Tab)
    text.stop
    text.macros.entries.should eq([Textedit::Whitespace::Tab] of Textedit::Editor::Command | String)

    text.replay
    text.value.should eq("    ")
  end

  it "refuses to replay nothing" do
    lines("a").replay.should be_false
  end
end
