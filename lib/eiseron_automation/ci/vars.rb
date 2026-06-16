# frozen_string_literal: true

module EiseronAutomation
  module CI
    class Vars
      def self.assign(entry, record)
        base = Naming.var_base(entry)
        return image(base, record) if entry[:type] == "image"

        {
          "STACK_#{base}_REPO" => record[:repo],
          "STACK_#{base}_REF" => record[:ref],
          "STACK_#{base}_SHA" => record[:sha]
        }
      end

      def self.image(base, record)
        { "STACK_#{base}_IMAGE" => record[:image], "STACK_#{base}_TAG" => record[:tag] }
      end

      def self.keys(entry)
        assign(entry, {}).keys
      end

      def self.version(entry, lock_vars)
        base = Naming.var_base(entry)
        key = entry[:type] == "image" ? "STACK_#{base}_TAG" : "STACK_#{base}_REF"
        lock_vars[key]
      end

      def self.record(entry, lock_vars)
        base = Naming.var_base(entry)
        return image_record(base, lock_vars) if entry[:type] == "image"

        {
          repo: lock_vars["STACK_#{base}_REPO"],
          ref: lock_vars["STACK_#{base}_REF"],
          sha: lock_vars["STACK_#{base}_SHA"]
        }
      end

      def self.image_record(base, lock_vars)
        { tag: lock_vars["STACK_#{base}_TAG"], image: lock_vars["STACK_#{base}_IMAGE"] }
      end
    end
  end
end
