# src/textedit/document.cr
module Textedit
  # Shared text, editing services, marks, listeners, and attached views.
  #
  # All text mutations pass through the document so history, constraints,
  # followers, and other views observe the same ordered changes.
  class Document
    getter graphemes   : Graphemes
    getter buffer      : Buffer
    getter constraints : Array(Constraint)
    getter marks       : Array(Mark)
    getter views       : Array(View)

    property filter      : Filter
    property history     : History?
    property style       : Style
    property line_ending : LineEnding

    @listeners     : Array(Listener)
    @followers     : Array(Follower)
    @depth         : Int32
    @batch         : Array(Change)
    @batch_before  : Array(Caret)
    @batch_primary : Int32
    @batch_view    : View?
    @batch_origin  : Origin?
    @stirred       : Array(View)
    @acting        : View?
    @saved         : Int32

    # Creates a document from text or an existing buffer.
    #
    # String input is normalized to `\n`, filtered, and truncated to the combined
    # constraint capacity. Options configure filtering, history, constraints, and style.
    def initialize(graphemes : Graphemes, text : String | Buffer = "", *,
                   filter      : Filter   = SingleLine.new,
                   history     : History? = History::Linear.new(graphemes),
                   constraints : Array    = [] of Constraint,
                   style       : Style    = Style.new)
      @graphemes   = graphemes
      @filter      = filter
      @history     = history
      @style       = style
      @constraints = constraints.map(&.as(Constraint))

      if text.is_a?(Buffer)
        @line_ending = LineEnding.detect_in(text)
        @buffer      = text
      else
        @line_ending = LineEnding.detect(text)
        prepared     = filter.filter(LineEnding.normalize(text))
        if (max = Constraint.capacity(@constraints)) && (marks = graphemes.boundaries(prepared)).size - 1 > max
          prepared = prepared.byte_slice(0, marks[max])
        end
        @buffer = Buffer.new(graphemes, prepared)
      end

      @marks         = [] of Mark
      @views         = [] of View
      @listeners     = [] of Listener
      @followers     = [] of Follower
      @depth         = 0
      @batch         = [] of Change
      @batch_before  = [] of Caret
      @batch_primary = 0
      @batch_view    = nil
      @batch_origin  = nil
      @stirred       = [] of View
      @acting        = nil
      @saved         = @buffer.revision
      @buffer.on_change { |change| applied(change) }
    end

    # Replaces the constraints and truncates the value when its new capacity is lower.
    def constraints=(list : Array) : Array(Constraint)
      @constraints = list.map(&.as(Constraint))
      max = capacity
      self.value = value if max && length > max
      @constraints
    end

    # Returns whether every constraint admits an edit from *origin*.
    def admits?(origin : Origin = Origin::User) : Bool
      @constraints.all?(&.admits?(origin))
    end

    # Returns the lowest constraint capacity in clusters, or `nil` when unbounded.
    def capacity : Int32?
      Constraint.capacity(@constraints)
    end

    # Registers *listener* and returns a proc that removes it.
    def listen(listener : Listener) : Proc(Nil)
      @listeners << listener
      -> { @listeners.delete(listener); nil }
    end

    # Registers *follower* for each change and returns a proc that removes it.
    def track(follower : Follower) : Proc(Nil)
      @followers << follower
      -> { @followers.delete(follower); nil }
    end

    # Returns the complete text with `\n` line breaks.
    def value : String
      @buffer.text
    end

    # Replaces the complete text as an undoable `Code` edit.
    #
    # Input is filtered, normalized, and limited by capacity. Every attached
    # view's carets follow the replacement.
    def value=(value : String) : String
      assign(value, nil)
    end

    # Replaces the complete text with an empty string.
    def clear : Nil
      self.value = ""
    end

    def length : Int32
      @buffer.size
    end

    # Returns the number of buffer edits, including undo and redo.
    def revision : Int32
      @buffer.revision
    end

    # Returns whether the text differs from the last save point.
    def modified? : Bool
      if found = @history
        found.modified?
      else
        @buffer.revision != @saved
      end
    end

    # Marks the current text as saved.
    def mark_saved : Nil
      @history.try(&.mark_saved)
      @saved = @buffer.revision
    end

    # Creates and registers a mark that follows subsequent edits.
    def mark(offset : Int32, gravity : Gravity = Gravity::Left) : Mark
      found = Mark.new(offset.clamp(0, length), gravity)
      @marks << found
      found
    end

    # Stops *mark* from following subsequent edits.
    def unmark(mark : Mark) : Nil
      @marks.delete(mark)
    end

    # Maps an offset from an earlier revision to the current text.
    #
    # Returns `nil` when the revision is newer or its changes are no longer retained.
    def map(offset : Int32, from : Int32, gravity : Gravity = Gravity::Left) : Int32?
      changes = @buffer.changes_since(from) || return nil
      spot    = Mark.new(offset.clamp(0, length), gravity)
      changes.each { |change| spot.follow(change) }
      spot.offset
    end

    # Maps an exclusive range from an earlier revision without growing at its edges.
    def map(range : Range(Int32, Int32), from : Int32) : Range(Int32, Int32)?
      start = map(range.begin, from, Gravity::Right) || return nil
      stop  = map(Math.max(range.end, range.begin), from, Gravity::Left) || return nil
      start...Math.max(stop, start)
    end

    # Groups edits into one history commit and listener batch and returns the block's value.
    #
    # Transactions may nest. Undo and redo return `false` while one is active.
    def transaction(view : View? = nil, & : -> T) : T forall T
      outer = @depth == 0
      if outer
        @batch         = [] of Change
        @batch_before  = view.try(&.carets) || [] of Caret
        @batch_primary = view.try(&.primary) || 0
        @batch_view    = view
        @batch_origin  = nil
        @stirred       = [] of View
      end

      @depth += 1
      begin
        yield
      ensure
        @depth -= 1
        finish if outer
      end
    end

    # Undoes one history step and returns whether a step was applied.
    def undo(view : View? = nil) : Bool
      revert(view, Origin::Undo)
    end

    # Redoes one history step and returns whether a step was applied.
    def redo(view : View? = nil) : Bool
      revert(view, Origin::Redo)
    end

    # Applies several replacements in reverse offset order as one history commit.
    #
    # Text bypasses the filter and capacity. The default origin is `Code`; other
    # views follow the changes. Optional *after* carets seat the acting *view*.
    def replace_ranges(edits : Array(Edit), gesture : Gesture = Gesture::Other, after : Array(Caret)? = nil, *,
                       view : View? = nil, origin : Origin = Origin::Code) : Bool
      return false unless admits?(origin)

      ordered = edits.sort_by { |edit| {edit.range.begin, edit.range.end} }
      floor   = 0
      kept    = [] of Edit

      ordered.each do |edit|
        from  = edit.range.begin.clamp(floor, length)
        to    = edit.range.end.clamp(from, length)
        floor = to
        kept << Edit.new(from...to, edit.text) unless from == to && edit.text.empty?
      end

      return false if kept.empty?

      before  = view.try(&.carets) || [] of Caret
      primary = view.try(&.primary) || 0
      sizes   = kept.map { |edit| {edit.range, count(edit.text)} }
      applied = [] of Change
      @acting = view
      kept.reverse_each { |edit| applied << @buffer.replace(edit.range, edit.text) }

      if view
        after ||= before.map { |caret| Caret.new(carry(caret.anchor, sizes), carry(caret.head, sizes)) }
        view.seat(after, primary)
      end
      record(gesture, origin, applied, before, primary, view)
      @acting = nil
      changed(applied)
      true
    end

    protected def apply(view : View, gesture : Gesture, & : Caret, Int32 -> Stroke?) : Bool
      return false unless admits?(Origin::User)

      before  = view.carets
      primary = view.primary
      strokes = Array(Stroke?).new(before.size)
      before.each_with_index { |caret, index| strokes << yield(caret, index) }

      room  = capacity.try { |max| max - length + strokes.sum { |stroke| stroke ? stroke.range.size : 0 } }
      floor = 0

      strokes.map! do |stroke|
        next nil unless stroke

        from  = Math.max(stroke.range.begin, floor)
        to    = Math.max(stroke.range.end, from)
        floor = to
        text  = stroke.text

        if left = room
          size = count(text)
          if size > left
            text = take(text, Math.max(left, 0))
            size = Math.max(left, 0)
          end
          room = left - size
        end

        from == to && text.empty? ? nil : stroke.copy_with(range: from...to, text: text)
      end

      return false if strokes.all?(&.nil?)

      changes = Array(Change?).new(strokes.size, nil)
      applied = [] of Change
      @acting = view
      (strokes.size - 1).downto(0) do |index|
        if stroke = strokes[index]
          change = @buffer.replace(stroke.range, stroke.text)
          changes[index] = change
          applied << change
        end
      end

      delta = 0
      after = before.map_with_index do |caret, index|
        stroke = strokes[index]
        change = changes[index]
        if stroke && change
          base   = stroke.range.begin + delta
          anchor = stroke.anchor
          head   = stroke.head
          placed = anchor && head ? Caret.new(base + anchor, base + head) : Caret.at(change.from + change.inserted_size + delta)
          delta += change.delta
          placed
        else
          caret.shift(delta)
        end
      end

      view.seat(after, primary)
      record(gesture, Origin::User, applied, before, primary, view)
      @acting = nil
      changed(applied)
      true
    end

    protected def assign(value : String, view : View?) : String
      @line_ending = LineEnding.detect(value) if value.includes?('\n') || value.includes?('\r')
      text = limit(prepare(value))

      if text == @buffer.text
        view.try(&.seat([Caret.at(length)], 0))
        return self.value
      end

      before  = view.try(&.carets) || [] of Caret
      primary = view.try(&.primary) || 0
      @acting = view
      change  = @buffer.replace(0...length, text)
      view.try(&.seat([Caret.at(length)], 0))
      record(Gesture::Other, Origin::Code, [change], before, primary, view)
      @acting = nil
      changed([change])
      self.value
    end

    protected def attach(view : View) : Nil
      @views << view
    end

    protected def detach(view : View) : Nil
      @views.delete(view)
    end

    protected def stirred(view : View) : Nil
      if @depth > 0
        @stirred << view unless @stirred.any?(&.same?(view))
      else
        @listeners.dup.each(&.moved(view))
      end
    end

    protected def prepare(text : String) : String
      @filter.filter(LineEnding.normalize(text))
    end

    protected def count(text : String) : Int32
      text.empty? ? 0 : @graphemes.boundaries(text).size - 1
    end

    private def revert(view : View?, origin : Origin) : Bool
      return false if @depth > 0 || !admits?(origin)

      history = @history || return false
      restore = (origin.undo? ? history.undo : history.redo) || return false
      before  = view.try(&.carets) || [] of Caret
      primary = view.try(&.primary) || 0
      seated  = restore.carets.empty? ? nil : view

      @acting = seated
      applied = restore.edits.map { |edit| @buffer.replace(edit.range, edit.text) }
      seated.try(&.seat(restore.carets, restore.primary))
      @acting = nil
      history.record(Commit.new(Gesture::Other, origin, applied, before, primary,
        view.try(&.carets) || [] of Caret, view.try(&.primary) || 0))
      changed(applied)
      true
    end

    private def record(gesture : Gesture, origin : Origin, changes : Array(Change), before : Array(Caret),
                       primary : Int32, view : View?) : Nil
      if @depth > 0
        @batch.concat(changes)
        @batch_view   ||= view
        @batch_origin ||= origin
      else
        @history.try(&.record(Commit.new(gesture, origin, changes, before, primary,
          view.try(&.carets) || [] of Caret, view.try(&.primary) || 0)))
      end
    end

    private def changed(changes : Array(Change)) : Nil
      @listeners.dup.each(&.edited(self, changes)) if @depth == 0
    end

    private def finish : Nil
      batch       = @batch
      acting      = @batch_view
      origin      = @batch_origin || Origin::Code
      stirred     = @stirred
      @batch      = [] of Change
      @batch_view = nil
      @stirred    = [] of View
      @batch_origin = nil

      unless batch.empty?
        @history.try(&.record(Commit.new(Gesture::Other, origin, batch, @batch_before, @batch_primary,
          acting.try(&.carets) || [] of Caret, acting.try(&.primary) || 0)))
      end
      stirred.each { |view| @listeners.dup.each(&.moved(view)) }
      @listeners.dup.each(&.edited(self, batch)) unless batch.empty?
    end

    private def applied(change : Change) : Nil
      @marks.each(&.follow(change))
      @followers.each(&.follow(change))
      acting = @acting
      @views.each { |view| view.follow(change) unless acting && view.same?(acting) }
      @listeners.dup.each(&.applied(self, change))
    end

    private def carry(offset : Int32, sizes : Array({Range(Int32, Int32), Int32})) : Int32
      delta = 0
      sizes.each do |(range, inserted)|
        return range.begin + delta + inserted if range.begin < offset < range.end
        break if offset < range.end || (offset == range.begin && range.size > 0)

        delta += inserted - range.size
      end
      offset + delta
    end

    private def take(text : String, clusters : Int32) : String
      text.byte_slice(0, @graphemes.boundaries(text)[clusters])
    end

    private def limit(text : String) : String
      max = capacity
      max && count(text) > max ? take(text, max) : text
    end
  end
end
