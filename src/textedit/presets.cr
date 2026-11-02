# src/textedit/presets.cr
module Textedit
  class Field < View
    alias Command = Motion | Selection | Deletion | Copy | Clip | UndoRedo | Recall

    include Typing
    include Deleting
    include Selecting
    include Copying
    include Pasting
    include Undoing
    include Recalling
  end

  class Area < View
    alias Command = Motion | Selection | Carets | Deletion | Whitespace | Copy | Clip | UndoRedo

    include Typing
    include Deleting
    include Spacing
    include Selecting
    include Multicaret
    include Copying
    include Pasting
    include Undoing

    def self.defaults
      {filter: MultiLine.new}
    end
  end

  class Reader < View
    alias Command = Motion | Selection | Carets | Copy

    include Selecting
    include Multicaret
    include Copying
    include Finding
    include Folding

    def self.defaults
      {filter: MultiLine.new, history: nil}
    end
  end

  class Editor < View
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

    def self.defaults
      {filter: MultiLine.new}
    end
  end
end
