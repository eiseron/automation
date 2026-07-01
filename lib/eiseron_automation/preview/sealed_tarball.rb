# frozen_string_literal: true

require "rubygems/package"
require "stringio"
require "zlib"

module EiseronAutomation
  module Preview
    module SealedTarball
      module_function

      def verify(path)
        raw = Zlib.gunzip(File.binread(path))
        Gem::Package::TarReader.new(StringIO.new(raw)) do |tar|
          tar.each { |entry| reject_unsafe(entry) }
        end
      end

      def reject_unsafe(entry)
        name = entry.full_name.to_s
        raise Error, "unsafe tar entry (absolute path): #{name}" if name.start_with?("/")
        raise Error, "unsafe tar entry (path traversal): #{name}" if name.split(%r{[/\\]}).include?("..")
        raise Error, "unsafe tar entry (link): #{name}" if %w[1 2].include?(entry.header.typeflag)
      end
    end
  end
end
