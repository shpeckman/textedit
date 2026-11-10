# src/textedit/features/spacing.cr
module Textedit
  # Commands that insert line breaks and indentation.
  enum Whitespace
    NewLine
    Tab

    # Returns `true`; whitespace commands change text.
    def edits? : Bool
      true
    end
  end

  # Inserts newlines and style-defined indentation, with optional automatic indentation.
  module Spacing
    macro included
      {% raise "#{@type} must include Textedit::Spacing before Textedit::LineEditing" if @type < ::Textedit::LineEditing %}
    end

    property? auto_indent : Bool = false

    # Runs a whitespace command and returns whether it applied.
    def run(command : Whitespace, selecting : Bool = false) : Bool
      return false unless enter(command)

      case command
      in .new_line? then new_line
      in .tab?
        tab
        true
      end
    end

    private def new_line : Bool
      @document.apply(self, Gesture::Other) do |caret, _index|
        if @auto_indent
          found = @buffer.position(caret.start)
          line  = @buffer.line(found.line)
          lead  = 0
          while lead < found.column && lead < line.size && @graphemes.kind(line.bytes(lead)).space?
            lead += 1
          end
          Stroke.new(caret.range, Buffer::BREAK + line.slice(0, lead))
        else
          Stroke.new(caret.range, Buffer::BREAK)
        end
      end
    end

    private def tab : Bool
      put(@document.prepare(@document.style.indent))
    end
  end
end
