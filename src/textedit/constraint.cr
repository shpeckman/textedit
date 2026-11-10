# src/textedit/constraint.cr
module Textedit
  # Controls whether edits are admitted and how many clusters a document may hold.
  module Constraint
    # :nodoc:
    def self.capacity(constraints : Array(Constraint)) : Int32?
      limit = nil.as(Int32?)
      constraints.each do |constraint|
        if max = constraint.capacity
          limit = limit ? Math.min(limit, max) : max
        end
      end
      limit
    end

    # Returns whether an edit from *origin* may proceed; defaults to `true`.
    def admits?(origin : Origin) : Bool
      true
    end

    # Returns a maximum document size in clusters, or `nil` for no limit.
    def capacity : Int32?
      nil
    end
  end

  # Toggleable constraint that admits only `Code` edits while active.
  class ReadOnly
    include Constraint

    property? active : Bool

    # Creates a read-only constraint; it starts active by default.
    def initialize(@active : Bool = true)
    end

    def admits?(origin : Origin) : Bool
      !@active || origin.code?
    end
  end

  # Constraint that limits a document to a nonnegative number of grapheme clusters.
  struct MaxLength
    include Constraint

    getter max : Int32

    # Creates a limit, clamping negative *max* values to zero.
    def initialize(max : Int32)
      @max = Math.max(max, 0)
    end

    def capacity : Int32?
      @max
    end
  end
end
