require 'captivus/auth_hmac'
require 'captivus/auth_hmac/headers'

module Captivus
  # Build a Canonical String for a HTTP request.
  #
  # A Canonical String has the following format:
  #
  # CanonicalString = HTTP-Verb    + "\n" +
  #                   Content-Type + "\n" +
  #                   Content-MD5  + "\n" +
  #                   Date         + "\n" +
  #                   request-uri;
  #
  #
  # If the Date header doesn't exist, one will be generated since
  # Net/HTTP will generate one if it doesn't exist and it will be
  # used on the server side to do authentication.
  #
  class AuthHMAC
    class CanonicalString < String # :nodoc:
      include Headers

      def initialize(request)
        self << request_method(request) + "\n"
        self << header_values(headers(request)) + "\n"
        self << request_path(request)
      end

      private

      def request_method(request)
        if request.respond_to?(:request_method) && request.request_method.is_a?(String)
          request.request_method
        elsif request.is_a?(Hash) && request.has_key?(:method)
          request[:method].to_s
        elsif request.respond_to?(:env) && request.env
          request.env['REQUEST_METHOD']
        elsif request.is_a?(Hash) && request.has_key?('REQUEST_METHOD')
          request['REQUEST_METHOD']
        else
          begin
            request.method
          rescue ArgumentError
            raise ArgumentError, "Don't know how to get the request method from #{request.inspect}"
          end
        end
      end

      def header_values(headers)
        [ content_type(headers),
          content_md5(headers),
          (date(headers) or headers['Date'] = Time.now.utc.httpdate)
        ].join("\n")
      end

      def content_type(headers)
        find_header(%w(CONTENT-TYPE CONTENT_TYPE HTTP_CONTENT_TYPE content-type), headers)
      end

      def date(headers)
        find_header(%w(DATE HTTP_DATE date), headers)
      end

      def content_md5(headers)
        find_header(%w(CONTENT-MD5 CONTENT_MD5 content-md5), headers)
      end

      def request_path(request)
        # Try unparsed_uri in case it is a Webrick request
        path = if request.respond_to?(:unparsed_uri)
          request.unparsed_uri
        elsif request.is_a?(Hash) && request.has_key?(:url) && request[:url].is_a?(URI)
          request[:url].path
        elsif request.is_a?(Hash) && request.has_key?('PATH_INFO')
          request['PATH_INFO']
        else
          request.path
        end

        path[/^[^?]*/]
      end
    end
  end
end