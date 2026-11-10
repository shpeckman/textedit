# src/textedit/history.cr
module Textedit
  # One document mutation delivered to a `History`, including carets around the edit.
  record Commit, gesture : Gesture, origin : Origin, changes : Array(Change),
    before : Array(Caret), before_primary : Int32, after : Array(Caret), after_primary : Int32

  # Stores document commits and supplies reversible edits for undo and redo.
  module History
    # Edits to apply in order and carets to seat after an undo or redo.
    record Restore, edits : Array(Edit), carets : Array(Caret), primary : Int32

    # Records one completed document commit.
    abstract def record(commit : Commit) : Nil

    # Removes and returns the next undo restoration, or `nil` when unavailable.
    abstract def undo : Restore?

    # Removes and returns the next redo restoration, or `nil` when unavailable.
    abstract def redo : Restore?

    # Returns whether an undo step is available.
    abstract def can_undo? : Bool

    # Returns whether a redo step is available.
    abstract def can_redo? : Bool

    # Returns whether the current position differs from the save point.
    abstract def modified? : Bool

    # Marks the current history position as saved.
    abstract def mark_saved : Nil

    # Clears all retained history and resets its save point.
    abstract def clear : Nil

    # Decides whether two adjacent commits belong to one undo step.
    module Grouping
      # Returns whether *following* joins *previous* after *elapsed* time.
      abstract def join?(previous : Commit, following : Commit, elapsed : Time::Span) : Bool

      # Groups adjacent typing and deletion within a time window, breaking typing at word starts.
      class Adjacent
        include Grouping

        property window : Time::Span

        # Creates the standard grouping policy using *graphemes* for word-boundary detection.
        def initialize(@graphemes : Graphemes, @window : Time::Span = Linear::WINDOW)
        end

        def join?(previous : Commit, following : Commit, elapsed : Time::Span) : Bool
          gesture = following.gesture
          return false if gesture.other? || previous.gesture != gesture
          return false if elapsed > @window
          return false unless previous.after == following.before
          return true unless gesture.typing?

          earlier = previous.changes.last?.try(&.inserted) || return true
          upcoming = following.changes.first?.try(&.inserted) || return true
          return true if earlier.empty? || upcoming.empty?

          !(blank?(earlier, last: true) && !blank?(upcoming, last: false))
        end

        private def blank?(text : String, last : Bool) : Bool
          marks = @graphemes.boundaries(text)
          start = last ? marks[-2] : 0
          stop  = last ? marks[-1] : marks[1]
          @graphemes.kind(text.to_slice[start, stop - start]).space?
        end
      end

      # Policy that keeps every commit in a separate undo step.
      struct Never
        include Grouping

        def join?(previous : Commit, following : Commit, elapsed : Time::Span) : Bool
          false
        end
      end
    end

    # Linear undo and redo stacks with configurable commit grouping.
    class Linear
      include History

      # Default maximum number of retained undo steps.
      LIMIT  = 500
      # Default time window for grouping adjacent typing or deletion.
      WINDOW = 1.second

      # :nodoc:
      class Step
        getter id              : Int32
        getter gesture         : Gesture
        getter origin          : Origin
        getter changes         : Array(Change)
        getter before          : Array(Caret)
        getter before_primary  : Int32
        property after         : Array(Caret)
        property after_primary : Int32
        property at            : Time::Instant

        def initialize(@id : Int32, @gesture : Gesture, @origin : Origin, @changes : Array(Change), @before : Array(Caret),
                       @before_primary : Int32, @after : Array(Caret), @after_primary : Int32, @at : Time::Instant)
        end
      end

      property limit    : Int32
      getter window     : Time::Span
      property grouping : Grouping

      @undo   : Array(Step)
      @redo   : Array(Step)
      @serial : Int32
      @saved  : Int32
      @sealed : Bool

      # Creates a linear history with optional grouping and an injectable clock.
      #
      # By default, grouping uses `Grouping::Adjacent` with *window*. Supplying
      # *grouping* replaces that policy while preserving *window* for later assignment.
      def initialize(graphemes : Graphemes, @limit : Int32 = LIMIT, @window : Time::Span = WINDOW,
                     @clock : Proc(Time::Instant) = -> { Time.instant }, grouping : Grouping? = nil)
        @grouping = grouping || Grouping::Adjacent.new(graphemes, @window)
        @undo     = [] of Step
        @redo     = [] of Step
        @serial   = 0
        @saved    = -1
        @sealed   = false
      end

      # Changes the default grouping window and updates an adjacent policy when installed.
      def window=(value : Time::Span) : Time::Span
        @window = value
        @grouping.as?(Grouping::Adjacent).try { |policy| policy.window = value }
        value
      end

      def can_undo? : Bool
        !@undo.empty?
      end

      def can_redo? : Bool
        !@redo.empty?
      end

      def clear : Nil
        @undo.clear
        @redo.clear
        @saved = -1
      end

      def mark_saved : Nil
        @saved  = top
        @sealed = true
      end

      def modified? : Bool
        top != @saved
      end

      def record(commit : Commit) : Nil
        return if commit.changes.empty? || commit.origin.undo? || commit.origin.redo?

        now = @clock.call
        @redo.clear

        if !@sealed && (last = @undo.last?) && joins?(last, commit, now)
          last.changes.concat(commit.changes)
          last.after         = commit.after
          last.after_primary = commit.after_primary
          last.at            = now
          return
        end

        @sealed  = false
        @serial += 1
        @undo << Step.new(@serial, commit.gesture, commit.origin, commit.changes.dup, commit.before, commit.before_primary,
          commit.after, commit.after_primary, now)
        @undo.shift if @undo.size > @limit
      end

      def undo : Restore?
        step = @undo.pop? || return
        @redo << step
        @sealed = true
        edits = step.changes.reverse.map { |change| Edit.new(change.from...(change.from + change.inserted_size), change.removed) }
        Restore.new(edits, step.before, step.before_primary)
      end

      def redo : Restore?
        step = @redo.pop? || return
        @undo << step
        @sealed = true
        edits = step.changes.map { |change| Edit.new(change.from...(change.from + change.removed_size), change.inserted) }
        Restore.new(edits, step.after, step.after_primary)
      end

      private def top : Int32
        @undo.last?.try(&.id) || -1
      end

      private def joins?(last : Step, commit : Commit, now : Time::Instant) : Bool
        previous = Commit.new(last.gesture, last.origin, last.changes, last.before, last.before_primary,
          last.after, last.after_primary)
        @grouping.join?(previous, commit, now - last.at)
      end
    end
  end
end
