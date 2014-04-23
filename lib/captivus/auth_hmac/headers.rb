require 'captivus/auth_hmac'

module Captivus
  class AuthHMAC
    module Headers
      # Gets the headers for a request.
      #
      # Attempts to deal with known HTTP header representations in Ruby.
      # Currently handles net/http and Rails.
      #
      def headers(request)
        if request.respond_to?(:headers)
          request.headers
        elsif request.is_a?(Hash) && request.has_key?(:request_headers)
          request[:request_headers]
        elsif request.respond_to?(:[])
          request
        else
          raise ArgumentError, "Don't know how to get the headers from #{request.inspect}"
        end
      end

      def find_header(keys, headers)
        keys.map { |key| headers[key] }.compact.first
      end
    end
  end
end