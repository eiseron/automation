# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class ProdUploadTest < Minitest::Test
    class FakeTransferManager
      attr_reader :calls

      def initialize
        @calls = []
      end

      def upload_directory(dir, **opts)
        @calls << opts.merge(dir: dir)
      end
    end

    def base_env
      {
        "AWS_ACCESS_KEY_ID" => "key",
        "PROD_ASSETS_BUCKET" => "afinados-assets",
        "PROD_SOURCEMAPS_BUCKET" => "afinados-sourcemaps"
      }
    end

    def run_upload(env)
      tm = FakeTransferManager.new
      Prod::Upload.new(env: env, io: StringIO.new, transfer_manager: tm).run
      tm
    end

    def mime_for(path)
      upload = Prod::Upload.new(env: base_env, io: StringIO.new, transfer_manager: FakeTransferManager.new)
      upload.send(:mime_for_path, path)
    end

    def test_mime_maps_known_extensions
      assert_equal "font/woff2", mime_for("/a/app-HASH.woff2")
      assert_equal "text/css", mime_for("app-HASH.css")
      assert_includes mime_for("app-HASH.js"), "javascript"
    end

    def test_mime_falls_back_to_octet_stream
      assert_equal "application/octet-stream", mime_for("file.unknownext")
    end

    def test_skips_when_r2_creds_absent
      tm = run_upload(base_env.except("AWS_ACCESS_KEY_ID"))
      assert_empty tm.calls
    end

    def test_uploads_to_assets_and_sourcemaps_buckets
      tm = run_upload(base_env)
      buckets = tm.calls.map { |call| call[:bucket] }
      dirs = tm.calls.map { |call| call[:dir] }
      assert_equal %w[afinados-assets afinados-sourcemaps], buckets
      assert(tm.calls.all? { |call| call[:recursive] })
      assert_equal %w[priv/static priv/static], dirs
    end

    def test_assets_bucket_excludes_sourcemaps_and_precompressed
      filter = run_upload(base_env).calls.fetch(0).fetch(:filter_callback)
      assert filter.call("priv/static/assets/app-HASH.js", "app-HASH.js")
      refute filter.call("priv/static/assets/app-HASH.js.map", "app-HASH.js.map")
      refute filter.call("priv/static/assets/app-HASH.css.gz", "app-HASH.css.gz")
    end

    def test_sourcemaps_bucket_includes_only_sourcemaps
      filter = run_upload(base_env).calls.fetch(1).fetch(:filter_callback)
      assert filter.call("priv/static/assets/app-HASH.js.map", "app-HASH.js.map")
      refute filter.call("priv/static/assets/app-HASH.js", "app-HASH.js")
    end

    def test_sets_content_type_from_extension
      request = run_upload(base_env).calls.fetch(0).fetch(:request_callback)
      assert_equal "font/woff2", request.call("a/x.woff2", {})[:content_type]
    end
  end
end
