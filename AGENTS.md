# AGENTS.md

Orientation for AI agents working on this repository.

## What this is

`textedit` is a Crystal shard holding a multi-caret text editing model built from composable features: a grapheme-cluster buffer, a `Document` with swappable services (history, constraints, filter, style, marks, followers), and `View`s that include only the feature modules a widget needs — typing, deleting, line editing, transforms, selection, multiple carets, box selection, clipboard, undo, find, replace, folding, snippets and macro recording. It produces no syntax tokens of its own: it defines the `Token` value and the `TokenSource`/`Tokenizer` interfaces, and a host plugs in a producer such as asekii-editor's `Asekii::Syntax::Highlighter`. It draws nothing and reads no input. Hosts (for example the `tui` shard) plug in through interfaces, pick a preset or compose their own view, and drive it with per-feature command enums. It has no dependencies beyond the standard library, and must stay that way.

## Layout

- `src/textedit.cr` — requires every file in load order. History implementations come after `history.cr`, feature modules come after `view.cr`, and `presets.cr` comes last because `include` needs the module defined.
- `src/textedit/values.cr` — the small value types: `Position`, `Point`, `Cell`, `Edit`, `Stroke`, `Gravity`, `Gesture` (how an edit groups for undo), `Origin` (`User`, `Code`, `Undo`, `Redo`), `Style` (indent, tab size, comment prefix), `LineEnding`, and `Units` (bytes, UTF-16, code points, clusters).
- `src/textedit/line.cr` — `Line`: one line of UTF-8 bytes plus, only when it needs one, its cluster byte boundaries and a lazily materialized `String`. Short lines keep one slice; lines over `CHUNK` use immutable cluster-aligned pieces with `Index` prefix lookups. An all-ASCII line stores no boundaries and maps column to byte with the identity; everything goes through `boundary`, `byte_at` and `column_at`, never a raw marks array. Pieces retain their `String` or `Mapped` owners. `text` and `to_slice` flatten on demand; `each_chunk` avoids it.
- `src/textedit/index.cr` — `Index`: the line-offset structure. Weights live in blocks of at most `LIMIT`, with two Fenwick trees over the blocks (one of line counts, one of weight sums), so `prefix`, `locate`, `set`, `insert` and `drop` are logarithmic in the block count plus a scan inside one block. Only a block split or an emptied block rebuilds the trees. `spec/index_spec.cr` holds a differential test against a naive array over 3000 random edits; extend it rather than reasoning about the structure by hand.
- `src/textedit/mapped.cr` — `Mapped`: a POSIX `mmap` of a file, private/read-only by default or shared/read-write with `writable: true`, with `bytes`, `sequential` and an idempotent `close`. `Buffer.map` and `Storage.open` retain the read-only mapping; `Storage#save` uses a block-scoped writable mapping.
- `src/textedit/buffer.cr` — `Buffer`: the lines, their optional persistent mapping, and two `Index`es over them, one in clusters and one in bytes (each weight is the line's size plus its separator); cluster-aligned piece-splicing `replace`, line-by-line literal `find` over bytes, leading whitespace (`leading`, `blank?`, `indentation`), byte and unit mapping (`byte_offset`, `offset_at_byte`, `byte_text`, `chunk`, `each_chunk`, `point`, `offset_at`), a journal of touched lines carrying each `Change`, and `changes_since`.
- `src/textedit/caret.cr`, `change.cr`, `mark.cr` — caret ranges with an optional goal column, one reversible replacement (with its start and end points in any unit), and offsets that follow changes.
- `src/textedit/brackets.cr` — `Brackets`: the shared pair tables (`PAIRS`, `CLOSING`, `OPENERS`, `CLOSERS`) and the scan `REACH` that typing, deleting, transforms and selection all read.
- `src/textedit/decoration.cr`, `annotation.cr` — `Decoration` and `Annotation` values, and the `Decorations` and `Annotations` stores: `Follower`s made for one document, replaced per source, with `entries`, `between`, `at` (and `on` for annotations), proc `listen` and `close`.
- `src/textedit/folds.cr` — `Folds`: collapsible line ranges held by document marks, owned by a view that includes `Folding`; `LineLayout` consults them so motion skips hidden lines; `revision` increments after fold-set mutations.
- `src/textedit/constraint.cr` — `Constraint` (`admits?(origin)`, `capacity`, both defaulted, plus `Constraint.capacity(list)`), `ReadOnly` (toggleable `active?`, admits only `Code`) and `MaxLength`.
- `src/textedit/history.cr` — `Commit` (gesture, origin, changes, carets before and after), the `History` interface with `History::Restore` (edits to apply in order and carets to seat), `Grouping` (`Adjacent` and `Never`), and `History::Linear`: undo and redo stacks, configurable grouping, a save point, an injectable clock, and no buffer access. It ignores `Undo` and `Redo` commits.
- `src/textedit/history/tree.cr` — `History::Tree`: linked commit nodes preserve redo branches after new edits, `choose` selects an immediate child for redo, and save points use node identity. Nodes are retained until `clear`.
- `src/textedit/history/journal.cr` — `History::Journal`: an append-only event log over a tree, retaining raw `Undo` and `Redo` commits, save points, clears and branch choices. Optional JSON-lines persistence replays grouped decisions and discards only an incomplete trailing event; wire records are `:nodoc:` because `JSON::Serializable` cannot expand over private constants.
- `src/textedit/snippet.cr` — `Snippet`: the LSP snippet parser (`Snippet::Parser`) producing a `Template`, and the live session holding each stop as a pair of marks. Mirrored stops become several carets, so typing fills them together.
- `src/textedit/diff.cr` — `Diff.hunks` (a Myers line diff with common ends trimmed and a fallback past `limit`) and `Textedit.diff`, which turns two texts into `Edit`s in the old text's cluster offsets.
- `src/textedit/macro_log.cr` — `MacroLog(C)`: the entries (`C | String`) a `Recording(C)` view takes down; the replay itself lives in `Recording`, because it needs the concrete view type to dispatch.
- `src/textedit/search.cr` — regex and literal search; literals and regexes conservatively proved line-local are kept per line and updated from the buffer's journal. Multiline-capable or uncertain regexes rescan the whole text.
- `src/textedit/token.cr`, `token_source.cr` — the `Token` value (start, count, kind; columns count clusters), and the two interfaces that carry it: `TokenSource` (`tokens(buffer, line)`) and `Tokenizer` (`tokens(text)`). Neither has an implementation here.
- `src/textedit/recollection.cr` — `Recollection`: input history for single-line fields (entries, browsing index, draft).
- `src/textedit/document.cr` — `Document`: built from a `String` or a `Buffer`; the text, `filter`, `history`, `constraints` (`admits?`, `capacity`), `style`, `line_ending`, marks, followers (`track`), listeners, views, transactions, dirty tracking (`modified?`, `mark_saved`, by history or by revision), revision mapping (`map`), and the edit pipeline: `apply` (user strokes), `replace_ranges` (structural, any origin), `assign` (behind `value=`), and the private `revert` (undo and redo through the history's `Restore`). Every path builds a `Commit` for the history.
- `src/textedit/storage.cr` — `Storage`: a document's `path` and `final_newline`, `Storage.open` (mapped), `export`, and the atomic writable-mmap `save`.
- `src/textedit/view.cr` — `View` core and the `Motion` enum: carets, primary index, layout, `dragging?`, `View.new(graphemes, text, **options)` merged over `self.defaults`, `value`/`value=`, motion, `move_carets`, `select_range`, `place_carets`, `add_caret`, `replace_ranges`, `transaction`, `seat` (which places carets and tells listeners), `follow` (carries this view's carets through a change another view made), the private hooks features override (`commanded`, `typed`, `pasted`, `selected`, `pairing?`), `enter` (the edit gate every `run` calls), `put` and `revise`.
- `src/textedit/view/motion.cr` — caret geometry shared by the features: steps, word and subword edges, smart start, vertical motion, `word_at`, `kind_at`, `char_at`, `blocks`.
- `src/textedit/features/` — one file per feature, each holding its command enum (with `edits?`) next to its module:
  - `typing.cr` — `Typing`: `insert`, `paste`, `auto_close?`, pairing.
  - `deleting.cr` — `Deletion`, `Deleting`.
  - `spacing.cr` — `Whitespace`, `Spacing`: new line with `auto_indent?`, tab.
  - `line_editing.cr` — `Lines`, `LineEditing`: indent, outdent, comments, moving, duplicating and deleting lines; overrides `tab` for a multi-line selection.
  - `transforming.cr` — `Transform`, `Transforming`: duplicate selection, sort, reverse, unique, join, trim, case, `surround`, `unsurround`.
  - `selecting.cr` — `Selection`, `Selecting`: select all, word, line, bracket and quote objects, `brackets`.
  - `multicaret.cr` — `Carets`, `Multicaret`: collapse, occurrences, carets above, below and per line, remove last.
  - `boxing.cr` — `Box`, `Boxing`: box selection and its corners.
  - `copying.cr` — `Copy`, `Copying`: clipboard properties, copy, auto-copy on `selected`.
  - `pasting.cr` — `Clip`, `Pasting`: cut, paste, paste cycling and its session.
  - `undoing.cr` — `UndoRedo`, `Undoing`.
  - `finding.cr`, `replacing.cr` — `Finding` (`find`, `add_caret_at_every_match`) and `Replacing` (`replace_match`, `replace_all`).
  - `folding.cr`, `snipping.cr`, `recording.cr` — `Folding`, `Snipping` (`insert_snippet`), `Recording(C)`.
  - `recalling.cr` — `Recall`, `Recalling`: steps the view's text through a lazily made `Recollection`.
- `src/textedit/presets.cr` — `Field`, `Area`, `Reader` and `Editor`, each with its `Command` union and `self.defaults`.
- Interfaces the host implements, each with its defaults:
  - `graphemes.cr` — `Graphemes` and `ClusterKind`; string boundaries are abstract, and byte boundaries default to one temporary string copy.
  - `filter.cr` — `Filter`, `SingleLine`, `MultiLine`.
  - `clipboard.cr` — `Clipboard`, optional `ClipboardHistory`, and the bounded in-memory `Register`.
  - `layout.cr` — `Layout` (with a no-op `folds=` a host layout overrides to receive the view's folds), `LineLayout`.
  - `listener.cr` — `Listener` with no-op `applied`, `edited` and `moved`, and `Follower`.
  - `history.cr` — `History`; `constraint.cr` — `Constraint`.
  - `token_source.cr` — `TokenSource` and `Tokenizer`; implemented outside this shard, for example by asekii-editor's `Asekii::Syntax::Highlighter` and `Asekii::Syntax::Tokenizer`.
- `spec/` — one file per area; `spec/editing_spec.cr` covers the commands and `spec/composition_spec.cr` the presets, host widgets and host histories. `spec/spec_helper.cr` defines a standard-library `Graphemes` (`Plain`), deferred clipboards, a recording listener, and the `buffer`, `line`, `editor` (an `Editor` with `SingleLine`), `lines`, `code`, `heads` and `change` helpers.

## Commands

- `crystal spec` — run the suite.
- `crystal spec spec/editing_spec.cr` — run one file.
- `crystal build --no-codegen src/textedit.cr` — fast compile check. It instantiates nothing, so run the specs to type-check feature modules.
- `crystal docs` — generate API documentation and review the public surface.

## Rules

- Offsets count grapheme clusters, and a line break counts as one. Text inside the buffer always uses `\n`; other endings live only in `Document#line_ending` and `Storage`.
- `Graphemes#boundaries` returns cluster start offsets plus the byte size; clusters reach `kind` and `width` as byte slices into the line, so never allocate a `String` per cluster on a hot path. Buffer read paths use `Line#each_chunk`; `Line#to_slice` is for contiguous compatibility and `Line#text` only when a `String` is genuinely required.
- Both buffer `Index`es change together in `replace_lines`; piece prefix lookups and any new per-line weight also go through an `Index` rather than a new copy of the tree code. `Buffer` never touches a Fenwick array directly.
- `@lines` is still a flat `Array(Line)`, so an edit that changes the line count memmoves it. Long lines use shared pieces, and ordinary ASCII splices avoid rebuilding or flattening the line. Arbitrary host grapheme rules can still force a full-line boundary rebuild; never assume bounded Unicode resynchronization.
- Mapped lines and their `Bytes` are read-only and retain the mapping owner. Edits create ordinary string-backed pieces and can share unchanged mapped pieces; never mutate mapped storage or close the persistent mapping explicitly. `mapped?` is true only for wholly mapping-backed, unedited lines.
- `Storage#save` writes a same-directory temporary file through a shared writable mapping, closes it, then renames it. Never truncate or overwrite the file a live buffer is reading; update `path` and the document's save point only after a successful rename.
- Positions for other tools go through `Units`, `Buffer#point`/`offset_at` and `Change#start_point`/`old_end_point`/`new_end_point`; never count bytes or UTF-16 units by hand elsewhere.
- `Buffer#replace` widens a change to whole clusters when an edit merges with a neighbour. Never assume `inserted_size` equals the cluster count of the text passed in; place carets from the returned `Change`.
- All grapheme, width, clipboard, layout, tokenizing, history and input-filtering knowledge comes through the interfaces. Never add a dependency on a terminal or width library, and never add a tokenizer, highlighter or language table here: `Token`, `TokenSource` and `Tokenizer` are the whole surface, and producers live in their own shards.
- A feature is a module in `src/textedit/features/` with its command enum in the same file. New editing behaviour is a member of the enum it belongs to, handled in that module's `run`, with `edits?` true on the enum when its commands change text; a behaviour that needs its own capability is a new feature file, a line in `src/textedit.cr`, a row in the README's feature table, and inclusion in the presets that should have it. Add specs in `spec/editing_spec.cr` and a line in the README's command notes.
- Every `run` overload takes `(command : TheEnum, selecting : Bool = false) : Bool` and starts with `return false unless enter(command)`, so the edit gate and the `commanded` hook stay in one place.
- An enum is either all-edit or all-motion. A command that edits does not belong in a non-editing enum, because `Reader`-style views must not compile it.
- `run` returns whether the command applied; keep the README's list of which commands can return `false` accurate.
- Features talk to each other only through the core hooks on `View` (`commanded`, `typed`, `pasted`, `selected`, `pairing?`), overriding them as `private def …; super; …; end`. A feature that genuinely needs another one says so in `macro included` with a `{% raise %}`; never `include` one feature from another, because Crystal does not dedupe a repeated include and the `super` chain then recurses forever.
- Instance variable declarations and initializers in a feature module resolve constants in the including class's scope, which may be outside `Textedit`. Write their types and initial values fully qualified (`::Textedit::Register.new`). Method bodies and signatures resolve lexically and need no prefix.
- Listener order is fixed: followers and views follow each change, then `applied` for each change as it lands, then `moved` once the carets are placed, then `edited` with the whole batch. Inside a transaction, `moved` (once per view that moved) and `edited` are held until it ends. `moved` takes the `View` whose carets moved, not the document.
- Anything that changes the text goes through `Document#apply` (user strokes, which honour `admits?(User)` and `capacity`), `Document#replace_ranges` (structural edits, gated by `admits?(origin)`), `Document#assign` (`value=`) or `revert` (undo and redo). Each records one `Commit` for the history and notifies listeners. Never call `Buffer#replace` directly from new code. A view's own structural edits go through its private `revise` (origin `User`); the public `replace_ranges` is `Code`.
- The split is the rule: text, history, constraints, style, marks and followers belong to the `Document`; carets, the goal column and the layout belong to the `View` core; everything else a view does belongs to a feature module. Decorations, annotations and file storage are standalone objects over a document.
- Every edit names the view that made it, or none. `Document#applied` carries the other views' carets with `View#follow` and skips the acting one; with no acting view every view follows. A new edit path sets `@acting` the same way.
- `Document`'s internals that a `View` or feature needs (`apply`, `assign`, `prepare`, `count`, `attach`, `detach`, `stirred`) are `protected`, which Crystal allows from any type in the `Textedit` namespace, including methods a host class inherits from a feature module. Keep them protected rather than widening the public API.
- A preset's document defaults live in its `self.defaults` named tuple; caller options override them through `merge`.

## Code standards

- Compiler-friendly, performance-focused, idiomatic Crystal.
- Data-driven design: tables and records over branching logic.
- Every file starts with a comment holding its path (`# src/textedit.cr`).
- Comments are sparse, but public API gets comments for `crystal docs` (~/.lib/doc-lib/crystal/documenting_code.md).
- The user-facing API must be ergonomic.
- Avoid shotgun surgery: one change, one place.
- Breaking API is fine when it buys a clean design; list what breaks.
- No stubs or placeholders; don't add functionality nobody asked for.
- Don't change the version in shard.yml.
- Keep README.md in sync with the code.
