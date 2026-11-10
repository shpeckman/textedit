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

describe Textedit::History::Grouping do
  it "can disable or replace linear grouping" do
    text    = buffer("")
    history = Textedit::History::Linear.new(GRAPHEMES, grouping: Textedit::History::Grouping::Never.new)
    history.record(commit([edit(text, 0, "a")], carets(0), carets(1), typing))
    history.record(commit([edit(text, 1, "b")], carets(1), carets(2), typing))
    restore(text, history.undo)
    text.text.should eq("a")

    history = Textedit::History::Linear.new(GRAPHEMES, grouping: SameGesture.new)
    history.record(commit([edit(text, 1, "x")], carets(1), carets(2)))
    history.record(commit([edit(text, 2, "y")], carets(2), carets(3)))
    restore(text, history.undo)
    text.text.should eq("a")
  end
end

describe Textedit::History::Tree do
  it "undoes and redoes commits with their carets" do
    text    = buffer("")
    history = Textedit::History::Tree.new(GRAPHEMES)
    history.record(commit([edit(text, 0, "a")], carets(0), carets(1)))
    step = history.undo.not_nil!
    step.carets.should eq(carets(0))
    restore(text, step)
    text.text.should eq("")
    restore(text, history.redo)
    text.text.should eq("a")
    history.undo.not_nil!.carets.should eq(carets(0))
  end

  it "preserves branches and chooses which child to redo" do
    text    = buffer("")
    history = Textedit::History::Tree.new(GRAPHEMES)
    history.record(commit([edit(text, 0, "a")], carets(0), carets(1)))
    history.record(commit([edit(text, 1, "b")], carets(1), carets(2)))
    restore(text, history.undo)
    alternate = history.current.children.first

    history.record(commit([edit(text, 1, "x")], carets(1), carets(2)))
    text.text.should eq("ax")
    history.current.children.should be_empty
    restore(text, history.undo)
    history.current.children.size.should eq(2)
    history.choose(alternate).should be_true
    restore(text, history.redo)
    text.text.should eq("ab")

    restore(text, history.undo)
    history.choose(history.current.children[1]).should be_true
    restore(text, history.redo)
    text.text.should eq("ax")
  end

  it "uses configurable grouping" do
    text    = buffer("")
    history = Textedit::History::Tree.new(GRAPHEMES, grouping: Textedit::History::Grouping::Never.new)
    history.record(commit([edit(text, 0, "a")], carets(0), carets(1), typing))
    history.record(commit([edit(text, 1, "b")], carets(1), carets(2), typing))
    restore(text, history.undo)
    text.text.should eq("a")

    history.grouping = SameGesture.new
    history.record(commit([edit(text, 1, "x")], carets(1), carets(2)))
    history.record(commit([edit(text, 2, "y")], carets(2), carets(3)))
    restore(text, history.undo)
    text.text.should eq("a")
  end

  it "tracks save points by node identity" do
    text    = buffer("")
    history = Textedit::History::Tree.new(GRAPHEMES)
    history.record(commit([edit(text, 0, "a")], carets(0), carets(1)))
    history.mark_saved
    history.record(commit([edit(text, 1, "b")], carets(1), carets(2)))
    restore(text, history.undo)
    history.modified?.should be_false
    history.record(commit([edit(text, 1, "x")], carets(1), carets(2)))
    history.modified?.should be_true
    restore(text, history.undo)
    history.modified?.should be_false
  end
end

private class SameGesture
  include Textedit::History::Grouping

  def join?(previous : Textedit::Commit, following : Textedit::Commit, elapsed : Time::Span) : Bool
    previous.gesture == following.gesture && previous.after == following.before
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
JOURNAL_WORK = File.join(Dir.tempdir, "textedit-journal-#{Process.pid}")

private def journal_path : String
  File.join(JOURNAL_WORK, "history.jsonl")
end

