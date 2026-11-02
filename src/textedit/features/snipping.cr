# src/textedit/features/snipping.cr
module Textedit
  module Snipping
    def insert_snippet(source : String) : Snippet?
      template = Snippet.parse(@document.prepare(source), @graphemes)
      start    = primary_caret.start
      return nil unless revise([Edit.new(primary_caret.range, template.text)], [Caret.at(start + count(template.text))])
      return nil if template.spans.empty?

      snippet = Snippet.new(@document, start, template)
      snippet.next_stop(self)
      snippet
    end
  end
end
