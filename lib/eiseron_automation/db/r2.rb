# frozen_string_literal: true

module EiseronAutomation
  module DB
    class R2
      def initialize(account_id:, client: nil, env: ENV)
        @account_id = account_id
        @client = client
        @env = env
      end

      def list(bucket, prefix)
        client.list_objects_v2(bucket: bucket, prefix: "#{prefix}/").contents.map(&:key)
      rescue Aws::S3::Errors::ServiceError => e
        raise Error, diagnostic("ListObjectsV2", bucket, "#{prefix}/", e)
      end

      def download(bucket, key, dest)
        client.get_object(response_target: dest, bucket: bucket, key: key)
      rescue Aws::S3::Errors::ServiceError => e
        raise Error, diagnostic("GetObject", bucket, key, e)
      end

      def upload(bucket, key, src)
        File.open(src, "rb") { |body| client.put_object(bucket: bucket, key: key, body: body) }
      rescue Aws::S3::Errors::ServiceError => e
        raise Error, diagnostic("PutObject", bucket, key, e)
      end

      def delete(bucket, key)
        client.delete_object(bucket: bucket, key: key)
      rescue Aws::S3::Errors::ServiceError => e
        raise Error, diagnostic("DeleteObject", bucket, key, e)
      end

      def read_text(bucket, key)
        client.get_object(bucket: bucket, key: key).body.read
      rescue Aws::S3::Errors::NoSuchKey
        nil
      rescue Aws::S3::Errors::ServiceError => e
        raise Error, diagnostic("GetObject", bucket, key, e)
      end

      def write_text(bucket, key, text)
        client.put_object(bucket: bucket, key: key, body: text)
      rescue Aws::S3::Errors::ServiceError => e
        raise Error, diagnostic("PutObject", bucket, key, e)
      end

      def exists?(bucket, key)
        client.head_object(bucket: bucket, key: key)
        true
      rescue Aws::S3::Errors::NotFound
        false
      rescue Aws::S3::Errors::ServiceError => e
        raise Error, diagnostic("HeadObject", bucket, key, e)
      end

      private

      def diagnostic(operation, bucket, key, error)
        "R2 #{operation} s3://#{bucket}/#{key} failed: #{error_code(error)} (#{credentials_hint})"
      end

      def error_code(error)
        error.class.name.split("::").last
      end

      def credentials_hint
        "#{access_key_id_hint}, #{secret_access_key_hint}"
      end

      def access_key_id_hint
        id = @env["AWS_ACCESS_KEY_ID"].to_s
        return "AWS_ACCESS_KEY_ID empty" if id.empty?

        "AWS_ACCESS_KEY_ID present (#{id.length} chars)"
      end

      def secret_access_key_hint
        @env["AWS_SECRET_ACCESS_KEY"].to_s.empty? ? "AWS_SECRET_ACCESS_KEY empty" : "AWS_SECRET_ACCESS_KEY present"
      end

      def client
        @client ||= begin
          require "aws-sdk-s3"
          Aws::S3::Client.new(
            region: "auto",
            endpoint: "https://#{@account_id}.r2.cloudflarestorage.com"
          )
        end
      end
    end
  end
end
