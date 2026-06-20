# frozen_string_literal: true

module EiseronAutomation
  module DB
    class R2
      def initialize(account_id:, client: nil)
        @account_id = account_id
        @client = client
      end

      def list(bucket, prefix)
        client.list_objects_v2(bucket: bucket, prefix: "#{prefix}/").contents.map(&:key)
      end

      def download(bucket, key, dest)
        client.get_object(response_target: dest, bucket: bucket, key: key)
      end

      def upload(bucket, key, src)
        File.open(src, "rb") { |body| client.put_object(bucket: bucket, key: key, body: body) }
      end

      def delete(bucket, key)
        client.delete_object(bucket: bucket, key: key)
      end

      def read_text(bucket, key)
        client.get_object(bucket: bucket, key: key).body.read
      rescue Aws::S3::Errors::NoSuchKey
        nil
      end

      def write_text(bucket, key, text)
        client.put_object(bucket: bucket, key: key, body: text)
      end

      def exists?(bucket, key)
        client.head_object(bucket: bucket, key: key)
        true
      rescue Aws::S3::Errors::NotFound
        false
      end

      private

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
