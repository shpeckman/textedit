# src/textedit/features/copying.cr
module Textedit
  # Commands that copy selections to a clipboard.
  enum Copy
    Selection

    # Returns `false`; copy commands never change text.
    def edits? : Bool
      false
    end
  end

  # Copies nonempty selections, optionally copying automatically after selection.
  module Copying
    property clipboard : ::Textedit::Clipboard = ::Textedit::Register.new
    property selection_clipboard : ::Textedit::Clipboard? = nil
    property? copyable : Bool = true
    property? copy_on_select : Bool = false

    # Copies selected text and returns `true`, including when nothing was copied.
    def run(command : Copy, selecting : Bool = false) : Bool
      return false unless enter(command)

      case command
      in .selection? then copy
      end
      true
    end

    # Copies a nonempty selection when automatic copying is enabled.
    def auto_copy : Nil
      copy(@selection_clipboard || @clipboard) if @copy_on_select && @carets.any? { |caret| !caret.empty? }
    end

    private def selected : Nil
      super
      auto_copy
    end

    private def copy(target : Clipboard = @clipboard) : Nil
      return unless @copyable

      texts = selected_texts
      target.write(texts.join('\n')) unless texts.empty?
    end
  end
end
