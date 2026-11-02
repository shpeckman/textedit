# spec/annotation_spec.cr
require "./spec_helper"

private def hint(offset : Int32, text : String, placement = Textedit::Placement::After) : Textedit::Annotation
  Textedit::Annotation.new(offset, text, placement, "type")
end

describe Textedit::Annotations do
  it "replaces every annotation from the same source and keeps them sorted" do
    text  = editor("let x = 1")
    notes = Textedit::Annotations.new(text.document)
    notes.replace("lsp", [hint(5, ": Int32"), hint(0, "let")])
    notes.entries.map(&.offset).should eq([0, 5])
    notes.entries.map(&.source).should eq(["lsp", "lsp"])

    notes.replace("lsp", [hint(5, ": Int64")])
    notes.entries.size.should eq(1)
    notes.entries.first.text.should eq(": Int64")

    notes.replace("blame", [hint(0, "you, 2 days ago", Textedit::Placement::RowEnd)])
    notes.entries.size.should eq(2)

    notes.replace("lsp", [] of Textedit::Annotation)
    notes.entries.map(&.source).should eq(["blame"])
  end

  it "moves with the text like a mark does" do
    text  = lines("one\ntwo")
    notes = Textedit::Annotations.new(text.document)
    notes.replace("lsp", [hint(3, "end"), hint(4, "start")])
    text.run(Textedit::Motion::DocumentStart)
    text.insert("xx")
    notes.entries.map(&.offset).should eq([5, 6])
  end

  it "takes gravity from its placement" do
    text  = editor("ab")
    notes = Textedit::Annotations.new(text.document)
    notes.replace("lsp", [hint(1, "after", Textedit::Placement::After), hint(1, "before", Textedit::Placement::Before)])
    text.select_range(1, 1)
    text.insert("-")

    found = notes.entries.sort_by(&.text)
    found.map { |entry| {entry.text, entry.offset} }.should eq([{"after", 1}, {"before", 2}])
  end

  it "finds annotations by offset, range and line" do
    text  = lines("one\ntwo\nthree")
    notes = Textedit::Annotations.new(text.document)
    notes.replace("lsp", [hint(1, "a"), hint(5, "b"), hint(9, "c")])
    notes.at(5).map(&.text).should eq(["b"])
    notes.between(0, 5).map(&.text).should eq(["a", "b"])
    notes.on(1).map(&.text).should eq(["b"])
    notes.on(2).map(&.text).should eq(["c"])
    notes.on(9).should be_empty
  end

  it "tells its listeners when a source replaces its annotations" do
    text  = lines("one")
    notes = Textedit::Annotations.new(text.document)
    count = 0
    stop  = notes.listen { count += 1 }
    notes.replace("lsp", [hint(0, "a")])
    count.should eq(1)
    notes.replace("lsp", [] of Textedit::Annotation)
    count.should eq(2)
    stop.call
    notes.replace("lsp", [hint(0, "b")])
    count.should eq(2)
  end

  it "stops following the text once closed" do
    text  = lines("one")
    notes = Textedit::Annotations.new(text.document)
    notes.replace("lsp", [hint(2, "a")])
    notes.close
    text.run(Textedit::Motion::DocumentStart)
    text.insert("xx")
    notes.entries.first.offset.should eq(2)
  end

  it "reports its placement" do
    hint(0, "x", Textedit::Placement::Before).before?.should be_true
    hint(0, "x", Textedit::Placement::After).after?.should be_true
    hint(0, "x", Textedit::Placement::RowEnd).row_end?.should be_true
  end
end
