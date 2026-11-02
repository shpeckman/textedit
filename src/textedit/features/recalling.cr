# src/textedit/features/recalling.cr
module Textedit
  enum Recall
    Back
    Forward

    def edits? : Bool
      true
    end
  end

  module Recalling
    property(recollection : ::Textedit::Recollection) { ::Textedit::Recollection.new }

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
