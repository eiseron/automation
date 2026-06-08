# frozen_string_literal: true

require "mime/types"

module EiseronAutomation
  module Prod
    class Upload
      def initialize(env: ENV, io: $stdout, transfer_manager: nil)
        @env = env
        @io = io
        @transfer_manager = transfer_manager
      end

      def run
        if @env.fetch("AWS_ACCESS_KEY_ID", "").empty?
          @io.puts "R2 creds unset; skipping asset upload (product not configured for prod)"
          return
        end

        dir = @env.fetch("PROD_ASSETS_DIR", "priv/static")
        sync(dir, require_env("PROD_ASSETS_BUCKET"), ->(path) { !path.end_with?(".map", ".gz") })
        sync(dir, require_env("PROD_SOURCEMAPS_BUCKET"), ->(path) { path.end_with?(".map") })
      end

      private

      def sync(dir, bucket, keep)
        @io.puts "Uploading #{dir} -> s3://#{bucket}"
        transfer_manager.upload_directory(
          dir,
          bucket: bucket,
          recursive: true,
          filter_callback: ->(file_path, _file_name) { keep.call(file_path) },
          request_callback: ->(file_path, params) { params.merge(content_type: mime_for_path(file_path)) }
        )
      end

      def mime_for_path(path)
        MIME::Types.type_for(path).first&.to_s || "application/octet-stream"
      end

      def transfer_manager
        @transfer_manager ||= begin
          require "aws-sdk-s3"
          client = Aws::S3::Client.new(
            region: "auto",
            endpoint: "https://#{require_env('CLOUDFLARE_ACCOUNT_ID')}.r2.cloudflarestorage.com"
          )
          Aws::S3::TransferManager.new(client: client)
        end
      end

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
