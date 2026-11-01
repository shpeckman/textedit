# spec/document_spec.cr
require "./spec_helper"

private def run(text : Textedit::Document, *commands : Textedit::Command) : Bool
  commands.map { |command| text.run(command) }.last
end

describe Textedit::Document do
  describe "typing and deleting" do
    it "inserts at the cursor and deletes around it" do
      text = document("abc")
      text.cursor.should eq(3)
      run(text, Textedit::Command::DeleteBackward).should be_true
      text.value.should eq("ab")
      text.run(Textedit::Command::Left)
      text.cursor.should eq(1)
      text.run(Textedit::Command::DeleteForward)
      text.value.should eq("a")
      text.run(Textedit::Command::RowStart)
      text.insert("x").should be_true
      text.value.should eq("xa")
    end

    it "filters what it is given" do
      text = document
      text.insert("a\r\nb\tc\e")
      text.value.should eq("a b c")
      text.value = "x\ny"
      text.value.should eq("x y")
      document("a\r\nb\tc", filter: Textedit::MultiLine.new).value.should eq("a\nb c")
    end

    it "enforces max_length across every caret" do
      text = document("ab", max_length: 3)
      text.place_carets([Textedit::Caret.at(1), Textedit::Caret.at(2)])
      text.insert("x").should be_true
      text.value.should eq("axb")
      text.insert("y").should be_false
      text.value = "abcdef"
      text.value.should eq("abc")
      document("abcdef", max_length: 2).value.should eq("ab")
      long = document("abcdef")
      long.max_length = 3
      long.value.should eq("abc")
    end

    it "clears the value and reports nothing when it is unchanged" do
      text   = document("abc")
      events = Recorder.new
      text.listen(events)
      text.value = "abc"
      events.edited.should be_empty
      text.clear
      text.value.should eq("")
      text.cursor.should eq(0)
      events.edited.size.should eq(1)
    end

    it "deletes by word and to the row edges" do
      text = document("one two three")
      run(text, Textedit::Command::DeleteWordBackward)
      text.value.should eq("one two ")
      text.move(4)
      text.run(Textedit::Command::DeleteWordForward)
      text.value.should eq("one  ")
      text.move(2)
      text.run(Textedit::Command::DeleteToRowEnd)
      text.value.should eq("on")
      text.move(1)
      text.run(Textedit::Command::DeleteToRowStart)
      text.value.should eq("n")
      text.cursor.should eq(0)
      text.run(Textedit::Command::DeleteToRowStart).should be_true
      text.value.should eq("n")
    end

    it "deletes a selection whatever the delete command" do
      text = document("hello world")
      text.select_range(2, 8)
      text.run(Textedit::Command::DeleteWordBackward)
      text.value.should eq("herld")
    end
  end

  describe "auto-closing" do
    it "pairs brackets and quotes, wraps selections and types over closers" do
      text = document("", auto_close: true)
      text.insert("(")
      text.value.should eq("()")
      text.cursor.should eq(1)
      text.insert("x")
      text.insert(")")
      text.value.should eq("(x)")
      text.cursor.should eq(3)
      text.insert(" ")
      text.insert("\"")
      text.value.should eq("(x) \"\"")
      text.insert("\"")
      text.value.should eq("(x) \"\"")
      text.cursor.should eq(6)
    end

    it "wraps a selection and keeps it selected" do
      text = document("word", auto_close: true)
      text.select_range(0, 4)
      text.insert("[")
      text.value.should eq("[word]")
      text.selected_text.should eq("word")
    end

    it "leaves a quote alone after a word and when pasted" do
      text = document("don", auto_close: true)
      text.insert("'")
      text.value.should eq("don'")
      text.paste("(")
      text.value.should eq("don'(")
    end

    it "removes an empty pair with one backspace" do
      text = document("", auto_close: true)
      text.insert("{")
      text.run(Textedit::Command::DeleteBackward)
      text.value.should eq("")
      plain = document("{}")
      plain.move(1)
      plain.run(Textedit::Command::DeleteBackward)
      plain.value.should eq("}")
    end
  end

  describe "moving" do
    it "jumps by word, treating underscores and combining marks as word characters" do
      text = document("snake_case café")
      text.cursor.should eq(15)
      text.run(Textedit::Command::WordLeft)
      text.cursor.should eq(11)
      text.run(Textedit::Command::WordLeft)
      text.cursor.should eq(0)
      text.run(Textedit::Command::WordRight)
      text.cursor.should eq(10)
    end

    it "collapses a selection to its edge before moving" do
      text = document("hello")
      text.select_range(1, 4)
      text.run(Textedit::Command::Left)
      text.cursor.should eq(1)
      text.select_range(1, 4)
      text.run(Textedit::Command::Right)
      text.cursor.should eq(4)
    end

    it "extends the selection while selecting" do
      text = document("hello world")
      5.times { text.run(Textedit::Command::Left, selecting: true) }
      text.selected_text.should eq("world")
      text.run(Textedit::Command::RowStart, selecting: true)
      text.selected_text.should eq("hello world")
      text.run(Textedit::Command::WordRight, selecting: true)
      text.selected_text.should eq(" world")
    end

    it "moves vertically by display column and to row edges" do
      text = lines("a日本x\nabcd")
      text.move(2)
      text.run(Textedit::Command::Down)
      text.cursor.should eq(8)
      text.run(Textedit::Command::Up)
      text.cursor.should eq(2)
      text.run(Textedit::Command::RowEnd)
      text.cursor.should eq(4)
      text.run(Textedit::Command::Down)
      text.cursor.should eq(9)
      text.run(Textedit::Command::RowStart)
      text.cursor.should eq(5)
    end

    it "remembers the column it started from across shorter lines" do
      text = lines("abcdef\nab\nabcdef")
      text.move(5)
      text.run(Textedit::Command::Down)
      text.cursor.should eq(9)
      text.run(Textedit::Command::Down)
      text.cursor.should eq(15)
      text.run(Textedit::Command::Left)
      text.run(Textedit::Command::Up)
      text.cursor.should eq(9)
    end

    it "goes to the first non-blank column and then to the row start" do
      text = lines("    code")
      text.run(Textedit::Command::SmartRowStart)
      text.cursor.should eq(4)
      text.run(Textedit::Command::SmartRowStart)
      text.cursor.should eq(0)
      text.run(Textedit::Command::SmartRowStart)
      text.cursor.should eq(4)
    end

    it "goes to the document edges" do
      text = lines("ab\ncd")
      text.move(1)
      text.run(Textedit::Command::DocumentEnd, selecting: true)
      text.selected_text.should eq("b\ncd")
      text.run(Textedit::Command::DocumentStart)
      text.cursor.should eq(0)
    end
  end

  describe "selecting" do
    it "reports the selection and its text" do
      text = lines("ab\ncd")
      text.select_range(0, 4)
      text.selection?.should be_true
      text.selection.should eq(0...4)
      text.selected_text.should eq("ab\nc")
      text.selected?(3).should be_true
      text.selected?(4).should be_false
      text.run(Textedit::Command::SelectAll)
      text.selected_text.should eq("ab\ncd")
    end

    it "selects the word or the line under every caret" do
      text = lines("one two\nthree")
      text.move(5)
      text.run(Textedit::Command::SelectWord)
      text.selected_text.should eq("two")
      text.run(Textedit::Command::SelectLine)
      text.selected_text.should eq("one two\n")
      text.move(10)
      text.run(Textedit::Command::SelectLine)
      text.selected_text.should eq("three")
    end

    it "merges carets that meet" do
      text = document("abc")
      text.place_carets([Textedit::Caret.at(1), Textedit::Caret.at(2)])
      text.run(Textedit::Command::RowStart)
      text.carets.should eq([Textedit::Caret.at(0)])
      text.place_carets([Textedit::Caret.new(0, 2), Textedit::Caret.at(1)])
      text.carets.should eq([Textedit::Caret.new(0, 2)])
    end

    it "selects the word and then its next occurrences" do
      text = document("foo bar foo foo")
      text.move(1)
      run(text, Textedit::Command::AddNextOccurrence).should be_true
      text.selected_text.should eq("foo")
      run(text, Textedit::Command::AddNextOccurrence, Textedit::Command::AddNextOccurrence)
      text.carets.size.should eq(3)
      text.run(Textedit::Command::AddNextOccurrence).should be_false
      text.insert("x")
      text.value.should eq("x bar x x")
    end

    it "skips an occurrence, selects them all and removes the last caret" do
      text = document("ab ab ab ab")
      text.select_range(0, 2)
      text.run(Textedit::Command::AddNextOccurrence)
      text.run(Textedit::Command::SkipOccurrence).should be_true
      text.carets.map(&.range).should eq([0...2, 6...8])
      text.run(Textedit::Command::RemoveLastCaret).should be_true
      text.carets.map(&.range).should eq([0...2])
      text.run(Textedit::Command::RemoveLastCaret).should be_false
      text.run(Textedit::Command::SelectAllOccurrences).should be_true
      text.carets.size.should eq(4)
      text.primary.should eq(0)
      document("   ").run(Textedit::Command::SelectAllOccurrences).should be_false
    end

    it "collapses to the primary caret and reports when there was nothing to collapse" do
      text = document("abc")
      text.place_carets([Textedit::Caret.at(0), Textedit::Caret.at(3)], 0)
      text.run(Textedit::Command::Collapse).should be_true
      text.carets.should eq([Textedit::Caret.at(0)])
      text.run(Textedit::Command::Collapse).should be_false
    end

    it "adds carets on the rows above and below" do
      text = lines("ab\ncd\nef")
      text.move(1)
      run(text, Textedit::Command::AddCaretBelow, Textedit::Command::AddCaretBelow)
      heads(text).should eq([1, 4, 7])
      text.run(Textedit::Command::AddCaretBelow)
      heads(text).should eq([1, 4, 7])
      text.insert("-")
      text.value.should eq("a-b\nc-d\ne-f")
    end

    it "selects a box of rows and columns and starts a fresh box once cleared" do
      text = lines("abcd\nefgh\nijkl")
      text.move(1)
      run(text, Textedit::Command::BoxDown, Textedit::Command::BoxDown, Textedit::Command::BoxRight, Textedit::Command::BoxRight)
      text.selected_texts.should eq(["bc", "fg", "jk"])
      text.box.should eq({0, 1, 2, 3})
      text.run(Textedit::Command::DeleteForward)
      text.value.should eq("ad\neh\nil")
      text.clear_box
      text.move(0)
      text.run(Textedit::Command::BoxDown)
      text.box.should eq({0, 0, 1, 0})
    end

    it "selects a box dragged from a start point" do
      text = lines("abcd\nefgh")
      text.start_box(0, 1)
      text.carets.should eq([Textedit::Caret.at(9)])
      text.select_box(0, 1, 1, 3)
      text.selected_texts.should eq(["bc", "fg"])
      text.primary.should eq(1)
    end

    it "selects inside and around the innermost bracket pair" do
      text = document("(a[b]c) {d}")
      text.move(3)
      text.run(Textedit::Command::SelectInsideBrackets).should be_true
      text.selected_text.should eq("b")
      text.run(Textedit::Command::SelectAroundBrackets).should be_true
      text.selected_text.should eq("[b]")
      text.move(1)
      text.run(Textedit::Command::SelectInsideBrackets)
      text.selected_text.should eq("a[b]c")
      text.run(Textedit::Command::SelectAroundBrackets)
      text.selected_text.should eq("(a[b]c)")
      document("plain").run(Textedit::Command::SelectInsideBrackets).should be_false
    end

    it "selects bracket objects at every caret" do
      text = document("(one) [two]")
      text.place_carets([Textedit::Caret.at(2), Textedit::Caret.at(8)])
      text.run(Textedit::Command::SelectInsideBrackets).should be_true
      text.selected_texts.should eq(["one", "two"])
    end

    it "selects quote objects and skips escaped quotes" do
      text = document("one \"a\\\"b\" 'two'")
      text.move(8)
      text.run(Textedit::Command::SelectInsideQuotes).should be_true
      text.selected_text.should eq("a\\\"b")
      text.run(Textedit::Command::SelectAroundQuotes).should be_true
      text.selected_text.should eq("\"a\\\"b\"")
      text.move(13)
      text.run(Textedit::Command::SelectInsideQuotes)
      text.selected_text.should eq("two")
      document("\"open").run(Textedit::Command::SelectInsideQuotes).should be_false
    end
  end

  describe "duplicate selection" do
    it "duplicates and selects the copy as one undo step" do
      text = lines("one\ntwo")
      text.select_range(0, 3)
      text.run(Textedit::Command::DuplicateSelection).should be_true
      text.value.should eq("oneone\ntwo")
      text.selection.should eq(3...6)
      text.undo
      text.value.should eq("one\ntwo")
      text.redo
      text.selection.should eq(3...6)
    end

    it "preserves backward selections and duplicates at every caret" do
      text = document("ab cd ef")
      text.place_carets([Textedit::Caret.new(2, 0), Textedit::Caret.new(6, 8)])
      text.run(Textedit::Command::DuplicateSelection)
      text.value.should eq("abab cd efef")
      text.carets.should eq([Textedit::Caret.new(4, 2), Textedit::Caret.new(10, 12)])
      document("ab").run(Textedit::Command::DuplicateSelection).should be_false
    end

    it "honours read-only and max_length" do
      fixed = document("ab", read_only: true)
      fixed.select_all
      fixed.run(Textedit::Command::DuplicateSelection).should be_false
      limited = document("ab", max_length: 3)
      limited.select_all
      limited.run(Textedit::Command::DuplicateSelection).should be_true
      limited.value.should eq("aba")
      limited.selection.should eq(2...3)
    end
  end

  describe "history" do
    it "undoes typing at every caret as one step and redoes it" do
      text = document("ab ab")
      text.place_carets([Textedit::Caret.at(2), Textedit::Caret.at(5)])
      text.insert("!")
      text.value.should eq("ab! ab!")
      heads(text).should eq([3, 7])
      run(text, Textedit::Command::DeleteBackward, Textedit::Command::DeleteBackward)
      text.value.should eq("a a")
      run(text, Textedit::Command::Undo).should be_true
      text.value.should eq("ab! ab!")
      text.undo
      text.value.should eq("ab ab")
      heads(text).should eq([2, 5])
      run(text, Textedit::Command::Redo).should be_true
      text.value.should eq("ab! ab!")
      text.undo
      text.undo.should be_false
    end

    it "undoes values set from code" do
      text = document("one")
      text.value = "two"
      text.undo.should be_true
      text.value.should eq("one")
      text.redo.should be_true
      text.value.should eq("two")
    end

    it "replaces several ranges as one step and carries the carets" do
      text = document("a-b-c")
      text.place_carets([Textedit::Caret.at(2), Textedit::Caret.at(5)])
      text.replace_ranges([Textedit::Edit.new(1...2, "++"), Textedit::Edit.new(3...4, "++")]).should be_true
      text.value.should eq("a++b++c")
      heads(text).should eq([3, 7])
      text.replace_ranges([Textedit::Edit.new(0...0, "")]).should be_false
      text.undo
      text.value.should eq("a-b-c")
    end

    it "groups a transaction into one undo step and one notification" do
      text   = document("abc")
      events = Recorder.new
      text.listen(events)
      result = text.transaction do
        text.move(0)
        text.insert("x")
        text.run(Textedit::Command::DocumentEnd)
        text.insert("y")
        text.undo.should be_false
        42
      end
      result.should eq(42)
      text.value.should eq("xabcy")
      events.applied.size.should eq(2)
      events.edited.size.should eq(1)
      events.edited.first.size.should eq(2)
      events.moves.should eq(1)
      text.undo
      text.value.should eq("abc")
    end

    it "knows whether it changed since it was saved" do
      text = document("a")
      text.modified?.should be_false
      text.insert("b")
      text.modified?.should be_true
      text.mark_saved
      text.modified?.should be_false
      text.insert("c")
      text.modified?.should be_true
      text.undo
      text.modified?.should be_false
    end
  end

  describe "clipboard" do
    it "copies every selection, pastes one line per caret, and cuts" do
      text = document("ab cd")
      text.place_carets([Textedit::Caret.new(0, 2), Textedit::Caret.new(3, 5)])
      text.run(Textedit::Command::Copy)
      text.clipboard.as(Textedit::Register).text.should eq("ab\ncd")
      text.place_carets([Textedit::Caret.at(2), Textedit::Caret.at(5)])
      text.run(Textedit::Command::Paste)
      text.value.should eq("abab cdcd")
      text.collapse
      text.move(0)
      text.run(Textedit::Command::Paste)
      text.value.should eq("ab cdabab cdcd")
      text.place_carets([Textedit::Caret.new(0, 1), Textedit::Caret.new(5, 6)])
      text.run(Textedit::Command::Cut)
      text.value.should eq("b cdbab cdcd")
    end

    it "pastes once an asynchronous clipboard answers" do
      board = Deferred.new("later")
      text  = document(clipboard: board)
      text.run(Textedit::Command::Paste)
      text.value.should eq("")
      board.deliver
      text.value.should eq("later")
    end

    it "never copies or cuts when it is not copyable" do
      board = Textedit::Register.new
      text  = document("secret", clipboard: board, copyable: false)
      text.run(Textedit::Command::SelectAll)
      run(text, Textedit::Command::Copy, Textedit::Command::Cut)
      text.value.should eq("secret")
      board.text.should eq("")
    end

    it "copies a selection as it is made unless a drag is still under way" do
      board = Textedit::Register.new
      text  = document("hello world", clipboard: board, copy_on_select: true)
      text.dragging = true
      text.move(6)
      text.move(11, selecting: true)
      board.text.should eq("")
      text.dragging = false
      text.auto_copy
      board.text.should eq("world")
      text.run(Textedit::Command::WordLeft, selecting: true)
      board.text.should eq("world")
      text.run(Textedit::Command::SelectAll)
      board.text.should eq("hello world")
    end

    it "copies a selection as it is made into the selection clipboard and leaves the clipboard alone" do
      board     = Textedit::Register.new
      selection = Textedit::Register.new
      text      = document("hello world", clipboard: board, selection_clipboard: selection, copy_on_select: true)
      text.move(6)
      text.move(11, selecting: true)
      selection.text.should eq("world")
      board.text.should eq("")
      text.run(Textedit::Command::Copy)
      board.text.should eq("world")
    end

    it "cycles the immediately preceding paste through clipboard history" do
      board = Textedit::Register.new
      board.write("one")
      board.write("two")
      board.write("three")
      text = document("", clipboard: board)
      text.run(Textedit::Command::Paste)
      text.value.should eq("three")
      text.run(Textedit::Command::PastePrevious).should be_true
      text.value.should eq("two")
      text.run(Textedit::Command::PastePrevious).should be_true
      text.value.should eq("one")
      text.run(Textedit::Command::PastePrevious).should be_false
      text.undo
      text.value.should eq("two")
    end

    it "cycles multi-caret pastes and rejects an invalidated session" do
      board = Textedit::Register.new
      board.write("x\ny")
      board.write("a\nb")
      text = lines("\n", clipboard: board)
      text.place_carets([Textedit::Caret.at(0), Textedit::Caret.at(1)])
      text.run(Textedit::Command::Paste)
      text.value.should eq("a\nb")
      text.run(Textedit::Command::PastePrevious)
      text.value.should eq("x\ny")
      text.insert("!")
      text.run(Textedit::Command::PastePrevious).should be_false
      text.read_only = true
      text.run(Textedit::Command::PastePrevious).should be_false
    end

    it "validates deferred history reads before replacing a paste" do
      board = DeferredHistory.new(["new", "old"])
      text  = document("", clipboard: board)
      text.run(Textedit::Command::Paste)
      board.deliver
      text.value.should eq("new")
      text.run(Textedit::Command::PastePrevious).should be_true
      board.deliver
      text.value.should eq("old")
      board.entries.unshift("latest")
      text.run(Textedit::Command::Paste)
      board.deliver
      text.run(Textedit::Command::PastePrevious)
      text.insert("!")
      board.deliver
      text.value.should eq("oldlatest!")
    end
  end

  describe "lines" do
    it "inserts plain line breaks or keeps the indentation" do
      plain = lines("  foo")
      plain.run(Textedit::Command::NewLine).should be_true
      plain.value.should eq("  foo\n")
      text = code("  foo")
      text.run(Textedit::Command::NewLine)
      text.insert("x")
      text.value.should eq("  foo\n  x")
    end

    it "indents with tab and outdents every selected line" do
      text = code("a\nb\nc")
      text.move(0)
      text.run(Textedit::Command::Tab).should be_true
      text.value.should eq("  a\nb\nc")
      text.select_range(0, 5)
      text.run(Textedit::Command::Tab)
      text.value.should eq("    a\n  b\nc")
      run(text, Textedit::Command::Outdent, Textedit::Command::Outdent)
      text.value.should eq("a\nb\nc")
      text.run(Textedit::Command::Outdent).should be_false
      text.undo
      text.value.should eq("  a\nb\nc")
    end

    it "outdents tab indentation and stray spaces" do
      text = document("\t\ta\n   b", filter: Textedit::MultiLine.new("\t"), indent: "\t", tab_size: 2)
      text.run(Textedit::Command::SelectAll)
      text.run(Textedit::Command::Outdent)
      text.value.should eq("\ta\n b")
      text.run(Textedit::Command::Outdent)
      text.value.should eq("a\nb")
    end

    it "toggles a line comment at the shallowest indentation, skipping blank lines" do
      text = code("  if x\n\n    y", comment: "#")
      text.run(Textedit::Command::SelectAll)
      text.run(Textedit::Command::ToggleComment).should be_true
      text.value.should eq("  # if x\n\n  #   y")
      text.run(Textedit::Command::ToggleComment)
      text.value.should eq("  if x\n\n    y")
      code("x").run(Textedit::Command::ToggleComment).should be_false
    end

    it "moves, duplicates and deletes the lines under every caret" do
      text = code("a\nb\nc\nd")
      text.move(2)
      text.run(Textedit::Command::MoveLinesDown).should be_true
      text.value.should eq("a\nc\nb\nd")
      text.cursor.should eq(4)
      run(text, Textedit::Command::MoveLinesUp, Textedit::Command::MoveLinesUp)
      text.value.should eq("b\na\nc\nd")
      text.run(Textedit::Command::MoveLinesUp).should be_false
      text.place_carets([Textedit::Caret.at(0), Textedit::Caret.at(4)])
      text.run(Textedit::Command::DuplicateLines).should be_true
      text.value.should eq("b\nb\na\nc\nc\nd")
      heads(text).should eq([2, 8])
      text.run(Textedit::Command::DeleteLines).should be_true
      text.value.should eq("b\na\nc\nd")
      text.undo
      text.value.should eq("b\nb\na\nc\nc\nd")
    end

    it "turns pasted tabs into its indent" do
      text = document("", filter: Textedit::MultiLine.new("    "), indent: "    ")
      text.paste("\tx")
      text.value.should eq("    x")
    end
  end

  describe "find and replace" do
    it "selects matches forward and backward" do
      text   = lines("one two one\ntwo one")
      search = Textedit::Search.new("one")
      text.move(0)
      text.find(search).should eq(0...3)
      text.find(search).should eq(8...11)
      text.find(search).should eq(16...19)
      text.find(search, backward: true).should eq(8...11)
      text.selection.should eq(8...11)
      text.find(Textedit::Search.new("zzz")).should be_nil
    end

    it "replaces the selected match and every match as one step, expanding captures" do
      text   = document("a=1 b=2 c=3")
      search = Textedit::Search.new("(\\w+)=(\\d)", regex: true)
      text.move(0)
      found = text.find(search).not_nil!
      text.replace_match(search, found, "$2=$1").should be_true
      text.value.should eq("1=a b=2 c=3")
      text.replace_match(search, 0...1, "x").should be_false
      text.replace_all(search, "$2=$1").should eq(2)
      text.value.should eq("1=a 2=b 3=c")
      text.undo
      text.value.should eq("1=a b=2 c=3")
      text.replace_all(Textedit::Search.new("zzz"), "x").should eq(0)
    end
  end

  describe "line endings" do
    it "keeps line feeds inside and exports the endings it was given" do
      text = lines("a\r\nb\r\n")
      text.value.should eq("a\nb\n")
      text.line_ending.should eq(Textedit::LineEnding::CRLF)
      text.export.should eq("a\r\nb\r\n")
      text.value = "x\ny"
      text.line_ending.should eq(Textedit::LineEnding::LF)
      text.line_ending = Textedit::LineEnding::CR
      text.export.should eq("x\ry")
      text.value = "single"
      text.line_ending.should eq(Textedit::LineEnding::CR)
    end
  end

  describe "read-only" do
    it "refuses edits but still moves, selects and copies" do
      board = Textedit::Register.new
      text  = document("fixed", clipboard: board, read_only: true)
      text.insert("x").should be_false
      text.paste("x").should be_false
      text.run(Textedit::Command::DeleteBackward).should be_false
      text.run(Textedit::Command::Undo).should be_false
      text.run(Textedit::Command::SelectAll).should be_true
      text.run(Textedit::Command::Copy).should be_true
      board.text.should eq("fixed")
      text.run(Textedit::Command::Cut).should be_false
      text.replace_all(Textedit::Search.new("f"), "g").should eq(0)
      text.value.should eq("fixed")
      text.value = "set from code"
      text.value.should eq("set from code")
    end
  end

  describe "marks" do
    it "follows edits, with gravity deciding which side an insertion at the mark lands on" do
      text  = document("abcdef")
      left  = text.mark(3)
      right = text.mark(3, Textedit::Gravity::Right)
      tail  = text.mark(5)
      text.move(3)
      text.insert("XY")
      left.offset.should eq(3)
      right.offset.should eq(5)
      tail.offset.should eq(7)
      text.select_range(2, 6)
      text.run(Textedit::Command::DeleteForward)
      left.offset.should eq(2)
      right.offset.should eq(2)
      tail.offset.should eq(3)
      text.unmark(tail)
      text.marks.size.should eq(2)
    end
  end

  it "finds the bracket matching the one beside an empty primary caret" do
    text = document("if (a(b)) x")
    text.move(4)
    text.brackets.should eq({3, 8})
    text.move(8)
    text.brackets.should eq({5, 7})
    text.move(1)
    text.brackets.should be_nil
    text.select_range(3, 4)
    text.brackets.should be_nil
  end
end
