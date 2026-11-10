# src/textedit/features/recalling.cr
module Textedit
  # Commands that browse previously submitted single-line input.
  enum Recall
    Back
    Forward

    # Returns `true`; recall commands replace the view's text.
    def edits? : Bool
      true
    end
  end

  # Connects a view to a lazily created `Recollection`.
  module Recalling
    property(recollection : ::Textedit::Recollection) { ::Textedit::Recollection.new }

    # Replaces the text with an older entry, newer entry, or saved draft.
    def run(command : Recall, selecting : Bool = false) : Bool
      return false unless enter(command)

      found = case command
              in .back?    then recollection.back(value)
              in .forward? then recollection.forward
              end
      return false unless found

      self.value = found
      true
    end
  end
end
