# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module CI
    class RubyGemsSourceTest < Minitest::Test
      class FakeResponse
        attr_reader :code, :body

        def initialize(code, body)
          @code = code
          @body = body
        end

        def is_a?(klass)
          klass == Net::HTTPSuccess && code.to_i.between?(200, 299)
        end
      end

      class FakeHTTP
        attr_reader :requests

        def initialize(response)
          @response = response
          @requests = []
        end

        def start(_host, _port, **)
          yield self
        end

        def request(req)
          @requests << req.path
          @response
        end
      end

      def versions_json
        JSON.dump([
                    { "number" => "0.3.8", "sha" => "aaa", "prerelease" => false },
                    { "number" => "0.3.7", "sha" => "bbb", "prerelease" => false },
                    { "number" => "0.4.0.rc1", "sha" => "ccc", "prerelease" => true }
                  ])
      end

      def source(response: FakeResponse.new(200, versions_json))
        http = FakeHTTP.new(response)
        [RubyGemsSource.new(http: http), http]
      end

      def test_candidates_hit_the_rubygems_versions_endpoint
        src, http = source
        src.candidates({ type: "gem", source: "specific_install" })
        assert_equal "/api/v1/versions/specific_install.json", http.requests.fetch(0)
      end

      def test_url_encodes_the_gem_name
        src, http = source
        src.candidates({ type: "gem", source: "aws-sdk-s3" })
        assert_equal "/api/v1/versions/aws-sdk-s3.json", http.requests.fetch(0)
      end

      def test_candidates_return_version_and_sha_for_stable_releases
        src, = source
        result = src.candidates({ type: "gem", source: "specific_install" })
        assert_equal [{ version: "0.3.8", sha: "aaa" }, { version: "0.3.7", sha: "bbb" }], result
      end

      def test_candidates_skip_prereleases
        src, = source
        result = src.candidates({ type: "gem", source: "specific_install" })
        versions = result.map { |row| row[:version] }
        refute_includes versions, "0.4.0.rc1"
      end

      def test_finalize_carries_the_gem_name
        src, = source
        record = src.finalize({ type: "gem", source: "aws-sdk-s3" }, { version: "1.225.0", sha: "deadbeef" })
        assert_equal "aws-sdk-s3", record[:gem]
        assert_equal "1.225.0", record[:version]
        assert_equal "deadbeef", record[:sha]
      end

      def test_non_2xx_raises
        src, = source(response: FakeResponse.new(404, "{}"))
        error = assert_raises(Error) do
          src.candidates({ type: "gem", source: "missing_gem" })
        end
        assert_match(/rubygems missing_gem fetch failed/, error.message)
      end
    end
  end
end
