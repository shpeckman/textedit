# spec/history_spec.cr
require "./spec_helper"

private class Clock
  getter now : Time::Instant = Time.instant

  def advance(span : Time::Span) : Nil
    @now += span
  end

  def proc : Proc(Time::Instant)
    -> { @now }
  end
end

private def edit(text : Textedit::Buffer, at : Int32, inserted : String) : Textedit::Change
  text.replace(at...at, inserted)
end

private def carets(*offsets : Int32) : Array(Textedit::Caret)
  offsets.to_a.map { |offset| Textedit::Caret.at(offset) }
end

private def commit(changes : Array(Textedit::Change), before : Array(Textedit::Caret), after : Array(Textedit::Caret),
                   gesture : Textedit::Gesture = Textedit::Gesture::Other,
                   origin : Textedit::Origin = Textedit::Origin::User) : Textedit::Commit
  Textedit::Commit.new(gesture, origin, changes, before, 0, after, 0)
end

private def typing : Textedit::Gesture
  Textedit::Gesture::Typing
end

private def restore(text : Textedit::Buffer, found : Textedit::History::Restore?) : Array(Textedit::Change)
  found.not_nil!.edits.map { |entry| text.replace(entry.range, entry.text) }
end

describe Textedit::History::Linear do
  it "undoes and redoes steps with their carets as edits to apply" do
    text    = buffer("")
    history = Textedit::History::Linear.new(GRAPHEMES)
    history.record(commit([edit(text, 0, "abc")], carets(0), carets(3)))
    text.text.should eq("abc")
    step = history.undo.not_nil!
    step.carets.should eq(carets(0))
    restore(text, step).should eq([change(0, "abc", "")])
    text.text.should eq("")
    history.can_redo?.should be_true
    again = history.redo.not_nil!
    again.carets.should eq(carets(3))
    restore(text, again)
    text.text.should eq("abc")
    restore(text, history.undo)
    history.undo.should be_nil
  end

  it "joins typing into one step and breaks it at word starts" do
    text    = buffer("")
    history = Textedit::History::Linear.new(GRAPHEMES)
    "ab c".each_char_with_index do |char, index|
      history.record(commit([edit(text, index, char.to_s)], carets(index), carets(index + 1), typing))
    end
    restore(text, history.undo)
    text.text.should eq("ab ")
    restore(text, history.undo)
    text.text.should eq("")
  end

  it "starts a new step when the carets moved, the gesture changed or the window passed" do
    clock   = Clock.new
    text    = buffer("")
    history = Textedit::History::Linear.new(GRAPHEMES, clock: clock.proc)
    history.record(commit([edit(text, 0, "a")], carets(0), carets(1), typing))
    history.record(commit([edit(text, 0, "b")], carets(0), carets(1), typing))
    restore(text, history.undo)
    text.text.should eq("a")

    history.record(commit([text.replace(0...1, "")], carets(1), carets(0), Textedit::Gesture::Deleting))
    restore(text, history.undo)
    text.text.should eq("a")

    history.record(commit([edit(text, 1, "x")], carets(1), carets(2), typing))
    clock.advance(2.seconds)
    history.record(commit([edit(text, 2, "y")], carets(2), carets(3), typing))
    restore(text, history.undo)
    text.text.should eq("ax")
  end

  it "forgets the redo stack on a new edit and keeps at most its limit" do
    text    = buffer("")
    history = Textedit::History::Linear.new(GRAPHEMES, limit: 2)
    3.times do |index|
      history.record(commit([edit(text, index, "x")], carets(index), carets(index + 1)))
    end
    restore(text, history.undo)
    restore(text, history.undo)
    history.undo.should be_nil
    text.text.should eq("x")
    history.record(commit([edit(text, 1, "y")], carets(1), carets(2)))
    history.can_redo?.should be_false
  end

  it "tracks a save point through undo, redo and further typing" do
    text    = buffer("")
    history = Textedit::History::Linear.new(GRAPHEMES)
    history.modified?.should be_false
    history.record(commit([edit(text, 0, "a")], carets(0), carets(1), typing))
    history.modified?.should be_true
    history.mark_saved
    history.modified?.should be_false
    history.record(commit([edit(text, 1, "b")], carets(1), carets(2), typing))
    history.modified?.should be_true
    restore(text, history.undo)
    history.modified?.should be_false
    restore(text, history.undo)
    history.modified?.should be_true
    restore(text, history.redo)
    history.modified?.should be_false
  end

  it "ignores the commits its own undo and redo produce" do
    text    = buffer("")
    history = Textedit::History::Linear.new(GRAPHEMES)
    history.record(commit([edit(text, 0, "a")], carets(0), carets(1)))
    applied = restore(text, history.undo)
    history.record(commit(applied, carets(1), carets(0), origin: Textedit::Origin::Undo))
    history.can_undo?.should be_false
    history.can_redo?.should be_true
  end
end
