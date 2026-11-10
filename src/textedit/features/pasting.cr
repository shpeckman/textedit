# src/textedit/features/pasting.cr
module Textedit
  # Commands that cut and paste clipboard text or cycle paste history.
  enum Clip
    Cut
    Paste
    PastePrevious

    # Returns `true`; clipboard editing commands may change text.
    def edits? : Bool
      true
    end
  end

  # Cuts selections, pastes clipboard text, and cycles earlier clipboard entries.
  #
  # Include `Typing` and `Copying` before this module.
  module Pasting
    macro included
      {% raise "#{@type} must include Textedit::Typing before Textedit::Pasting" unless @type < ::Textedit::Typing %}
      {% raise "#{@type} must include Textedit::Copying before Textedit::Pasting" unless @type < ::Textedit::Copying %}
    end

    # :nodoc:
    record Session, ranges : Array(Range(Int32, Int32)), revision : Int32,
      carets : Array(Caret), primary : Int32, index : Int32

    @paste_session : ::Textedit::Pasting::Session? = nil
    @paste_pending : Bool = false

    # Runs a clipboard command and returns whether the command applied.
    def run(command : Clip, selecting : Bool = false) : Bool
      return false unless enter(command)

      case command
      in .cut?            then cut
      in .paste?          then paste_clipboard
      in .paste_previous? then return paste_previous
      end
      true
    end

    private def commanded(command) : Nil
      super
      @paste_session = nil unless command.is_a?(Clip) && command.paste_previous?
    end

    private def typed(text : String) : Nil
      super
      @paste_session = nil
    end

    private def pasted(ranges : Array(Range(Int32, Int32)), size : Int32, pieces : Array(String)?) : Nil
      super
      @paste_session = nil
      remember_paste(ranges, size, pieces, 0) if pieces
    end

    private def cut : Nil
      return if !@copyable || @carets.all?(&.empty?)

      copy
      @document.apply(self, Gesture::Other) { |caret, _index| caret.empty? ? nil : Stroke.new(caret.range, "") }
    end

    private def paste_clipboard : Nil
      @clipboard.read do |text|
        text.try { |found| paste(found) }
        nil
      end
    end

    private def paste_previous : Bool
      session = @paste_session || return false
      history = @clipboard.as?(ClipboardHistory) || return false
      return false if @paste_pending || session.revision != @buffer.revision
      return false unless session.carets == @carets && session.primary == @primary

      index = session.index + 1
      return false if index >= history.size

      @paste_pending = true
      history.read(index) do |text|
        @paste_pending = false
        cycle_paste(session, text, index) if text
        nil
      end
      true
    end

    private def cycle_paste(session : Session, text : String, index : Int32) : Nil
      return unless @paste_session == session && session.revision == @buffer.revision
      return unless session.carets == @carets && session.primary == @primary

      filter = @document.filter
      normal = LineEnding.normalize(text)
      parts  = normal.chomp.split('\n')
      pieces = multiple? && parts.size == @carets.size ? parts.map { |part| filter.filter(part) } : Array.new(@carets.size, filter.filter(normal))
      size   = @buffer.size
      if @document.apply(self, Gesture::Other) { |_caret, at| Stroke.new(session.ranges[at], pieces[at]) }
        remember_paste(session.ranges, size, pieces, index)
      end
    end

    private def remember_paste(ranges : Array(Range(Int32, Int32)), size : Int32,
                               pieces : Array(String), index : Int32) : Nil
      @paste_session = nil
      return unless @carets.size == ranges.size

      delta = 0
      fresh = ranges.map_with_index do |range, at|
        start = range.begin + delta
        stop  = @carets[at].head
        delta += stop - start - range.size
        start...stop
      end
      return unless @buffer.size - size == delta
      return unless fresh.each_with_index.all? { |range, at| @buffer.slice_text(range) == pieces[at] }

      @paste_session = Session.new(fresh, @buffer.revision, @carets.dup, @primary, index)
    end
  end
end
