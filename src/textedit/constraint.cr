# src/textedit/constraint.cr
module Textedit
  module Constraint
    def self.capacity(constraints : Array(Constraint)) : Int32?
      limit = nil.as(Int32?)
      constraints.each do |constraint|
        if max = constraint.capacity
          limit = limit ? Math.min(limit, max) : max
        end
      end
      limit
    end

    def admits?(origin : Origin) : Bool
      true
    end

    def capacity : Int32?
      nil
    end
  end

  class ReadOnly
    include Constraint

    property? active : Bool

    def initialize(@active : Bool = true)
    end

    def admits?(origin : Origin) : Bool
      !@active || origin.code?
    end
  end

  struct MaxLength
    include Constraint

    getter max : Int32

    def initialize(max : Int32)
      @max = Math.max(max, 0)
    end

    def capacity : Int32?
      @max
    end
  end
end
