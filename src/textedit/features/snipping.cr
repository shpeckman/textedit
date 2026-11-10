# src/textedit/features/snipping.cr
module Textedit
  # Inserts LSP-style snippets and navigates their tabstops.
  module Snipping
    # Replaces the primary selection with a snippet and selects its first stop.
    #
    # Returns `nil` when the edit is refused or the snippet has no stops.
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
