# src/textedit/macro_log.cr
module Textedit
  class MacroLog(C)
    getter entries : Array(C | String)
    getter? recording : Bool
    getter? replaying : Bool

    def initialize
      @entries   = Array(C | String).new
      @recording = false
      @replaying = false
    end

    def record : Nil
      return if @replaying

      @entries   = Array(C | String).new
      @recording = true
    end

    def stop : Nil
      @recording = false
    end

    def empty? : Bool
      @entries.empty?
    end

    def size : Int32
      @entries.size
    end

    def push(entry : C | String) : Nil
      return unless @recording && !@replaying

      @entries << entry
    end

    protected def replaying=(value : Bool) : Bool
      @replaying = value
    end
  end
end
