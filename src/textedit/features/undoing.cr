# src/textedit/features/undoing.cr
module Textedit
  # Commands that move backward or forward through document history.
  enum UndoRedo
    Undo
    Redo

    # Returns `true`; undo and redo change text.
    def edits? : Bool
      true
    end
  end

  # Exposes document undo and redo as view commands.
  module Undoing
    # Runs an undo or redo command and returns whether a step was applied.
    def run(command : UndoRedo, selecting : Bool = false) : Bool
      return false unless enter(command)

      case command
      in .undo? then undo
      in .redo? then redo
      end
    end

    # Undoes one step and restores carets recorded for this view when available.
    def undo : Bool
      @document.undo(self)
    end

    # Redoes one step and restores carets recorded for this view when available.
    def redo : Bool
      @document.redo(self)
    end
  end
end
