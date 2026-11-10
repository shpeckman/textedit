# src/textedit/snippet.cr
module Textedit
  # Live snippet tabstops held by document marks.
  class Snippet
    # One tabstop span in a parsed template, using grapheme-cluster offsets.
    record Span, index : Int32, from : Int32, to : Int32

    # Plain snippet text and the tabstop spans within it.
    record Template, text : String, spans : Array(Span)

    # :nodoc:
    FINAL = 0

    getter document : Document
    # :nodoc:
    getter stops    : Array(Array({Mark, Mark}))
    # Zero-based index of the current stop group.
    getter index    : Int32

    # Parses LSP-style snippet syntax into plain text and grapheme-cluster stop spans.
    def self.parse(source : String, graphemes : Graphemes) : Template
      Parser.new(source).run(graphemes)
    end

    # :nodoc:
    def initialize(@document : Document, start : Int32, template : Template)
      groups = {} of Int32 => Array(Span)
      template.spans.each { |span| (groups[span.index] ||= [] of Span) << span }
      order = groups.keys.sort_by { |stop| stop == FINAL ? Int32::MAX : stop }

      @stops = order.map do |stop|
        groups[stop].map do |span|
          {@document.mark(start + span.from, Gravity::Left), @document.mark(start + span.to, Gravity::Right)}
        end
      end
      @index = -1
    end

    def size : Int32
      @stops.size
    end

    def empty? : Bool
      @stops.empty?
    end

    # Returns whether a tabstop remains active.
    def active? : Bool
      @index < @stops.size && !@stops.empty?
    end

    # :nodoc:
    def carets : Array(Caret)
      return [] of Caret unless 0 <= @index < @stops.size

      @stops[@index].map { |(from, to)| Caret.new(from.offset, Math.max(to.offset, from.offset)) }
    end

    # Selects the next stop in *view*, closing after the final stop and returning `false`.
    def next_stop(view : View) : Bool
      seek(view, @index + 1)
    end

    # Selects the previous stop in *view* and returns whether one existed.
    def previous_stop(view : View) : Bool
      return false if @index <= 0

      seek(view, @index - 1)
    end

    # Releases all tabstop marks and deactivates the snippet.
    def close : Nil
      @stops.each { |group| group.each { |(from, to)| @document.unmark(from); @document.unmark(to) } }
      @stops = [] of Array({Mark, Mark})
      @index = 0
    end

    private def seek(view : View, target : Int32) : Bool
      return false if @stops.empty?

      if target >= @stops.size
        close
        return false
      end

      @index = target
      placed = carets
      return false if placed.empty?

      view.place_carets(placed)
      true
    end

    private class Parser
      @source : String
      @text   : String::Builder
      @spans  : Array({Int32, Int32, Int32})
      @at     : Int32

      def initialize(@source : String)
        @text  = String::Builder.new
        @spans = [] of {Int32, Int32, Int32}
        @at    = 0
      end

      def run(graphemes : Graphemes) : Template
        reader = Char::Reader.new(@source)
        while reader.has_next?
          char = reader.current_char
          case char
          when '\\'
            reader.next_char
            if reader.has_next?
              emit(reader.current_char.to_s)
              reader.next_char
            else
              emit("\\")
            end
          when '$'
            reader = tabstop(reader)
          else
            emit(char.to_s)
            reader.next_char
          end
        end

        text  = @text.to_s
        marks = graphemes.boundaries(text)
        Template.new(text, @spans.map { |(index, from, to)| Span.new(index, column(marks, from), column(marks, to)) })
      end

      private def column(marks : Array(Int32), byte : Int32) : Int32
        found = marks.bsearch_index { |mark| mark >= byte } || marks.size - 1
        found.clamp(0, marks.size - 1)
      end

      private def emit(text : String) : Nil
        @text << text
        @at += text.bytesize
      end

      private def tabstop(reader : Char::Reader) : Char::Reader
        reader.next_char
        unless reader.has_next?
          emit("$")
          return reader
        end

        if reader.current_char == '{'
          reader.next_char
          braced(reader)
        else
          plain(reader)
        end
      end

      private def plain(reader : Char::Reader) : Char::Reader
        digits = String::Builder.new
        while reader.has_next? && reader.current_char.ascii_number?
          digits << reader.current_char
          reader.next_char
        end

        text = digits.to_s
        if text.empty?
          name = String::Builder.new
          while reader.has_next? && (reader.current_char.ascii_alphanumeric? || reader.current_char == '_')
            name << reader.current_char
            reader.next_char
          end
          emit("$") if name.to_s.empty?
          return reader
        end

        @spans << {text.to_i, @at, @at}
        reader
      end

      private def braced(reader : Char::Reader) : Char::Reader
        digits = String::Builder.new
        while reader.has_next? && reader.current_char.ascii_number?
          digits << reader.current_char
          reader.next_char
        end
        numeric = digits.to_s

        unless numeric.empty?
          return finish(reader, numeric.to_i) if reader.has_next? && reader.current_char == '}'
          return placeholder(reader, numeric.to_i) if reader.has_next? && reader.current_char == ':'
          return choice(reader, numeric.to_i) if reader.has_next? && reader.current_char == '|'
        end

        skip(reader)
      end

      private def finish(reader : Char::Reader, index : Int32) : Char::Reader
        @spans << {index, @at, @at}
        reader.next_char
        reader
      end

      private def placeholder(reader : Char::Reader, index : Int32) : Char::Reader
        reader.next_char
        from  = @at
        depth = 0
        while reader.has_next?
          char = reader.current_char
          break if char == '}' && depth == 0

          depth += 1 if char == '{'
          depth -= 1 if char == '}'
          emit(char.to_s)
          reader.next_char
        end
        reader.next_char if reader.has_next?

        @spans << {index, from, @at}
        reader
      end

      private def choice(reader : Char::Reader, index : Int32) : Char::Reader
        reader.next_char
        from  = @at
        first = true
        while reader.has_next? && reader.current_char != '|'
          emit(reader.current_char.to_s) if first && reader.current_char != ','
          first = false if reader.current_char == ','
          reader.next_char
        end
        reader.next_char if reader.has_next?
        reader.next_char if reader.has_next? && reader.current_char == '}'

        @spans << {index, from, @at}
        reader
      end

      private def skip(reader : Char::Reader) : Char::Reader
        depth   = 0
        default = nil.as(String?)
        while reader.has_next?
          char = reader.current_char
          break if char == '}' && depth == 0

          if char == ':' && depth == 0 && default.nil?
            default = ""
            reader.next_char
            next
          end

          depth += 1 if char == '{'
          depth -= 1 if char == '}'
          default = "#{default}#{char}" if default
          reader.next_char
        end
        reader.next_char if reader.has_next?

        emit(default) if default
        reader
      end
    end
  end
end
