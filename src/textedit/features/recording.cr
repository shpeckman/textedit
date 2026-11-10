# src/textedit/features/recording.cr
module Textedit
  # Records commands and inserted text into a `MacroLog` for replay.
  #
  # Include `Typing` before this module. *C* is the view's complete command union.
  module Recording(C)
    macro included
      {% raise "#{@type} must include Textedit::Typing before Textedit::Recording" unless @type < ::Textedit::Typing %}
    end

    property macros : ::Textedit::MacroLog(C) = ::Textedit::MacroLog(C).new

    # Starts a new recording, replacing the previous log.
    def record : Nil
      @macros.record
    end

    # Stops recording without clearing the log.
    def stop : Nil
      @macros.stop
    end

    # Replays the log *times* times, grouping each pass into one undo step.
    def replay(times : Int32 = 1) : Bool
      log = @macros
      return false if log.empty? || log.replaying?

      log.replaying = true
      applied = false
      begin
        times.times do
          transaction do
            log.entries.each do |entry|
              applied = (entry.is_a?(String) ? insert(entry) : run(entry)) || applied
            end
          end
        end
      ensure
        log.replaying = false
      end
      applied
    end

    private def commanded(command) : Nil
      super
      @macros.push(command)
    end

    private def typed(text : String) : Nil
      super
      @macros.push(text)
    end
  end
end
