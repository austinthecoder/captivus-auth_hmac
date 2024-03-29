require 'captivus/auth_hmac/version'
require 'openssl'
require 'base64'

module Captivus
  class AuthHMAC
    # This module provides a HMAC Authentication method for HTTP requests. It should work with
    # net/http request classes and CGIRequest classes and hence Rails.
    #
    # It is loosely based on the Amazon Web Services Authentication mechanism but
    # generalized to be useful to any application that requires HMAC based authentication.
    # As a result of the generalization, it won't work with AWS because it doesn't support
    # the Amazon extension headers.
    #
    # === References
    # Cryptographic Hash functions:: http://en.wikipedia.org/wiki/Cryptographic_hash_function
    # SHA-1 Hash function::          http://en.wikipedia.org/wiki/SHA-1
    # HMAC algorithm::               http://en.wikipedia.org/wiki/HMAC
    # RFC 2104::                     http://tools.ietf.org/html/rfc2104
    #
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
        keys.map do |key|
          headers[key]
        end.compact.first
      end
    end

    include Headers

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

    @@default_signature_class = CanonicalString

    # Create an AuthHMAC instance using the given credential store
    #
    # Credential Store:
    # * Credential store must respond to the [] method and return a secret for access key id
    #
    # Options:
    # Override default options
    # *  <tt>:service_id</tt> - Service ID used in the AUTHORIZATION header string. Default is AuthHMAC.
    # *  <tt>:signature_method</tt> - Proc object that takes request and produces the signature string
    #                                 used for authentication. Default is CanonicalString.
    # Examples:
    #   my_hmac = AuthHMAC.new('access_id1' => 'secret1', 'access_id2' => 'secret2')
    #
    #   cred_store = { 'access_id1' => 'secret1', 'access_id2' => 'secret2' }
    #   options = { :service_id => 'MyApp', :signature_method => lambda { |r| MyRequestString.new(r) } }
    #   my_hmac = AuthHMAC.new(cred_store, options)
    #
    def initialize(credential_store, options = nil)
      @credential_store = credential_store

      # Defaults
      @service_id = self.class.name.split(/::/).last
      @signature_class = @@default_signature_class

      unless options.nil?
        @service_id = options[:service_id] if options.key?(:service_id)
        @signature_class = options[:signature] if options.key?(:signature) && options[:signature].is_a?(Class)
      end

      @signature_method = lambda { |r| @signature_class.send(:new, r) }
    end

    # Generates canonical signing string for given request
    #
    # Supports same options as AuthHMAC.initialize for overriding service_id and
    # signature method.
    #
    def self.canonical_string(request, options = nil)
      self.new(nil, options).canonical_string(request)
    end

    # Generates signature string for a given secret
    #
    # Supports same options as AuthHMAC.initialize for overriding service_id and
    # signature method.
    #
    def self.signature(request, secret, options = nil)
      self.new(nil, options).signature(request, secret)
    end

    # Signs a request using a given access key id and secret.
    #
    # Supports same options as AuthHMAC.initialize for overriding service_id and
    # signature method.
    #
    def self.sign!(request, access_key_id, secret, options = nil)
      credentials = { access_key_id => secret }
      self.new(credentials, options).sign!(request, access_key_id)
    end

    # Authenticates a request using HMAC
    #
    # Supports same options as AuthHMAC.initialize for overriding service_id and
    # signature method.
    #
    def self.authenticated?(request, access_key_id, secret, options)
      credentials = { access_key_id => secret }
      self.new(credentials, options).authenticated?(request)
    end

    # Signs a request using the access_key_id and the secret associated with that id
    # in the credential store.
    #
    # Signing a requests adds an Authorization header to the request in the format:
    #
    #  <service_id> <access_key_id>:<signature>
    #
    # where <signature> is the Base64 encoded HMAC-SHA1 of the CanonicalString and the secret.
    #
    def sign!(request, access_key_id)
      secret = @credential_store[access_key_id]
      raise ArgumentError, "No secret found for key id '#{access_key_id}'" if secret.nil?
      request['Authorization'] = authorization(request, access_key_id, secret)
    end

    # Authenticates a request using HMAC
    #
    # Returns true if the request has an AuthHMAC Authorization header and
    # the access id and HMAC match an id and HMAC produced for the secret
    # in the credential store. Otherwise returns false.
    #
    def authenticated?(request)
      rx = Regexp.new("#{@service_id} ([^:]+):(.+)$")
      if md = rx.match(authorization_header(request))
        access_key_id = md[1]
        hmac = md[2]
        secret = @credential_store[access_key_id]
        !secret.nil? && hmac == signature(request, secret)
      else
        false
      end
    end

    def signature(request, secret)
      digest = OpenSSL::Digest::Digest.new('sha1')
      string = canonical_string(request)
      Base64.strict_encode64(OpenSSL::HMAC.digest(digest, secret, string)).strip
    end

    def canonical_string(request)
      @signature_method.call(request)
    end

    def authorization_header(request)
      find_header(%w(Authorization HTTP_AUTHORIZATION), headers(request))
    end

    def authorization(request, access_key_id, secret)
      "#{@service_id} #{access_key_id}:#{signature(request, secret)}"
    end
  end
end