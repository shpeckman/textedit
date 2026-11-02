# src/textedit/features/copying.cr
module Textedit
  enum Copy
    Selection

    def edits? : Bool
      false
    end
  end

  module Copying
    property clipboard : ::Textedit::Clipboard = ::Textedit::Register.new
    property selection_clipboard : ::Textedit::Clipboard? = nil
    property? copyable : Bool = true
    property? copy_on_select : Bool = false

    def run(command : Copy, selecting : Bool = false) : Bool
      return false unless enter(command)

      case command
      in .selection? then copy
      end
      true
    end

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
