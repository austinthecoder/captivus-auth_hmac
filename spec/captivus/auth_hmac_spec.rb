require 'spec_helper'
require 'captivus-auth_hmac'

describe Captivus::AuthHMAC do
  describe "sign_request" do
    it "adds an authorization header to the request in the format <service_id> <key>:<signature>" do
      request = {}
      Captivus::AuthHMAC.new.sign_request request, 'the-key', 'the-secret'
      expect(request['Authorization']).to eq "Something key:somehash"
    end
  end
end