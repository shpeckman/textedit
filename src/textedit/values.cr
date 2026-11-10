# src/textedit/values.cr
module Textedit
  # A zero-based line and grapheme-cluster column in a buffer.
  record Position, line : Int32, column : Int32

  # A zero-based display cell, with its column before its row.
  record Cell, column : Int32, row : Int32

  # A replacement of an exclusive grapheme-cluster range with new text.
  record Edit, range : Range(Int32, Int32), text : String

  # A zero-based line and column whose column is interpreted using a `Units` value.
  record Point, line : Int32, column : Int32

  # Units used when converting between text offsets and external positions.
  enum Units
    Bytes
    Utf16
    CodePoints
    Clusters

    # :nodoc:
    def width(char : Char) : Int32
      case self
      in Bytes      then char.bytesize
      in Utf16      then char.ord > 0xFFFF ? 2 : 1
      in CodePoints then 1
      in Clusters   then 1
      end
    end
  end

  # Controls which side of inserted text a mark follows.
  enum Gravity
    Left
    Right
  end

  # The editing gesture used by history to group commits.
  enum Gesture
    Typing
    Deleting
    Other
  end

  # Identifies the source of an edit for constraints and history.
  enum Origin
    User
    Code
    Undo
    Redo
  end

  # Editing conventions for indentation, tab width, and line comments.
  record Style, indent : String = "  ", tab_size : Int32 = 4, comment : String? = nil

  # Line-ending convention used when importing and exporting text.
  enum LineEnding
    LF
    CRLF
    CR

    # Returns the byte sequence for this line ending.
    def sequence : String
      case self
      in LF   then "\n"
      in CRLF then "\r\n"
      in CR   then "\r"
      end
    end

    # Returns the predominant line ending in *text*, or `LF` when none is present.
    def self.detect(text : String) : LineEnding
      return LF unless text.includes?('\r')

      pairs   = text.scan("\r\n").size
      singles = text.count('\r') - pairs
      feeds   = text.count('\n') - pairs
      return CRLF if pairs >= singles && pairs >= feeds
      singles > feeds ? CR : LF
    end

    # :nodoc:
    def self.detect_in(buffer : Buffer) : LineEnding
      return LineEnding::LF if buffer.line_count < 2

      first = buffer.line(0)
      first.byte(first.bytesize - 1) == 0x0d ? LineEnding::CRLF : LineEnding::LF
    end

    # :nodoc:
    def self.normalize(text : String) : String
      return text unless text.includes?('\r')

      text.gsub("\r\n", "\n").tr("\r", "\n")
    end
  end

  # :nodoc:
  record Stroke, range : Range(Int32, Int32), text : String, anchor : Int32? = nil, head : Int32? = nil
end
