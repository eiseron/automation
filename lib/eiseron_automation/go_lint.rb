# frozen_string_literal: true

module EiseronAutomation
  class GoRunner
    def run(*cmd)
      system(*cmd) || raise(Error, "command failed: #{cmd.join(' ')}")
    end

    def capture(*cmd)
      IO.popen(cmd, &:read)
    end
  end

  class GoLint
    SKIP_DIRS = %w[.cache vendor .git].freeze

    def initialize(root: ".", runner: GoRunner.new, io: $stdout)
      @root = root
      @runner = runner
      @io = io
    end

    def run
      check_gofmt
      @runner.run("go", "vet", "./...")
      @runner.run("golangci-lint", "run", "./...")
      check_comments
      @io.puts "go lint: clean"
    end

    def check_gofmt
      listed = @runner.capture("gofmt", "-l", @root).to_s.lines.map(&:strip).reject(&:empty?)
      bad = listed.reject { |path| self.class.skip?(strip_root(path)) }
      return if bad.empty?

      raise Error, "gofmt needed on:\n#{bad.join("\n")}"
    end

    def check_comments
      violations = self.class.find_comments(go_files)
      return if violations.empty?

      raise Error, "comments are not allowed in source; move rationale to the MR description:\n#{violations.join("\n")}"
    end

    def go_files
      Dir.glob(File.join(@root, "**", "*.go")).reject { |path| self.class.skip?(strip_root(path)) }.sort
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
      content.lines.each_with_index.filter_map { |line, idx| (idx + 1) if comment?(line) }
    end

    def self.comment?(line)
      return false if line.lstrip.start_with?("//go:")

      code = strip_literals(line)
      code.include?("//") || code.include?("/*")
    end

    def self.strip_literals(line)
      line
        .gsub(/"(?:\\.|[^"\\])*"/, '""')
        .gsub(/`[^`]*`/, "``")
        .gsub(/'(?:\\.|[^'\\])*'/, "''")
    end
  end
end
