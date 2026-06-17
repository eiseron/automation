# frozen_string_literal: true

module EiseronAutomation
  module CI
    class Lock
      AUTOMATION_LABEL = "automation_ref"
      AUTOMATION_SHA = "STACK_AUTOMATION_SHA"

      def self.build(env:, io:)
        git = GitSource.new
        new(
          manifest_path: env.fetch("STACK_MANIFEST", "manifest.yml"),
          lock_path: env.fetch("STACK_LOCK", "lock.yml"),
          sources: { "gem" => git, "repo" => git, "image" => RegistrySource.new },
          io: io
        )
      end

      def initialize(manifest_path:, lock_path:, sources:, io: $stdout)
        @manifest_path = manifest_path
        @lock_path = lock_path
        @sources = sources
        @io = io
      end

      def init
        return @io.puts("ci: #{@manifest_path} already exists") if File.exist?(@manifest_path)

        File.write(@manifest_path, "gems: {}\nrepos: {}\nimages: {}\n")
        @io.puts "ci: wrote #{@manifest_path}"
      end

      def install
        write(resolve(current_vars))
      end

      def update(names)
        write(resolve(reusable(names)))
      end

      def check
        fail_check("lock.yml is missing") unless File.exist?(@lock_path)
        vars = current_vars
        entries.each { |entry| verify(entry, vars) }
        assert_baked_automation(vars)
        @io.puts "ci: lock in sync with manifest"
      end

      private

      def resolve(reuse)
        entries.each_with_object({}) do |entry, vars|
          vars.merge!(Vars.assign(entry, record(entry, reuse)))
        end
      end

      def record(entry, reuse)
        reused(entry, reuse) || fetch(entry)
      end

      def reused(entry, reuse)
        version = Vars.version(entry, reuse)
        return nil unless version && Constraint.satisfies?(entry[:constraint], version)

        Vars.record(entry, reuse)
      end

      def fetch(entry)
        source = @sources.fetch(entry[:type])
        source.finalize(entry, Constraint.best(entry[:constraint], source.candidates(entry)))
      end

      def reusable(names)
        return {} if names.empty?

        dropped = entries.select { |entry| names.include?(entry[:name]) }.flat_map { |entry| Vars.keys(entry) }
        current_vars.except(*dropped)
      end

      def verify(entry, vars)
        Vars.keys(entry).each { |key| fail_check("#{key} is missing") unless vars.key?(key) }
        version = Vars.version(entry, vars)
        return if Constraint.satisfies?(entry[:constraint], version)

        fail_check("#{entry[:name]} #{version} does not satisfy '#{entry[:constraint]}'")
      end

      def assert_baked_automation(vars)
        expected = vars[AUTOMATION_SHA]
        return unless expected

        baked_image_vars(vars).each do |key, image|
          actual = registry.label(image, AUTOMATION_LABEL)
          next unless actual
          next if actual == expected

          raise Error, "#{image_name(key)} bakes #{AUTOMATION_LABEL} #{actual.inspect} " \
                       "but lock pins #{expected.inspect}"
        end
      end

      def baked_image_vars(vars)
        vars.select { |key, _| key.start_with?("STACK_") && key.end_with?("_IMAGE") }
      end

      def image_name(key)
        key.delete_prefix("STACK_").delete_suffix("_IMAGE").downcase.tr("_", "-")
      end

      def registry = @sources.fetch("image")

      def write(vars)
        File.write(@lock_path, LockFile.render(vars))
        @io.puts "ci: wrote #{@lock_path} (#{vars.length} variables)"
      end

      def current_vars
        LockFile.parse(@lock_path)
      end

      def entries
        @entries ||= Manifest.load(@manifest_path)
      end

      def fail_check(detail)
        raise Error, "lock.yml is out of sync with manifest.yml: #{detail}"
      end
    end
  end
end
