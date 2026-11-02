# src/textedit/listener.cr
module Textedit
  module Listener
    def applied(document : Document, change : Change) : Nil
    end

    def edited(document : Document, changes : Array(Change)) : Nil
    end

    def moved(view : View) : Nil
    end
  end

  module Follower
    abstract def follow(change : Change) : Nil
  end
end
