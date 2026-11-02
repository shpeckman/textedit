# src/textedit/features/replacing.cr
module Textedit
  module Replacing
    def replace_match(search : Search, match : Range(Int32, Int32), template : String) : Bool
      return false unless match == selection && search.index(@buffer, match)

      revise([Edit.new(match, @document.prepare(search.expand(@buffer, match, template)))])
    end

    def replace_all(search : Search, template : String) : Int32
      return 0 unless @document.admits?

      found = search.matches(@buffer)
      return 0 if found.empty?

      revise(found.map { |range| Edit.new(range, @document.prepare(search.expand(@buffer, range, template))) }) ? found.size : 0
    end
  end
end
