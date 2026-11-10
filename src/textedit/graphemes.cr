# src/textedit/graphemes.cr
module Textedit
  # Host-defined grapheme classification used by editing and motion.
  enum ClusterKind
    Other
    Space
    Word
    Punct
  end

  # Supplies grapheme segmentation, classification, and display measurement.
  module Graphemes
    # Returns cluster-start byte offsets followed by the text's total byte size.
    #
    # Empty text returns `[0]`; `"ab"` returns `[0, 1, 2]`.
    abstract def boundaries(text : String) : Array(Int32)

    # Returns cluster boundaries for UTF-8 *bytes*.
    #
    # The default makes one temporary string copy. Override it to segment mapped
    # bytes directly.
    def boundaries(bytes : Bytes) : Array(Int32)
      boundaries(String.new(bytes))
    end

    # Returns the editing classification of one grapheme cluster.
    abstract def kind(cluster : Bytes) : ClusterKind

    # Returns the display width of one grapheme cluster in columns.
    abstract def width(cluster : Bytes) : Int32
  end
end
