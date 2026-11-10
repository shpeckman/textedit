# src/textedit/features/boxing.cr
module Textedit
  # Commands that grow a rectangular selection from its head.
  enum Box
    Up
    Down
    Left
    Right

    # Returns `false`; box-selection commands never change text.
    def edits? : Bool
      false
    end
  end

  # Rectangular selection over layout rows and display columns.
  module Boxing
    # Anchor row, anchor column, head row, and head column of a box selection.
    alias Corners = {Int32, Int32, Int32, Int32}

    getter box : ::Textedit::Boxing::Corners? = nil

    # Grows the box in the requested direction.
    def run(command : Box, selecting : Bool = false) : Bool
      return false unless enter(command)

      case command
      in .up?    then box_step(-1, 0)
      in .down?  then box_step(1, 0)
      in .left?  then box_step(0, -1)
      in .right? then box_step(0, 1)
      end
      true
    end

    # Starts a box with both corners at a display cell.
    def start_box(row : Int32, column : Int32) : Nil
      @box = {row, column, row, column}
    end

    # Selects a rectangle between two display cells.
    def select_box(anchor_row : Int32, anchor_column : Int32, head_row : Int32, head_column : Int32) : Nil
      @box = {anchor_row, anchor_column, head_row, head_column}
      low  = Math.min(anchor_row, head_row)
      high = Math.max(anchor_row, head_row)
      list = (low..high).map do |row|
        Caret.new(@layout.offset_in(row, anchor_column), @layout.offset_in(row, head_column))
      end
      place_carets(list, head_row - low)
    end

    # Clears the stored box corners without changing the carets.
    def clear_box : Nil
      @box = nil
    end

    private def box_step(rows : Int32, columns : Int32) : Nil
      anchor_row, anchor_column, head_row, head_column = @box || begin
        cell = @layout.cell_of(cursor)
        {cell.row, cell.column, cell.row, cell.column}
      end

      head_row    = (head_row + rows).clamp(0, Math.max(@layout.row_count - 1, 0))
      head_column = Math.max(head_column + columns, 0)
      select_box(anchor_row, anchor_column, head_row, head_column)
    end
  end
end
