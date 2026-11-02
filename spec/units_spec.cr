# spec/units_spec.cr
require "./spec_helper"

describe Textedit::Units do
  it "counts a line in every unit and maps unit offsets back to clusters" do
    row = line("aé👍🏽x")
    row.units(Textedit::Units::Clusters).should eq(4)
    row.units(Textedit::Units::Bytes).should eq(12)
    row.units(Textedit::Units::CodePoints).should eq(5)
    row.units(Textedit::Units::Utf16).should eq(7)
    row.units(Textedit::Units::Utf16, 2, 3).should eq(4)
    row.column_for(3, Textedit::Units::Utf16).should eq(2)
    row.column_for(6, Textedit::Units::Utf16).should eq(3)
    row.column_for(4, Textedit::Units::Utf16).should eq(2)
    row.column_for(3, Textedit::Units::Bytes).should eq(2)
    row.column_for(99, Textedit::Units::CodePoints).should eq(4)
  end

  it "converts offsets to points and back through the buffer" do
    text = buffer("ab\n👍🏽c")
    text.point(4, Textedit::Units::Utf16).should eq(Textedit::Point.new(1, 4))
    text.point(4, Textedit::Units::Bytes).should eq(Textedit::Point.new(1, 8))
    text.offset_at(Textedit::Point.new(1, 4), Textedit::Units::Utf16).should eq(4)
    text.offset_at(Textedit::Point.new(9, 0), Textedit::Units::Utf16).should eq(3)
    text.measure("👍🏽\nx", Textedit::Units::Clusters).should eq(3)
  end
end

describe Textedit::Change do
  it "describes where it starts and where it ended before and after, in any unit" do
    text  = buffer("ab\ncd")
    found = text.replace(1...4, "é\n👍🏽\nxy")
    found.start_point(text, Textedit::Units::Utf16).should eq(Textedit::Point.new(0, 1))
    found.old_end_point(text, Textedit::Units::Utf16).should eq(Textedit::Point.new(1, 1))
    found.new_end_point(text, Textedit::Units::Utf16).should eq(Textedit::Point.new(2, 2))
    found.new_end_point(text, Textedit::Units::Bytes).should eq(Textedit::Point.new(2, 2))
    single = text.replace(0...0, "é")
    single.new_end_point(text, Textedit::Units::Bytes).should eq(Textedit::Point.new(0, 2))
  end
end

describe Textedit::Decorations do
  it "follows edits without growing at its edges and is replaced per source" do
    text    = editor("one two three")
    found   = Textedit::Decorations.new(text.document)
    changes = 0
    found.listen { changes += 1 }
    found.replace("lsp", [Textedit::Decoration.new(4...7, "error", "bad"), Textedit::Decoration.new(8...8, "hint")])
    found.replace("spell", [Textedit::Decoration.new(0...3, "warning")])
    found.entries.map(&.range).should eq([0...3, 4...7, 8...8])
    text.move(4)
    text.insert("XX")
    text.move(9)
    text.insert("Y")
    found.entries.map(&.range).should eq([0...3, 6...9, 11...11])
    found.at(7).map(&.message).should eq(["bad"])
    found.between(0, 5).map(&.kind).should eq(["warning"])
    found.between(11, 11).map(&.kind).should eq(["hint"])
    found.replace("lsp", [] of Textedit::Decoration)
    found.entries.map(&.source).should eq(["spell"])
    changes.should eq(3)
  end
end

describe "cluster marks" do
  it "stores no boundary table for an ASCII line and maps columns to bytes directly" do
    row = line("def run(x)")
    row.ascii?.should be_true
    row.size.should eq(10)
    row.byte_at(4).should eq(4)
    row.column_at(4).should eq(4)
    row.boundary(7).should eq(7)
    row.cluster(0).should eq("d")
    row.slice(4, 7).should eq("run")
    row.units(Textedit::Units::Utf16, 0, 10).should eq(10)
    row.column_for(4, Textedit::Units::Utf16).should eq(4)
  end

  it "keeps a boundary table once a line needs one" do
    row = line("héllo 👍")
    row.ascii?.should be_false
    row.size.should eq(7)
    row.byte_at(1).should eq(1)
    row.byte_at(2).should eq(3)
    row.cluster(6).should eq("👍")
    row.units(Textedit::Units::Utf16, 0, 7).should eq(8)
  end

  it "agrees on both paths for the same columns" do
    plain = line("abcdef")
    mixed = line("abcdéf")
    (0..6).each { |column| plain.byte_at(column).should eq(column) }
    (0..4).each { |column| mixed.byte_at(column).should eq(column) }
    mixed.byte_at(5).should eq(6)
  end
end
