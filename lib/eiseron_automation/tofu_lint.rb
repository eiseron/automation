# frozen_string_literal: true

module EiseronAutomation
  class TofuLint
    SKIP_DIRS = %w[.terraform .git].freeze

    def initialize(root: ".", io: $stdout)
      @root = root
      @io = io
    end

    def run
      violations = self.class.find_comments(tf_files)
      unless violations.empty?
        listed = violations.join("\n")
        raise Error, "comments are not allowed in .tf files; move rationale to the MR description:\n#{listed}"
      end

      @io.puts "tofu lint: clean"
    end

    def tf_files
      Dir.glob(File.join(@root, "**", "*.tf")).reject { |path| self.class.skip?(strip_root(path)) }.sort
    end

    def strip_root(path)
      rel = path.sub(%r{\A\./}, "")
      prefix = @root.sub(%r{\A\./}, "").chomp("/")
      return rel if prefix.empty? || prefix == "."

      rel.sub(%r{\A#{Regexp.escape(prefix)}/}, "")
    end

    def self.skip?(path)
      SKIP_DIRS.any? { |dir| path == dir || path.start_with?("#{dir}/") || path.include?("/#{dir}/") }
    end

    def self.find_comments(files)
      files.flat_map do |file|
        scan(File.read(file, encoding: Encoding::UTF_8)).map { |line_no| "#{file}:#{line_no}" }
      end
    end

    def self.scan(content)
      heredoc = nil
      content.lines.each_with_index.filter_map do |line, idx|
        if heredoc
          heredoc = nil if line =~ /\A\s*#{Regexp.escape(heredoc)}\s*\z/
          next
        end
        heredoc = heredoc_terminator(line)
        (idx + 1) if comment?(line)
      end
    end

    def self.heredoc_terminator(line)
      return unless (match = line.match(/(?:^|[\s=(,])<<[-~]?"?([A-Za-z_]\w*)"?\s*\z/))

      match[1]
    end

    def self.comment?(line)
      code = strip_literals(line)
      code.include?("#") || code.include?("//") || code.include?("/*")
    end

    def self.strip_literals(line)
      line.gsub(/"(?:\\.|[^"\\])*"/, '""')
    end
  end
end
