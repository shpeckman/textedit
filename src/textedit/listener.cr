# src/textedit/listener.cr
module Textedit
  # Receives ordered document and caret notifications; every method defaults to a no-op.
  module Listener
    # Runs after each change lands and before carets are seated.
    def applied(document : Document, change : Change) : Nil
    end

    # Runs once after an edit or transaction with all changes in application order.
    def edited(document : Document, changes : Array(Change)) : Nil
    end

    # Runs after a view's carets change, including after edits.
    def moved(view : View) : Nil
    end
  end

  # Receives each change before views and listeners, for derived document state.
  module Follower
    # Updates derived state for one applied *change*.
    abstract def follow(change : Change) : Nil
  end
end