describe Textedit::History::Journal do
  before_each { FileUtils.mkdir_p(JOURNAL_WORK) }
  after_each { FileUtils.rm_rf(JOURNAL_WORK) }

  it "appends raw edit, undo, and redo commits" do
    text    = buffer("")
    history = Textedit::History::Journal.new(GRAPHEMES)
    history.record(commit([edit(text, 0, "a")], carets(0), carets(1)))
    history.record(commit([edit(text, 1, "b")], carets(1), carets(2)))

    applied = restore(text, history.undo)
    history.record(commit(applied, carets(2), carets(1), origin: Textedit::Origin::Undo))
    applied = restore(text, history.redo)
    history.record(commit(applied, carets(1), carets(2), origin: Textedit::Origin::Redo))

    history.entries.map(&.kind).should eq([Textedit::History::Journal::Kind::Commit] * 4)
    history.entries.map { |entry| entry.commit.not_nil!.origin }.should eq([
      Textedit::Origin::User, Textedit::Origin::User, Textedit::Origin::Undo, Textedit::Origin::Redo,
    ])
    text.text.should eq("ab")
  end

  it "round trips text, carets, grouping, and save points" do
    path    = journal_path
    text    = buffer("")
    history = Textedit::History::Journal.open(GRAPHEMES, path)
    history.record(commit([edit(text, 0, "é")], carets(0), carets(1), typing))
    history.record(commit([edit(text, 1, "👍")], carets(1), carets(2), typing))
    history.mark_saved
    original = history.entries.first.commit

    loaded = Textedit::History::Journal.open(GRAPHEMES, path)
    loaded.entries.size.should eq(3)
    loaded.entries[1].grouped.should be_true
    loaded.entries.first.commit.should eq(original)
    loaded.current.commit.not_nil!.changes.size.should eq(2)
    loaded.modified?.should be_false
  end

  it "replays branches and explicit redo choices" do
    path    = journal_path
    text    = buffer("")
    history = Textedit::History::Journal.open(GRAPHEMES, path)
    history.record(commit([edit(text, 0, "a")], carets(0), carets(1)))
    history.record(commit([edit(text, 1, "b")], carets(1), carets(2)))
    history.mark_saved

    applied = restore(text, history.undo)
    history.record(commit(applied, carets(2), carets(1), origin: Textedit::Origin::Undo))
    alternate = history.current.children.first
    history.record(commit([edit(text, 1, "x")], carets(1), carets(2)))
    applied = restore(text, history.undo)
    history.record(commit(applied, carets(2), carets(1), origin: Textedit::Origin::Undo))
    history.choose(alternate).should be_true

    loaded = Textedit::History::Journal.open(GRAPHEMES, path)
    loaded.current.children.size.should eq(2)
    restore(text, loaded.redo)
    text.text.should eq("ab")
    loaded.modified?.should be_false
  end

  it "appends a clear marker without deleting earlier events" do
    path    = journal_path
    text    = buffer("")
    history = Textedit::History::Journal.open(GRAPHEMES, path)
    history.record(commit([edit(text, 0, "a")], carets(0), carets(1)))
    history.clear
    history.entries.size.should eq(2)
    history.can_undo?.should be_false

    loaded = Textedit::History::Journal.open(GRAPHEMES, path)
    loaded.entries.size.should eq(2)
    loaded.can_undo?.should be_false
    loaded.modified?.should be_false
  end

  it "discards only an incomplete trailing event" do
    path    = journal_path
    text    = buffer("")
    history = Textedit::History::Journal.open(GRAPHEMES, path)
    history.record(commit([edit(text, 0, "é")], carets(0), carets(1)))
    File.open(path, "a") { |file| file << %({"v":1) }

    loaded = Textedit::History::Journal.open(GRAPHEMES, path)
    loaded.entries.size.should eq(1)
    File.read(path).ends_with?('\n').should be_true
    loaded.record(commit([edit(text, 1, "b")], carets(1), carets(2)))
    Textedit::History::Journal.open(GRAPHEMES, path).entries.size.should eq(2)
  end

  it "rejects a malformed complete event without truncating it" do
    path    = journal_path
    text    = buffer("")
    history = Textedit::History::Journal.open(GRAPHEMES, path)
    history.record(commit([edit(text, 0, "a")], carets(0), carets(1)))
    File.open(path, "a") { |file| file << "{}\n" }

    expect_raises(ArgumentError, /line 2/) { Textedit::History::Journal.open(GRAPHEMES, path) }
    File.read(path).ends_with?("{}\n").should be_true
  end

  it "works through document undo and redo after reopening" do
    path    = journal_path
    history = Textedit::History::Journal.open(GRAPHEMES, path)
    first   = editor("", history: history)
    first.insert("a")
    first.undo.should be_true
    first.value.should eq("")

    second = editor("", history: Textedit::History::Journal.open(GRAPHEMES, path))
    second.redo.should be_true
    second.value.should eq("a")
  end
end
