# src/textedit/features/finding.cr
module Textedit
  module Finding
    def find(search : Search, backward : Bool = false, from : Int32? = nil) : Range(Int32, Int32)?
      lead  = primary_caret
      start = from || (lead.empty? ? lead.head : lead.start + 1)
      found = backward ? search.previous(@buffer, from || lead.start) : search.next(@buffer, start)
      select_range(found.begin, found.end) if found
      found
    end

    def add_caret_at_every_match(search : Search) : Bool
      found = search.matches(@buffer)
      return false if found.empty?

      seat(found.map { |range| Caret.new(range.begin, range.end) }, found.size - 1)
      true
    end
  end
end
