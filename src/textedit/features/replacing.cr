# src/textedit/features/replacing.cr
module Textedit
  # Replaces search matches, including regular-expression capture expansion.
  module Replacing
    # Replaces *match* only when it is still the primary selection and a known match.
    def replace_match(search : Search, match : Range(Int32, Int32), template : String) : Bool
      return false unless match == selection && search.index(@buffer, match)

      revise([Edit.new(match, @document.prepare(search.expand(@buffer, match, template)))])
    end

    # Replaces every match as one undo step and returns the replacement count.
    def replace_all(search : Search, template : String) : Int32
      return 0 unless @document.admits?

      found = search.matches(@buffer)
      return 0 if found.empty?

      revise(found.map { |range| Edit.new(range, @document.prepare(search.expand(@buffer, range, template))) }) ? found.size : 0
    end
  end
end
