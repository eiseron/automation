# frozen_string_literal: true

module EiseronAutomation
  module CI
    class GitSource
      SEMVER = /\Av?\d+\.\d+\.\d+\z/

      def initialize(runner: CommandRunner.new)
        @runner = runner
      end

      def candidates(entry)
        url = Naming.git_url(entry[:source])
        self.class.parse(@runner.capture("git", "ls-remote", "--tags", url))
      end

      def finalize(entry, candidate)
        { repo: Naming.git_url(entry[:source]), ref: candidate[:ref], sha: candidate[:sha] }
      end

      def self.parse(output)
        peeled = peeled_shas(output)
        plain(output).map do |tag, sha|
          { version: tag.sub(/\Av/, ""), ref: tag, sha: peeled[tag] || sha }
        end
      end

      def self.plain(output)
        rows(output)
          .reject { |_sha, ref| ref.end_with?("^{}") }
          .map { |sha, ref| [ref.delete_prefix("refs/tags/"), sha] }
          .select { |tag, _sha| tag.match?(SEMVER) }
      end

      def self.peeled_shas(output)
        rows(output)
          .select { |_sha, ref| ref.end_with?("^{}") }
          .to_h { |sha, ref| [ref.delete_prefix("refs/tags/").delete_suffix("^{}"), sha] }
      end

      def self.rows(output)
        output.to_s.each_line.filter_map do |line|
          parts = line.strip.split(/\s+/, 2)
          parts if parts.length == 2 && parts[1].start_with?("refs/tags/")
        end
      end
    end
  end
end
