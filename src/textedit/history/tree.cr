# src/textedit/history/tree.cr
module Textedit
  module History
    # Branching undo history that preserves alternative redo paths after new edits.
    #
    # Every node remains retained until `#clear`.
    class Tree
      include History

      # One commit position in a `Tree`, with links for branch inspection.
      class Node
        getter id       : Int32
        getter parent   : Node?
        getter children : Array(Node)
        getter commit   : Commit?

        # :nodoc:
        getter at : Time::Instant?

        # :nodoc:
        def initialize(@id : Int32, @parent : Node?, @commit : Commit?, @at : Time::Instant? = nil)
          @children = [] of Node
        end

        protected def commit=(value : Commit?) : Commit?
          @commit = value
        end

        protected def at=(value : Time::Instant?) : Time::Instant?
          @at = value
        end
      end

      getter root      : Node
      getter current   : Node
      getter window    : Time::Span
      property grouping : Grouping

      @saved   : Node
      @choices : Hash(Node, Node)
      @serial  : Int32
      @sealed  : Bool

      # Creates an empty branching history with optional grouping and an injectable clock.
      def initialize(graphemes : Graphemes, @window : Time::Span = Linear::WINDOW,
                     @clock : Proc(Time::Instant) = -> { Time.instant }, grouping : Grouping? = nil)
        @grouping = grouping || Grouping::Adjacent.new(graphemes, @window)
        @serial   = 0
        @root     = Node.new(0, nil, nil)
        @current  = @root
        @saved    = @root
        @choices  = {} of Node => Node
        @sealed   = false
      end

      # Changes the default grouping window and updates an adjacent policy when installed.
      def window=(value : Time::Span) : Time::Span
        @window = value
        @grouping.as?(Grouping::Adjacent).try { |policy| policy.window = value }
        value
      end

      def can_undo? : Bool
        !@current.parent.nil?
      end

      def can_redo? : Bool
        !@current.children.empty?
      end

      def clear : Nil
        @serial  = 0
        @root    = Node.new(0, nil, nil)
        @current = @root
        @saved   = @root
        @choices.clear
        @sealed  = false
      end

      def mark_saved : Nil
        @saved  = @current
        @sealed = true
      end

      def modified? : Bool
        !@current.same?(@saved)
      end

      def record(commit : Commit) : Nil
        record_at(commit, @clock.call)
      end

      def undo : Restore?
        parent = @current.parent || return
        node   = @current
        commit = node.commit.not_nil!

        @choices[parent] = node
        @current = parent
        @sealed  = true
        edits = commit.changes.reverse.map { |change| Edit.new(change.from...(change.from + change.inserted_size), change.removed) }
        Restore.new(edits, commit.before, commit.before_primary)
      end

      def redo : Restore?
        node   = @choices[@current]? || @current.children.last? || return
        commit = node.commit.not_nil!

        @current = node
        @sealed  = true
        edits = commit.changes.map { |change| Edit.new(change.from...(change.from + change.removed_size), change.inserted) }
        Restore.new(edits, commit.after, commit.after_primary)
      end

      # Selects which child of the current node the next `#redo` follows.
      #
      # Returns `false` when *node* is not an immediate child of `#current`.
      def choose(node : Node) : Bool
        parent = node.parent
        return false unless parent && parent.same?(@current)

        @choices[@current] = node
        true
      end

      # :nodoc:
      protected def record_at(commit : Commit, now : Time::Instant, grouped : Bool? = nil) : Nil
        return if commit.changes.empty? || commit.origin.undo? || commit.origin.redo?

        combine = grouped.nil? ? joins?(commit, now) : grouped
        if combine
          previous = @current.commit.not_nil!
          @current.commit = Commit.new(previous.gesture, previous.origin, previous.changes + commit.changes,
            previous.before, previous.before_primary, commit.after, commit.after_primary)
          @current.at = now
          return
        end

        @sealed = false
        @serial += 1
        node = Node.new(@serial, @current, commit, now)
        @current.children << node
        @choices[@current] = node
        @current = node
      end

      # :nodoc:
      protected def joins?(commit : Commit, now : Time::Instant) : Bool
        return false if @sealed || !@current.children.empty?

        previous = @current.commit || return false
        @grouping.join?(previous, commit, now - @current.at.not_nil!)
      end

      # :nodoc:
      protected def seal : Nil
        @sealed = true
      end
    end
  end
end
