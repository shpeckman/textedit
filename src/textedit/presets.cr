# src/textedit/presets.cr
module Textedit
  # Single-line input preset with editing, clipboard, undo, and input recall.
  class Field < View
    # Commands accepted by `Field`.
    alias Command = Motion | Selection | Deletion | Copy | Clip | UndoRedo | Recall

    include Typing
    include Deleting
    include Selecting
    include Copying
    include Pasting
    include Undoing
    include Recalling
  end

  # Multiline input preset with multiple carets, clipboard, and undo.
  class Area < View
    # Commands accepted by `Area`.
    alias Command = Motion | Selection | Carets | Deletion | Whitespace | Copy | Clip | UndoRedo

    include Typing
    include Deleting
    include Spacing
    include Selecting
    include Multicaret
    include Copying
    include Pasting
    include Undoing

    # Returns the multiline document defaults.
    def self.defaults
      {filter: MultiLine.new}
    end
  end

  # Read-only viewing preset with selection, search, folds, and clipboard copying.
  class Reader < View
    # Commands accepted by `Reader`.
    alias Command = Motion | Selection | Carets | Copy

    include Selecting
    include Multicaret
    include Copying
    include Finding
    include Folding

    # Returns multiline defaults with history disabled.
    def self.defaults
      {filter: MultiLine.new, history: nil}
    end
  end

  # Full code-editing preset with line operations, snippets, folds, and macro recording.
  class Editor < View
    # Commands accepted by `Editor`.
    alias Command = Motion | Selection | Carets | Box | Deletion | Whitespace | Lines | Transform | Copy | Clip | UndoRedo

    include Typing
    include Deleting
    include Spacing
    include LineEditing
    include Transforming
    include Selecting
    include Multicaret
    include Boxing
    include Copying
    include Pasting
    include Undoing
    include Finding
    include Replacing
    include Folding
    include Snipping
    include Recording(Command)

    # Returns the multiline document defaults.
    def self.defaults
      {filter: MultiLine.new}
    end
  end
end
