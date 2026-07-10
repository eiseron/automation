# frozen_string_literal: true

module EiseronAutomation
  module CI
    class TofuCoverage
      DEFAULT_MODULES_DIR = "modules"

      def initialize(root: ".", io: $stdout, args: [])
        @root = root
        @io = io
        @args = args
      end

      def run
        total, tested = self.class.coverage(root: @root, modules_dir: modules_dir)
        pct = self.class.percentage(tested, total)
        @io.puts "[TOTAL] #{format('%.1f', pct)}% (#{tested}/#{total} modules)"
      end

      def self.coverage(root:, modules_dir:)
        dirs = module_dirs(root: root, modules_dir: modules_dir)
        [dirs.size, dirs.count { |dir| tested?(dir) }]
      end

      def self.percentage(tested, total)
        return 0.0 if total.zero?

        (tested.to_f / total * 100).round(1)
      end

      def self.module_dirs(root:, modules_dir:)
        base = File.join(root, modules_dir)
        return [root] unless Dir.exist?(base)

        Dir.children(base)
           .map { |name| File.join(base, name) }
           .select { |path| File.directory?(path) }
           .sort
      end

      def self.tested?(dir)
        !Dir.glob(File.join(dir, "**", "*.tftest.hcl")).empty?
      end

      private

      def modules_dir
        idx = @args.index("--modules-dir")
        return DEFAULT_MODULES_DIR unless idx

        value = @args[idx + 1]
        raise Error, "--modules-dir requires a value" if value.nil? || value.start_with?("-")

        value
      end
    end
  end
end
