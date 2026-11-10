# src/textedit/history/journal.cr
require "json"

module Textedit
  module History
    # Append-only event journal backed by a branching history, optionally persisted as JSON lines.
    #
    # Entries and files grow until external rotation. A journal records history,
    # not document text, and each persistent file expects a single writer.
    class Journal
      include History

      # Current on-disk event format version.
      VERSION = 1

      # Journal event category.
      enum Kind
        Commit
        MarkSaved
        Clear
        Choose
      end

      # One audited event, including raw undo and redo commits.
      #
      # `grouped` records whether a commit joined its predecessor. `node` identifies
      # the selected child for a `Choose` event.
      record Event, kind : Kind, at : Time, commit : Commit? = nil, grouped : Bool = false, node : Int32? = nil

      # :nodoc:
      record CaretWire, anchor : Int32, head : Int32, goal : Int32? = nil do
        include JSON::Serializable
      end

      # :nodoc:
      record ChangeWire, from : Int32, removed : String, inserted : String,
        removed_size : Int32, inserted_size : Int32 do
        include JSON::Serializable
      end

      # :nodoc:
      record CommitWire, gesture : Gesture, origin : Origin, changes : Array(ChangeWire),
        before : Array(CaretWire), before_primary : Int32, after : Array(CaretWire), after_primary : Int32 do
        include JSON::Serializable
      end

      # :nodoc:
      record EventWire, v : Int32, kind : Kind, at : String, commit : CommitWire? = nil,
        grouped : Bool = false, node : Int32? = nil do
        include JSON::Serializable
      end

      getter entries  : Array(Event)
      getter path     : String?
      getter grouping : Grouping
      getter window   : Time::Span

      @tree  : Tree
      @clock : Proc(Time::Instant)

      # Opens a journal at *path*, loading existing events before returning it.
      def self.open(graphemes : Graphemes, path : String, window : Time::Span = Linear::WINDOW,
                    clock : Proc(Time::Instant) = -> { Time.instant }, grouping : Grouping? = nil) : Journal
        new(graphemes, path: path, window: window, clock: clock, grouping: grouping)
      end

      # Creates an in-memory journal or loads a persistent journal from *path*.
      #
      # Existing complete events are replayed. An incomplete trailing event is
      # discarded after all preceding events load successfully. Malformed or
      # inconsistent complete events raise `ArgumentError`.
      def initialize(graphemes : Graphemes, @path : String? = nil, @window : Time::Span = Linear::WINDOW,
                     @clock : Proc(Time::Instant) = -> { Time.instant }, grouping : Grouping? = nil)
        @grouping = grouping || Grouping::Adjacent.new(graphemes, @window)
        @tree     = Tree.new(graphemes, @window, @clock, @grouping)
        @entries  = [] of Event
        load if (path = @path) && File.exists?(path)
      end

      # Returns the root of the replayed history tree.
      def root : Tree::Node
        @tree.root
      end

      # Returns the current position in the replayed history tree.
      def current : Tree::Node
        @tree.current
      end

      # Changes the grouping policy for subsequent commits.
      def grouping=(value : Grouping) : Grouping
        @grouping = value
        @tree.grouping = value
      end

      # Changes the default grouping window and updates an adjacent policy when installed.
      def window=(value : Time::Span) : Time::Span
        @window = value
        @tree.window = value
      end

      def can_undo? : Bool
        @tree.can_undo?
      end

      def can_redo? : Bool
        @tree.can_redo?
      end

      # Resets navigable history by appending a clear marker; audit entries remain.
      def clear : Nil
        @tree.clear
        append(Event.new(Kind::Clear, Time.utc))
      end

      def mark_saved : Nil
        @tree.mark_saved
        append(Event.new(Kind::MarkSaved, Time.utc))
      end

      def modified? : Bool
        @tree.modified?
      end

      # Appends every nonempty commit, including commits produced by undo and redo.
      def record(commit : Commit) : Nil
        return if commit.changes.empty?

        if commit.origin.undo? || commit.origin.redo?
          append(Event.new(Kind::Commit, Time.utc, commit))
          return
        end

        now     = @clock.call
        grouped = @tree.joins?(commit, now)
        @tree.record_at(commit, now, grouped)
        append(Event.new(Kind::Commit, Time.utc, commit, grouped))
      end

      def undo : Restore?
        @tree.undo
      end

      def redo : Restore?
        @tree.redo
      end

      # Selects and journals which child of the current node the next `#redo` follows.
      def choose(node : Tree::Node) : Bool
        return false unless @tree.choose(node)

        append(Event.new(Kind::Choose, Time.utc, node: node.id))
        true
      end

      private def append(event : Event) : Nil
        @entries << event
        path = @path || return

        File.open(path, "a") do |file|
          file << wire(event).to_json << '\n'
          file.flush
        end
      end

      private def load : Nil
        path     = @path.not_nil!
        source   = File.read(path)
        complete = complete_prefix(source)
        parse(complete)
        replay
        @tree.seal
        return if complete.bytesize == source.bytesize

        File.open(path, "r+") { |file| file.truncate(complete.bytesize) }
      end

      private def complete_prefix(source : String) : String
        return source if source.empty? || source.ends_with?('\n')

        last = source.to_slice.rindex(0x0A_u8)
        last ? source.byte_slice(0, last + 1) : ""
      end

      private def parse(source : String) : Nil
        source.lines.each_with_index do |line, index|
          begin
            found = EventWire.from_json(line)
            raise ArgumentError.new("unsupported journal version #{found.v}") unless found.v == VERSION
            @entries << event(found)
          rescue error
            raise ArgumentError.new("invalid journal event on line #{index + 1}: #{error.message}")
          end
        end
      end

      private def replay : Nil
        @entries.each_with_index do |entry, index|
          begin
            case entry.kind
            in .commit?
              replay_commit(entry.commit.not_nil!, entry.grouped)
            in .mark_saved?
              @tree.mark_saved
            in .clear?
              @tree.clear
            in .choose?
              id   = entry.node.not_nil!
              node = @tree.current.children.find { |child| child.id == id } || raise ArgumentError.new("unknown branch #{id}")
              @tree.choose(node) || raise ArgumentError.new("branch #{id} is not a child of the current node")
            end
          rescue error
            raise ArgumentError.new("cannot replay journal event #{index + 1}: #{error.message}")
          end
        end
      end

      private def replay_commit(commit : Commit, grouped : Bool) : Nil
        case commit.origin
        in .user?, .code?
          @tree.record_at(commit, @clock.call, grouped)
        in .undo?
          @tree.undo || raise ArgumentError.new("nothing to undo")
        in .redo?
          @tree.redo || raise ArgumentError.new("nothing to redo")
        end
      end

      private def wire(event : Event) : EventWire
        EventWire.new(VERSION, event.kind, event.at.to_rfc3339, event.commit.try { |commit| wire(commit) }, event.grouped, event.node)
      end

      private def wire(commit : Commit) : CommitWire
        CommitWire.new(commit.gesture, commit.origin, commit.changes.map { |change| wire(change) },
          commit.before.map { |caret| wire(caret) }, commit.before_primary,
          commit.after.map { |caret| wire(caret) }, commit.after_primary)
      end

      private def wire(change : Change) : ChangeWire
        ChangeWire.new(change.from, change.removed, change.inserted, change.removed_size, change.inserted_size)
      end

      private def wire(caret : Caret) : CaretWire
        CaretWire.new(caret.anchor, caret.head, caret.goal)
      end

      private def event(wire : EventWire) : Event
        Event.new(wire.kind, Time.parse_rfc3339(wire.at), wire.commit.try { |commit| event(commit) }, wire.grouped, wire.node)
      end

      private def event(wire : CommitWire) : Commit
        Commit.new(wire.gesture, wire.origin, wire.changes.map { |change| event(change) },
          wire.before.map { |caret| event(caret) }, wire.before_primary,
          wire.after.map { |caret| event(caret) }, wire.after_primary)
      end

      private def event(wire : ChangeWire) : Change
        Change.new(wire.from, wire.removed, wire.inserted, wire.removed_size, wire.inserted_size)
      end

      private def event(wire : CaretWire) : Caret
        Caret.new(wire.anchor, wire.head, wire.goal)
      end
    end
  end
end
