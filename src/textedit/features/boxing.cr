# src/textedit/features/boxing.cr
module Textedit
  enum Box
    Up
    Down
    Left
    Right

    def edits? : Bool
      false
    end
  end

  module Boxing
    alias Corners = {Int32, Int32, Int32, Int32}

    getter box : ::Textedit::Boxing::Corners? = nil

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

    def start_box(row : Int32, column : Int32) : Nil
      @box = {row, column, row, column}
    end

    def select_box(anchor_row : Int32, anchor_column : Int32, head_row : Int32, head_column : Int32) : Nil
      @box = {anchor_row, anchor_column, head_row, head_column}
      low  = Math.min(anchor_row, head_row)
      high = Math.max(anchor_row, head_row)
      list = (low..high).map do |row|
        Caret.new(@layout.offset_in(row, anchor_column), @layout.offset_in(row, head_column))
      end
      place_carets(list, head_row - low)
    end

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
