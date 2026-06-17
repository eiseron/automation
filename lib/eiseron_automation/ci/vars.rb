# frozen_string_literal: true

module EiseronAutomation
  module CI
    class Vars
      def self.assign(entry, record)
        base = Naming.var_base(entry)
        return image(base, record) if entry[:type] == "image"
        return rubygem(base, record) if GemRouter.rubygems_source?(entry)

        {
          "STACK_#{base}_REPO" => record[:repo],
          "STACK_#{base}_REF" => record[:ref],
          "STACK_#{base}_SHA" => record[:sha]
        }
      end

      def self.image(base, record)
        { "STACK_#{base}_IMAGE" => record[:image], "STACK_#{base}_TAG" => record[:tag] }
      end

      def self.rubygem(base, record)
        {
          "STACK_#{base}_GEM" => record[:gem],
          "STACK_#{base}_VERSION" => record[:version],
          "STACK_#{base}_SHA" => record[:sha]
        }
      end

      def self.keys(entry)
        assign(entry, {}).keys
      end

      def self.version(entry, lock_vars)
        base = Naming.var_base(entry)
        lock_vars[version_key(entry, base)]
      end

      def self.version_key(entry, base)
        return "STACK_#{base}_TAG" if entry[:type] == "image"
        return "STACK_#{base}_VERSION" if GemRouter.rubygems_source?(entry)

        "STACK_#{base}_REF"
      end

      def self.record(entry, lock_vars)
        base = Naming.var_base(entry)
        return image_record(base, lock_vars) if entry[:type] == "image"
        return rubygem_record(base, lock_vars) if GemRouter.rubygems_source?(entry)

        {
          repo: lock_vars["STACK_#{base}_REPO"],
          ref: lock_vars["STACK_#{base}_REF"],
          sha: lock_vars["STACK_#{base}_SHA"]
        }
      end

      def self.image_record(base, lock_vars)
        { tag: lock_vars["STACK_#{base}_TAG"], image: lock_vars["STACK_#{base}_IMAGE"] }
      end

      def self.rubygem_record(base, lock_vars)
        {
          gem: lock_vars["STACK_#{base}_GEM"],
          version: lock_vars["STACK_#{base}_VERSION"],
          sha: lock_vars["STACK_#{base}_SHA"]
        }
      end
    end
  end
end
