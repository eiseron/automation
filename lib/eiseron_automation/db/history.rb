# frozen_string_literal: true

module EiseronAutomation
  module DB
    class History
      SUFFIX = ".sql.age"

      Entry = Struct.new(:key, :sha256)

      def self.parse(text)
        new((text || "").lines.filter_map { |line| build_entry(line) })
      end

      def self.build_entry(line)
        key, sha256 = line.strip.split("\t", 2)
        return nil unless key&.end_with?(SUFFIX)

        Entry.new(key, normalize(sha256))
      end

      def self.normalize(value)
        stripped = value.to_s.strip
        stripped.empty? ? nil : stripped
      end

      def initialize(entries)
        @entries = entries
      end

      def empty? = @entries.empty?
      def keys = @entries.map(&:key)
      def latest = @entries.max_by(&:key)
      def sha256_for(key) = @entries.find { |entry| entry.key == key }&.sha256

      def add(key, sha256)
        self.class.new(@entries + [Entry.new(key, sha256)])
      end

      def without(keys)
        self.class.new(@entries.reject { |entry| keys.include?(entry.key) })
      end

      def dump
        return "" if @entries.empty?

        "#{@entries.map { |entry| format_line(entry) }.join("\n")}\n"
      end

      private

      def format_line(entry)
        return entry.key unless entry.sha256

        "#{entry.key}\t#{entry.sha256}"
      end
    end
  end
end
