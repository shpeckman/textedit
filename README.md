# textedit

A multi-caret text editing model for Crystal, built from features you compose.

textedit holds the text, the carets and the undo history, and carries out editing commands: typing, deleting, word and subword motion, multiple carets, box selection, clipboard, line operations and transforms, comments, auto-closing brackets, snippets with tabstops, folding, and find and replace. Each of those is a feature module, so a single-line field, a read-only viewer and a code editor each carry only what they use. History, read-only and length limits, decorations, annotations and file storage are separate, swappable services. One document can carry several views, each with its own carets, layout and features. It draws nothing, reads no input and highlights nothing: syntax tokens come from a host-supplied `TokenSource`, such as the Tree-sitter highlighter in [asekii-editor](https://github.com/shpeckman/asekii-editor). The host — a terminal UI, a GUI, a test — implements a few small interfaces, sends commands, and listens for changes.

It has no dependencies beyond the standard library.

## Requirements

- Crystal 1.21 or newer

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  textedit:
    github: shpeckman/textedit
```

Then run `shards install` and require it:

```crystal
require "textedit"
```

## Quick start

A document needs one thing from its host: a `Textedit::Graphemes`, which finds the grapheme cluster boundaries in a string, classifies a cluster and measures its display width.

```crystal
require "textedit"

struct Clusters
  include Textedit::Graphemes

  def boundaries(text : String) : Array(Int32)
    marks = [0]
    text.each_grapheme { |grapheme| marks << marks.last + grapheme.to_s.bytesize }
    marks
  end

  def kind(cluster : Bytes) : Textedit::ClusterKind
    char = String.new(cluster)[0]? || return Textedit::ClusterKind::Other
    return Textedit::ClusterKind::Space if char.whitespace?
    return Textedit::ClusterKind::Word if char.alphanumeric? || char == '_'

    Textedit::ClusterKind::Punct
  end

  def width(cluster : Bytes) : Int32
    1
  end
end

text = Textedit::Editor.new(Clusters.new, "hello world")
text.run(Textedit::Motion::WordLeft)
text.insert("big ")
text.value # => "hello big world"
text.undo
text.value # => "hello world"
```

## Composition

Three things make up an editing widget:

- A `Document` holds the text and the services that act on every edit: the `History`, the `Constraint`s, the `Filter`, the `Style`, the marks and the listeners.
- A `View` holds the carets, the goal column and the `Layout`, and carries out motion. Everything else a view can do comes from the feature modules it includes.
- Each feature module brings its own command enum, its state and its methods.

### Presets

Four ready-made views cover the common widgets. Each one declares its command union as `Command`, which is also the type for a host keymap.

| Preset | Features | Document defaults |
| --- | --- | --- |
| `Field` | `Typing`, `Deleting`, `Selecting`, `Copying`, `Pasting`, `Undoing`, `Recalling` | `SingleLine` filter, `History::Linear` |
| `Area` | `Field`'s except `Recalling`, plus `Spacing` and `Multicaret` | `MultiLine` filter, `History::Linear` |
| `Reader` | `Selecting`, `Multicaret`, `Copying`, `Finding`, `Folding` | `MultiLine` filter, no history |
| `Editor` | `Area`'s features, plus `LineEditing`, `Transforming`, `Boxing`, `Finding`, `Replacing`, `Folding`, `Snipping` and `Recording` | `MultiLine` filter, `History::Linear` |

```crystal
name   = Textedit::Field.new(graphemes, "hello", constraints: [Textedit::MaxLength.new(40)])
notes  = Textedit::Area.new(graphemes)
viewer = Textedit::Reader.new(graphemes, log_text)
editor = Textedit::Editor.new(graphemes, source, style: Textedit::Style.new(indent: "\t", comment: "#"))
```

`View.new(graphemes, text, **options)` builds the view's own document; the options go to `Document.new` and override the preset's defaults. `View.new(document)` attaches a view to an existing document instead. A view starts with one caret at the end of the text.

Settings that belong to a feature are properties of the view, set after construction:

```crystal
editor.auto_close     = true
editor.auto_indent    = true
editor.clipboard      = system_clipboard
editor.copy_on_select = true
```

### Building a widget

Subclass `View`, include the features, and name the command union:

```crystal
class Pin < Textedit::View
  alias Command = Textedit::Motion | Textedit::Deletion

  include Textedit::Typing
  include Textedit::Deleting
end

pin = Pin.new(graphemes, filter: Digits.new, history: nil, constraints: [Textedit::MaxLength.new(6)])
pin.insert("12a3")
pin.value                      # => "123"
pin.run(Textedit::Clip::Paste) # compile error: Pin has no Pasting
```

A command a view lacks is a compile error, not a `false` at run time. A preset can be the base class too, for example `class Console < Textedit::Field` with `include Textedit::Finding`.

| Feature | Commands | Adds | Needs |
| --- | --- | --- | --- |
| (core) | `Motion` | carets, `move`, `select_range`, `place_carets`, `add_caret`, `replace_ranges`, `transaction`, `value`, `dragging?` | |
| `Typing` | | `insert`, `paste`, `auto_close?` | |
| `Deleting` | `Deletion` | | |
| `Spacing` | `Whitespace` | `auto_indent?` | include before `LineEditing` |
| `LineEditing` | `Lines` | `Tab` indents a selection that spans lines | |
| `Transforming` | `Transform` | `surround`, `unsurround` | |
| `Selecting` | `Selection` | `select_all`, `select_word`, `select_line`, `brackets` | |
| `Multicaret` | `Carets` | `collapse`, `remove_last_caret`, `add_next_occurrence`, `skip_occurrence`, `select_all_occurrences`, `add_caret_per_line` | |
| `Boxing` | `Box` | `box`, `start_box`, `select_box`, `clear_box` | |
| `Copying` | `Copy` | `clipboard`, `selection_clipboard`, `copyable?`, `copy_on_select?`, `auto_copy` | |
| `Pasting` | `Clip` | paste cycling | `Typing`, `Copying` |
| `Undoing` | `UndoRedo` | `undo`, `redo` | |
| `Finding` | | `find`, `add_caret_at_every_match` | |
| `Replacing` | | `replace_match`, `replace_all` | |
| `Folding` | | `folds`, `folds?`, `lift_carets` | |
| `Snipping` | | `insert_snippet` | |
| `Recording(C)` | | `record`, `stop`, `replay`, `macros` | `Typing` |
| `Recalling` | `Recall` | `recollection` | |

The "Needs" column is checked when the module is included: including `Pasting` before `Typing` and `Copying`, or `LineEditing` before `Spacing`, stops the build with a message naming the order. `Recording(C)` takes the view's whole command union; running a command whose enum is missing from `C` is a compile error, so a recording can never silently skip a step.

To change what a widget can do at run time, keep the document and swap the view:

```crystal
editor = Textedit::Editor.new(reader.document)
editor.place_carets(reader.carets, reader.primary)
reader.close
```

## Documents

```crystal
text = Textedit::Document.new(graphemes, "one two",
  filter:      Textedit::MultiLine.new,
  history:     Textedit::History::Linear.new(graphemes),
  constraints: [Textedit::MaxLength.new(80)],
  style:       Textedit::Style.new(indent: "  ", tab_size: 4, comment: "#"))
```

| Option | Default | Effect |
| --- | --- | --- |
| `filter` | `SingleLine.new` | What happens to incoming text (see Filters) |
| `history` | `History::Linear.new(graphemes)` | Records edits for undo; `nil` for none |
| `constraints` | none | Which edits are admitted and how long the text may grow (see Constraints) |
| `style` | `Style.new` | `indent` (inserted by `Tab` and `Indent`), `tab_size` (spaces `Outdent` removes when `indent` is a tab), `comment` (line comment prefix for `ToggleComment`) |

`filter`, `history`, `style` and `line_ending` are properties; assigning `constraints=` truncates the text when a new capacity is lower. A document can also be built from a `Buffer`, which is what `Storage.open` does with a mapped file.

Offsets everywhere count grapheme clusters, not bytes or characters; a line break counts as one cluster.

```crystal
text.value                 # the text, with \n line breaks
text.value = "replaced"    # undoable; every view's carets follow
text.length
text.views                 # the views attached to it
```

On a view, `value=` does the same and puts that view's caret at the end.

### Line endings

Text is always held with `\n` breaks. The ending found in the text a document is created with, or given through `value=`, is kept as `line_ending` (`LF`, `CRLF` or `CR`); `Storage` writes it back out. Pasted and typed `\r\n` and `\r` become `\n` as well.

```crystal
text = Textedit::Document.new(graphemes, "a\r\nb", filter: Textedit::MultiLine.new)
text.value        # => "a\nb"
text.line_ending  # => Textedit::LineEnding::CRLF
```

### Transactions and the save point

```crystal
editor.transaction do
  editor.run(Textedit::Motion::DocumentEnd)
  editor.insert("\n")
  editor.insert("appended")
end                # one undo step, one `moved` per view that moved, and one `edited`

text.mark_saved
text.modified?     # false until the text changes again
```

`transaction` returns the block's value and can be nested; `undo` and `redo` are refused inside one. `Document#transaction(view = nil)` is the same without a view to record carets for. With a history, undoing back to the save point clears `modified?`; without one, any edit after `mark_saved` sets it.

### Constraints

A constraint decides whether edits from an `Origin` are admitted and how many clusters the text may hold. The document asks every constraint before each edit.

```crystal
lock = Textedit::ReadOnly.new          # active by default
text = Textedit::Document.new(graphemes, "fixed", constraints: [lock, Textedit::MaxLength.new(80)])
text.admits?                           # => false: user edits are refused
lock.active = false                    # editable again
text.capacity                          # => 80, the lowest capacity of all constraints
```

`Origin` is `User` (typing and commands), `Code` (`value=` and `replace_ranges` from the host), `Undo` or `Redo`. `ReadOnly` admits only `Code`, so the host can still set the text. `MaxLength` trims typed and pasted text to fit, shared across carets, and truncates text given to `value=` or to the constructor. A host constraint includes `Textedit::Constraint` and overrides `admits?(origin)`, `capacity`, or both.

While a document refuses user edits, a view refuses every command whose enum edits — `Deletion`, `Whitespace`, `Lines`, `Transform`, `Clip`, `UndoRedo` and `Recall` — along with `insert`, `paste`, `insert_snippet`, `replace_match` and `replace_all`. Motion, selection and copy still work.

### History

Every edit becomes one `Commit` — its `gesture` (`Typing`, `Deleting` or `Other`), its `origin`, the `changes`, and the carets before and after — and the document hands it to its `history`. Undo asks the history for a `History::Restore` (edits to apply in order, and carets to seat), applies it, and hands that back as a commit with origin `Undo` or `Redo`.

`History::Linear` is the default: an undo and a redo stack, typing and deleting grouped within a time window and broken at word starts, a save point, and a bound.

```crystal
Textedit::History::Linear.new(graphemes, limit: 1000, window: 2.seconds)
```

It ignores the commits its own undo and redo produce.

#### Configurable grouping

`History::Grouping` decides whether two adjacent commits form one undo step. Its `join?(previous, following, elapsed)` method can inspect both commits' gestures, origins, changes and carets. `Grouping::Adjacent` provides the standard time-window and word-start behavior; `Grouping::Never` gives every commit its own step. Both linear and tree histories accept a policy, and it can be replaced later:

```crystal
ungrouped = Textedit::History::Grouping::Never.new
history   = Textedit::History::Linear.new(graphemes, grouping: ungrouped)

history.grouping = Textedit::History::Grouping::Adjacent.new(graphemes, 2.seconds)
```

A host can include `History::Grouping` in its own type for command-, transaction- or language-aware grouping. Grouping applies only to subsequent commits.

#### Branching history

`History::Tree` preserves alternative redo paths. Undo followed by a new edit adds a branch instead of discarding the old one:

```crystal
history = Textedit::History::Tree.new(graphemes)
editor  = Textedit::Editor.new(graphemes, source, history: history)

editor.undo                         # return to a node with several children
history.current.children           # branches available from this node
history.choose(history.current.children.first)
editor.redo                         # follow the chosen branch
```

`choose` accepts only an immediate child of `current`. Undo to the divergence point before choosing another branch. `root`, `current` and each node's `parent`, `children` and `commit` expose the tree for a history browser. Every node remains in memory until `clear`.

#### Append-only and persistent history

`History::Journal` combines a tree with an append-only event log. Unlike linear and tree histories, it retains the raw commits produced by undo and redo in `entries`, together with save points, clears and explicit branch choices:

```crystal
journal = Textedit::History::Journal.open(graphemes, "notes.history.jsonl")
storage = Textedit::Storage.open(graphemes, "notes.txt", history: journal)
editor  = Textedit::Editor.new(storage.document)
```

`Journal.new(graphemes)` makes an in-memory journal. With a path, every event is appended and flushed as one JSON object on its own line. Format version 1 stores an RFC 3339 UTC timestamp, the event kind, its optional commit, whether it joined its predecessor, and an optional chosen node ID. Grouping decisions are stored, so reloading does not depend on the currently configured policy.

Opening an existing journal replays its events and save points. A malformed or inconsistent complete event raises `ArgumentError`; an incomplete trailing event is discarded after the valid prefix loads. `clear` appends a reset marker rather than deleting old events. The journal does not store document text, so open the text and history separately. Use one writer per journal file; entries and files grow until the host rotates them.

A different kind of history includes `Textedit::History` and implements `record(commit)`, `undo`, `redo`, `can_undo?`, `can_redo?`, `modified?`, `mark_saved` and `clear`. `history: nil` turns undo off, and `document.history = …` swaps it on a live document.

### Marks

A `Mark` is an offset that follows edits, for bookmarks, diagnostics or search highlights:

```crystal
spot  = text.mark(10)                              # Textedit::Gravity::Left by default
after = text.mark(10, Textedit::Gravity::Right)
spot.offset
text.unmark(spot)
```

Text inserted exactly at a mark goes after a `Left` mark and before a `Right` mark. A mark inside deleted text moves to where the deletion happened.

## Views

A view owns the carets, the goal column and the `Layout`. Two views of one document share the text and the history: an edit from either one shows in both, the other's carets are carried through it as marks are, and `undo` from either one seats the carets it recorded. `layout = …` is per view, so two panes can wrap the same document at different widths.

```crystal
text  = Textedit::Editor.new(graphemes, "one two")
other = Textedit::Reader.new(text.document)
other.select_range(0, 3)     # its own carets, its own layout
text.document.views.size     # => 2
other.close                  # stops following the document
```

```crystal
text.cursor                # the head of the primary caret
text.carets                # Array(Textedit::Caret), sorted and merged
text.select_range(0, 3)
text.selected_text
text.selected_texts
text.place_carets([Textedit::Caret.at(0), Textedit::Caret.at(4)])
text.insert("x")           # typed text, at every caret
text.paste("a\nb")         # one line per caret when the counts match
text.undo
text.redo
```

`dragging=` tells a view a pointer drag is in progress, which holds back `copy_on_select` until the host calls `auto_copy` on release.

## Commands

`run(command, selecting = false)` carries out one command. Every feature's `run` takes `selecting`, so a host can pass its union straight through; motion uses it to extend the selection, everything else ignores it.

| Enum | Members |
| --- | --- |
| `Motion` | `Left`, `Right`, `WordLeft`, `WordRight`, `SubwordLeft`, `SubwordRight`, `RowStart`, `SmartRowStart`, `RowEnd`, `Up`, `Down`, `PageUp`, `PageDown`, `DocumentStart`, `DocumentEnd` |
| `Selection` | `All`, `Word`, `Line`, `InsideBrackets`, `AroundBrackets`, `InsideQuotes`, `AroundQuotes` |
| `Carets` | `Collapse`, `AddNextOccurrence`, `SkipOccurrence`, `SelectAllOccurrences`, `AddAbove`, `AddBelow`, `AddPerLine`, `RemoveLast` |
| `Box` | `Up`, `Down`, `Left`, `Right` |
| `Deletion` | `Backward`, `Forward`, `WordBackward`, `WordForward`, `SubwordBackward`, `SubwordForward`, `ToRowStart`, `ToRowEnd` |
| `Whitespace` | `NewLine`, `Tab` |
| `Lines` | `Indent`, `Outdent`, `ToggleComment`, `MoveUp`, `MoveDown`, `Duplicate`, `Delete` |
| `Transform` | `DuplicateSelection`, `Sort`, `Reverse`, `Unique`, `Join`, `TrimTrailingWhitespace`, `UpperCase`, `LowerCase`, `TitleCase` |
| `Copy` | `Selection` |
| `Clip` | `Cut`, `Paste`, `PastePrevious` |
| `UndoRedo` | `Undo`, `Redo` |
| `Recall` | `Back`, `Forward` |

Each enum's `edits?` says whether its commands change the text.

```crystal
KEYS = {
  Key::Left      => Textedit::Motion::Left,
  Key::Backspace => Textedit::Deletion::Backward,
  Key::CtrlV     => Textedit::Clip::Paste,
} of Key => Textedit::Field::Command

field.run(KEYS[key], selecting: shift)
```

`run` returns `true` when the command applied and `false` when it did not, so a host can let the key go on to something else:

- Always `true`: `Motion`, `Selection::All`, `Selection::Word`, `Selection::Line`, `Carets::AddAbove`, `Carets::AddBelow`, every `Box` and `Deletion` command, `Whitespace::Tab`, `Copy::Selection`, `Clip::Cut` and `Clip::Paste` — even when there was nothing to delete or copy.
- `false` when there was nothing to do: `Carets::Collapse` and `Carets::RemoveLast` with one caret; the bracket and quote `Selection` commands with no target; `AddNextOccurrence`, `SkipOccurrence` and `SelectAllOccurrences` without a match; `AddPerLine` when no selection spans lines; `Transform::DuplicateSelection` and the case transforms without a selection to change; `Sort`, `Reverse`, `Unique`, `Join` and `TrimTrailingWhitespace` when the lines did not change; `Clip::PastePrevious` without an active paste or older entry; `Whitespace::NewLine` and every `Lines` command when the text did not change (`ToggleComment` also without a `comment` in the style); `UndoRedo` with nothing to undo or redo, or without a history; `Recall::Back` with no older entry and `Recall::Forward` when not browsing.
- `false` for every command whose enum edits while the document refuses user edits.

Notes on individual commands:

- `Up`, `Down`, `PageUp` and `PageDown` remember the column a caret started in, so moving through a short line and on to a long one returns to that column. Any other move or edit forgets it.
- `SmartRowStart` goes to the first non-blank cluster of the row, or to the row start when already there.
- `InsideBrackets` and `AroundBrackets` select the innermost balanced pair around every caret, excluding or including its delimiters. The quote equivalents pair unescaped single or double quotes on one line.
- `DuplicateSelection` inserts a copy immediately after every nonempty selection and selects the copies, preserving their direction. Empty carets stay unchanged.
- `Tab` inserts the style's indent. With `LineEditing` included, it indents every line instead when a selection spans lines. `Outdent` removes one indent, a leading tab, or up to that many spaces.
- `ToggleComment` comments every non-blank line under the carets at their shallowest indentation, or uncomments them when all are commented. It needs a `comment` in the style.
- `MoveUp`, `MoveDown`, `Indent`, `Outdent`, `ToggleComment`, `Duplicate` and `Delete` act once per block of lines under the carets.
- `AddNextOccurrence` first selects the word under an empty caret. `SkipOccurrence` moves the most recent caret on to the next occurrence. `SelectAllOccurrences` puts a caret on every occurrence of the selection, or of the word under the caret.
- `SubwordLeft` and `SubwordRight` stop at camelCase humps, underscores and the start of a word, so `fooBar_baz` has four stops.
- `Sort`, `Reverse`, `Unique` and `TrimTrailingWhitespace` act on the whole block of lines under the carets. `Join` joins the block, or the next line when a caret is empty.
- `UpperCase`, `LowerCase` and `TitleCase` transform each selection and keep it selected.
- `AddPerLine` puts a caret at the end of every line a selection spans.
- `PastePrevious` replaces the immediately preceding paste with the next older clipboard entry; repeated calls keep cycling. Moving, editing or starting another paste ends that session.
- `Box` grows a rectangular selection from the primary caret. `start_box(row, column)`, `select_box(anchor_row, anchor_column, head_row, head_column)` and `clear_box` let a host drive it from a pointer; `box` returns the current corners.

Typing is not a command: send `insert(text)`. Pressing Enter in a single-line field is not a command either; the host decides what it means.

### Typing aids

With `auto_close` on, typing `(`, `[`, `{`, `"` or `'` inserts the pair and leaves the caret between them; with a selection it wraps the selection and keeps it selected. Typing a closing character in front of the same character steps over it, a quote typed right after a word stays single, and `Deletion::Backward` between an empty pair removes both. Pasted text is never paired. With `auto_indent` on, `NewLine` keeps the current line's leading whitespace.

## Interfaces

The host plugs in through these modules. Each is small, and all but `Graphemes` come with a default.

| Interface | Methods | Default |
| --- | --- | --- |
| `Graphemes` | `boundaries(text)`, optional `boundaries(bytes)`, `kind(cluster : Bytes)`, `width(cluster : Bytes)` | byte boundaries fall back to a string copy |
| `Filter` | `filter(text)` | `SingleLine`, `MultiLine(tab)` |
| `Clipboard` | `write(text)`, `read { \|text\| }` | `Register` (in memory) |
| `ClipboardHistory` | `size`, `read(index) { \|text\| }` | `Register` (100 entries) |
| `Layout` | `row_count`, `row_of`, `row_start`, `row_end`, `cell_of`, `offset_in`, `page_rows` | `LineLayout` (one row per line) |
| `History` | `record`, `undo`, `redo`, `can_undo?`, `can_redo?`, `modified?`, `mark_saved`, `clear` | `History::Linear` |
| `Constraint` | `admits?(origin)`, `capacity` | `ReadOnly`, `MaxLength` |
| `Listener` | `applied`, `edited`, `moved` | no-ops to override |
| `Follower` | `follow(change)` | `Decorations`, `Annotations` |
| `TokenSource` | `tokens(buffer, line)` | none |
| `Tokenizer` | `tokens(text)` | none |

**Graphemes.** `boundaries` returns the byte offset where each cluster starts, followed by the text's byte size, so `""` gives `[0]` and `"ab"` gives `[0, 1, 2]`. Implement the `String` form; the `Bytes` form is used for mapped lines and defaults to `boundaries(String.new(bytes))`, so existing producers keep working. Override it to index non-ASCII mapped lines without that temporary copy. `kind` returns a `ClusterKind` (`Space`, `Word`, `Punct` or `Other`), which drives word motion and deletion, word selection, smart Home, auto-indent and how typing is grouped for undo. `width` is the display width in columns. Clusters are passed as byte slices into the document's own storage, so a host can classify and measure them without allocating. Give the document the same measurements your renderer uses.

**Filters.** `SingleLine` turns line breaks and tabs into spaces and drops other control characters. `MultiLine.new(tab)` keeps line breaks and replaces tabs with `tab`. Any struct or class that includes `Filter` works, for example one that only lets digits through.

**Clipboard.** `read` takes a block so a clipboard can answer later, for example after asking a terminal; the paste happens when the block is called. `Register` also includes `ClipboardHistory`, keeping the newest 100 unique entries and exposing them through `entries`; `Register.new(limit: n)` changes that bound. Other clipboards can opt into `PastePrevious` by including `ClipboardHistory`.

**Layout.** `cell_of(offset)` returns a `Cell` (`column`, `row`) in display columns, and `offset_in(row, column)` goes back. A host that wraps lines implements `Layout` over its wrapped rows and assigns it with `view.layout = …`; vertical motion, paging (`page_rows`), smart Home, carets above and below and box selection then follow the wrapped rows.

**Listener.** `document.listen(listener)` returns a proc that removes it again.

- `applied(document, change)` runs for each `Change` as it lands, with the buffer in the state right after it. This is the place to update per-line caches such as wrapping.
- `moved(view)` runs whenever that view's carets change, including after every edit. The view it is given carries `view.document`.
- `edited(document, changes)` runs once per edit or transaction, after the carets are placed, with every change in the order it was applied. Undo reports the changes it applied.

**Follower.** `document.track(follower)` calls `follow(change)` for each change as it lands, after the marks and before the views and listeners, and returns a proc that stops it.

**TokenSource.** Anything that can return the tokens of a line in a buffer includes `TokenSource`, so a renderer takes a source without knowing what produced it. `Asekii::Syntax::Highlighter` from [asekii-editor](https://github.com/shpeckman/asekii-editor) is one. A `Token` is a `start`, a `count` and a `kind`, with columns counting clusters, and `TokenSource::NO_TOKENS` is the shared empty result.

**Tokenizer.** Anything that can tokenize standalone text, with no document behind it, includes `Tokenizer`: `tokens(text)` returns one array of `Token` per line. This is what a renderer needs for a fenced code block or any other snippet it holds as a string. `Asekii::Syntax::Tokenizer` is one.

## Buffer and changes

`document.buffer` stores UTF-8 lines with their grapheme-cluster boundaries and converts between lines, cluster offsets and byte offsets. String-backed lines retain their string; mapped lines retain the mapping and materialize `text` only on demand. A line whose bytes are all ASCII maps byte and cluster columns directly; `line.ascii?` reports this. Lines over 64 KiB use cluster-aligned pieces, reported by `line.chunked?`. `each_chunk` reads those pieces without flattening the line. Host-defined Unicode segmentation can require a boundary rebuild after an edit.

```crystal
buffer = text.buffer
buffer.line_count
buffer.position(42)          # Textedit::Position(line, column)
buffer.offset(position)
buffer.line_start(3)
buffer.line(3)               # Textedit::Line: text, to_slice, mapped?, chunked?, size, ascii?, cluster(column), bytes(column), boundary(column), slice(from, to), each_cluster, each_chunk
buffer.width(3, 0, 10)       # display width of columns 0...10 on line 3
buffer.index(3, 12)          # the column under display column 12 on line 3
buffer.leading(3)            # how many whitespace clusters line 3 starts with
buffer.blank?(3)             # whether line 3 is empty or only whitespace
buffer.indentation(3)        # display width of line 3's leading whitespace, nil for a blank line (indent guides, hanging wraps)
buffer.find("needle", 10)    # next literal match as a cluster range, wrapping around
buffer.find_all("needle")
buffer.revision              # how many edits the buffer has seen
buffer.changes_since(7)      # the Changes since a revision, or nil when the journal does not reach back
```

Byte offsets are available alongside cluster offsets for parsers and language servers that count bytes:

```crystal
buffer.bytesize              # the text's size in bytes, with \n line breaks
buffer.byte_offset(42)       # cluster offset → byte offset
buffer.offset_at_byte(97)    # byte offset → cluster offset (rounded down; ceil: true rounds up)
buffer.line_byte(3)          # the byte offset where line 3 starts
buffer.byte_position(97)     # Textedit::Position(line, byte within the line)
buffer.byte_text(10, 20)     # the text between two byte offsets
buffer.chunk(97)             # the rest of that line as Bytes, "\n" at a line end, empty at the end
buffer.each_chunk(97) { |bytes| consume(bytes) } # contiguous pieces without flattening
```

`chunk` returns the rest of the line and can flatten a chunked line. `each_chunk` yields the same text as contiguous pieces instead, including `"\n"` at a line end. `Line#text` and `Line#to_slice` also flatten on demand.

**Units and points.** Other tools count positions in other units. `Textedit::Units` is `Bytes`, `Utf16`, `CodePoints` or `Clusters`, and a `Point` is a line and a column in one of them:

```crystal
point = buffer.point(42, Textedit::Units::Utf16)    # Textedit::Point(line, column in UTF-16 code units)
buffer.offset_at(point, Textedit::Units::Utf16)     # back to a cluster offset (a column inside a cluster rounds down)
buffer.measure("é👍", Textedit::Units::Utf16)       # => 3
buffer.line(3).units(Textedit::Units::Bytes, 0, 5)  # the size of columns 0...5 in bytes
```

A `Change` records `from`, the `removed` and `inserted` text, and their sizes in clusters; `removed_lines` and `inserted_lines` count line breaks. `start_point(buffer, unit)`, `old_end_point` and `new_end_point` describe where it starts and where it ended before and after, as a language server or an incremental parser expects; call them from `Listener#applied`, while the buffer is in the state right after the change. When an edit merges with a neighbouring cluster — a combining accent typed after a letter — the change is widened to whole clusters, so undoing it is exact.

`replace_ranges` applies several `Edit`s (a range and its new text) as one undo step:

```crystal
view.replace_ranges([Textedit::Edit.new(0...3, "one"), Textedit::Edit.new(10...10, "!")])
document.replace_ranges(edits)     # no view: every view's carets follow the text
```

On a view it moves that view's carets with the text. Its text is used as given, without the filter, and it counts as an edit from `Code`.

## Decorations

A decoration marks a range of the text with a `kind` and a `message`, for example a compiler error. Its edges move with edits like marks do, without growing when text is typed right at them, and a decoration whose range shrinks to nothing remains, empty, until it is replaced. A `Decorations` store follows the document it is made for:

```crystal
diagnostics = Textedit::Decorations.new(document)
diagnostics.replace("lsp", [Textedit::Decoration.new(4...9, "error", "undefined method")])
diagnostics.entries             # every decoration, sorted by start
diagnostics.between(0, 20)      # those overlapping 0...20
diagnostics.at(6)               # those covering offset 6
diagnostics.replace("lsp", [] of Textedit::Decoration)   # clears that source's decorations
diagnostics.listen { redraw }   # returns a proc that removes the block
diagnostics.close               # stops following the document
```

Each `replace` replaces every decoration from the same `source`, so several producers can share one store, and calls its listeners.

## Annotations

An annotation is text shown beside the document rather than in it — an inlay hint, a git blame, a line note. Its offset follows edits like a mark, and each source replaces its own set, as decorations do.

```crystal
hints = Textedit::Annotations.new(document)
hints.replace("lsp", [Textedit::Annotation.new(7, ": Int32", Textedit::Placement::After, "type")])
hints.entries                  # every annotation, sorted by offset
hints.between(0, 20)           # those between two offsets
hints.at(7)
hints.on(3)                    # those on line 3
hints.replace("lsp", [] of Textedit::Annotation)   # clears that source
```

`Placement` is `Before`, `After` or `RowEnd`, and decides which side of the offset the host draws the text on; a `Before` annotation keeps its place when text is typed at it, the others move with it. `listen` and `close` work as they do for decorations.

## Folding

`Folding` gives a view its own folds, so two panes can fold a document differently. A fold is a line range held by marks, so it follows edits.

```crystal
folds = view.folds
folds.fold(2, 8)             # collapsed by default; nil for an empty or out-of-range range
folds.collapsed?(2)          # the header line
folds.hidden?(5)             # a line inside a collapsed fold
folds.toggle(2)
folds.expand(2)
folds.unfold(2)
folds.rows                   # the visible lines, in order
folds.replace([{0, 4}, {6, 9}])   # every fold at once, as a query would supply them
folds.clear
view.lift_carets             # moves carets on hidden lines to the end of the visible line above; false when none was hidden
```

`LineLayout` consults the view's folds, so `row_count`, vertical motion, paging, smart Home and carets above and below all skip hidden lines. A host with its own `Layout` overrides `Layout#folds=` (a no-op by default) to receive them: the view hands its folds to the layout when they are first made and to every layout assigned later. `folds.revision` increments after fold-set mutations, so a layout can tell when to recount its rows. `view.folds` creates the set on first use and `view.folds?` tells whether one exists.

## Snippets

A snippet is text with tabstops. `Snippet.parse` turns LSP snippet syntax into plain text plus stop spans, and `Snipping#insert_snippet` inserts it and selects the first stop.

```crystal
snippet = editor.insert_snippet("def ${1:name}($2)\n  $0\nend")
editor.selected_text        # => "name"
editor.insert("run")        # fills the stop
snippet.next_stop(editor)
snippet.previous_stop(editor)
snippet.active?
snippet.close               # drops its marks
```

- `$1`, `${1}`, `${1:placeholder}`, `$0` (the final stop), `${1|one,two|}` (the first option) and `\$` are understood. A `${VAR:default}` resolves to its default and an unknown `$VAR` to nothing.
- A stop that appears more than once becomes one caret per occurrence, so typing fills every mirror at once.
- The stops are held by marks, so filling an early stop carries the later ones.
- Inserting a snippet replaces the primary caret's selection as one undo step. A snippet with no stops is inserted and `nil` comes back.

## Diffing

`Textedit.diff` turns an old and a new text into line-oriented edits, for `replace_ranges`:

```crystal
view.replace_ranges(Textedit.diff(view.value, formatted, graphemes))
```

The carets, marks, decorations and annotations outside the changed lines stay where they are, which is what `value=` cannot do. Common leading and trailing lines stay untouched; past `limit` lines of difference it falls back to one edit covering the changed region.

## Opening and saving a file

`Storage` ties a document to a file: its `path`, whether to end the file with a line ending (`final_newline`), `export`, and `save`. `Storage.open` keeps a read-only mapping of the file and finds the lines in its bytes. Unchanged lines and long-line pieces stay in the mapping with no per-line string; edits create ordinary string-backed pieces only for changed storage.

```crystal
storage = Textedit::Storage.open(graphemes, "src/app.cr", filter: Textedit::MultiLine.new)
storage.document.buffer.mapped?       # true
storage.document.buffer.line(0).to_slice  # read-only Bytes into the mapping
storage.document.line_ending          # taken from the file
editor = Textedit::Editor.new(storage.document)
editor.move(0)

editor.insert("// edited\n")
storage.save                 # writes path and marks the document saved
storage.save("other/app.cr") # save-as; updates path
storage.export               # the text with the document's line ending

Textedit::Storage.new(document, "notes.txt", final_newline: true)   # for a document built from text
```

`Storage.open` takes the `Document` options as well. `save` writes atomically and preserves existing destination permissions. The live source mapping is never truncated, and a failed save leaves the destination, path and document's save point unchanged. Saving without a path requires an explicit one.

`Textedit::Mapped` is the mapping itself, for a host that wants the bytes:

```crystal
Textedit::Mapped.open(path) do |mapped|
  mapped.bytesize
  mapped.bytes            # a read-only Bytes view; invalid once closed
  mapped.sequential       # tells the kernel the reads will be sequential
end

Textedit::Mapped.open(path, writable: true) do |mapped|
  mapped.bytes[0] = 'x'.ord.to_u8  # MAP_SHARED: writes reach the file
end
```

Mappings need a POSIX system and refuse a file larger than `Int32::MAX`. A persistent mapping is released once its buffer and extracted lines are no longer referenced. Do not truncate a mapped file externally while it is in use. String-returning operations such as `value`, regex search, and line transforms still allocate; byte chunks, motion, and literal search do not need to materialize mapped lines.

## Revisions

`Buffer#revision` counts edits, and the buffer keeps the last 256 of them. `Document#map` carries an offset or a range from an older revision to the current one, for a result that arrives late:

```crystal
mark = document.revision
# … a language server answers three keystrokes later …
document.map(offset, mark)    # => the offset now, or nil if the journal no longer reaches back
document.map(range, mark)     # a range, which does not grow at its edges
```

## Find and replace

`Search` finds matches in a buffer, case-insensitively by default, with optional whole-word and regular-expression modes. Matches are grapheme-cluster ranges, and multiline-capable regular expressions can match across line breaks. `Finding` selects matches; `Replacing` changes them.

```crystal
search = Textedit::Search.new("(\\w+)=(\\d)", regex: true)
found  = editor.find(search)                          # selects the next match
editor.replace_match(search, found.not_nil!, "$2=$1") # only if that match is still selected
editor.find(search, backward: true)                   # selects the previous match
editor.replace_all(search, "$2=$1")                   # one undo step; returns the count
editor.add_caret_at_every_match(search)               # a caret on every match
search.error                                          # the message for an invalid pattern
```

`Selecting#brackets` returns the offsets of the bracket pair beside an empty primary caret.

## Tokens

textedit defines the token vocabulary and the two interfaces that carry it; it produces no tokens itself.

```crystal
Textedit::Token.new(0, 3, "keyword")   # start, count, kind — columns count clusters
```

A `TokenSource` serves one line of a buffer and is what a renderer reads through:

```crystal
session = Asekii::Syntax::Session.new(text, Asekii::Syntax::Languages["crystal"])
syntax  = Asekii::Syntax::Highlighter.new(session)   # includes Textedit::TokenSource
syntax.tokens(text.buffer, 3)                         # => Array(Textedit::Token)
```

A `Tokenizer` serves standalone text, one array of tokens per line, for a snippet with no document behind it:

```crystal
marker = Asekii::Syntax::Tokenizer.new(Asekii::Syntax::Languages["crystal"], graphemes)   # includes Textedit::Tokenizer
marker.tokens("def f\nend")                                                              # => [[Token], [Token]]
```

To examine text outside a document, build a line with `Textedit::Line.new(text, graphemes)`.

## Input recall

`Recollection` keeps the entries submitted from a single-line field and steps through them, remembering the draft:

```crystal
past = Textedit::Recollection.new(limit: 100)
past.push("ls")
past.back("dra")   # => "ls"
past.forward       # => "dra"
```

`Recalling` puts one behind a view, so recall is a command like any other. `Recall::Back` replaces the text with the previous entry and `Recall::Forward` with the next one, ending on the draft; each is one undo step, and the caret goes to the end. What Enter means stays with the host, which pushes the entry itself:

```crystal
prompt = Textedit::Field.new(graphemes)
prompt.run(Textedit::Recall::Back)         # bound to Up, for example
prompt.recollection.push(prompt.value)     # on Enter
prompt.clear

search = Textedit::Field.new(graphemes)
search.recollection = prompt.recollection  # share the entries between fields
```

The recollection is made on first use, so a field that never recalls carries none.

## Macros

`Recording(C)` records the commands and the text a view receives into a `MacroLog(C)`, and replays them:

```crystal
editor.record
editor.run(Textedit::Motion::RowEnd)
editor.insert(";")
editor.stop

editor.replay              # once, as one undo step
editor.replay(10)          # ten more times
editor.macros.entries      # Array(Editor::Command | String)
```

A replay records nothing itself, and each pass is one undo step. `editor.macros = …` swaps the log, for example to share one between views of the same type.

## Development

```sh
crystal spec
crystal docs
```

The specs drive the presets directly, with a small `Graphemes` built on the standard library in `spec/spec_helper.cr`. `History::Linear` takes an optional clock, which the specs use instead of sleeping.

## License

MIT
