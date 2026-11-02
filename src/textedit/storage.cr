# src/textedit/storage.cr
module Textedit
  class Storage
    getter document : Document
    getter path     : String?

    property? final_newline : Bool

    def self.open(graphemes : Graphemes, path : String, *, final_newline : Bool = false, **options) : Storage
      new(Document.new(graphemes, Buffer.map(graphemes, path), **options), path, final_newline: final_newline)
    end

    def initialize(@document : Document, @path : String? = nil, *, @final_newline : Bool = false)
    end

    def export : String
      String.build(export_size) do |io|
        each_export_chunk { |chunk| io.write(chunk) }
      end
    end

    def save(path : String? = nil) : Nil
      target = path || @path || raise ArgumentError.new("save needs a path for a storage without one")
      size   = export_size
      raise Mapped::Error.new("exported text is larger than this build can map") if size > Int32::MAX

      temporary = File.tempfile(".#{File.basename(target)}", ".tmp", dir: File.dirname(target))
      temp_path = temporary.path
      begin
        temporary.chmod(File.info(target).permissions) if File.exists?(target)
        temporary.truncate(size)
        temporary.close
        Mapped.open(temp_path, writable: true) do |mapped|
          bytes  = mapped.bytes
          offset = 0
          each_export_chunk do |chunk|
            chunk.copy_to(bytes[offset, chunk.size])
            offset += chunk.size
          end
        end
        File.rename(temp_path, target)
        @path = target
        @document.mark_saved
      rescue error
        temporary.close unless temporary.closed?
        File.delete(temp_path) if File.exists?(temp_path)
        raise error
      end
    end

    private def export_size : Int64
      buffer   = @document.buffer
      sequence = @document.line_ending.sequence
      breaks   = buffer.line_count.to_i64 - 1
      size     = buffer.bytesize.to_i64 + breaks * (sequence.bytesize - 1)
      final_break? ? size + sequence.bytesize : size
    end

    private def each_export_chunk(& : Bytes -> Nil) : Nil
      buffer = @document.buffer
      ending = @document.line_ending.sequence.to_slice
      last   = buffer.line_count - 1
      buffer.line_count.times do |index|
        buffer.line(index).each_chunk { |chunk, _start| yield chunk }
        yield ending if index < last
      end
      yield ending if final_break?
    end

    private def final_break? : Bool
      buffer = @document.buffer
      @final_newline && !buffer.empty? && !(buffer.line_count > 1 && buffer.line(buffer.line_count - 1).empty?)
    end
  end
end
