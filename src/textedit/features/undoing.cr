# src/textedit/features/undoing.cr
module Textedit
  enum UndoRedo
    Undo
    Redo

    def edits? : Bool
      true
    end
  end

  module Undoing
    def run(command : UndoRedo, selecting : Bool = false) : Bool
      return false unless enter(command)

      case command
      in .undo? then undo
      in .redo? then redo
      end
    end

    def undo : Bool
      @document.undo(self)
    end

    def redo : Bool
      @document.redo(self)
    end
  end
end
