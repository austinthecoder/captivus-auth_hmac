require 'spec_helper'
require 'rack/test'
require 'net/http'
require 'captivus/auth_hmac'

describe Captivus::AuthHMAC do
  include Rack::Test::Methods

  def app
    lambda do |env|
      [200, {"Content-Type" => "text/html", "Content-Length" => 13}, "Hello, World!"]
    end
  end

  it 'says hello world' do
    get '/'
    last_response.status.should == 200
    last_response.body.should == 'Hello, World!'
  end

  it 'can process rack test requests' do
    # HMAC uses date to validate request signature, we need to fix the date so
    # that it matches.
    Delorean.time_travel_to(Date.parse("Thu, 10 Jul 2008 03:29:56 GMT"))

    env = current_session.__send__(:env_for, '/notify', {}.merge(:method => "POST", :params => {token: 'my-key-id'}))
    signature = Captivus::AuthHMAC.sign!(env, "my-key-id", "secret")
    signature.should == "AuthHMAC my-key-id:5zpt0efY2ck3zO/U1Eh9De/B1KM="

    back_to_the_present
  end

  it 'can handle hash requests' do
    Delorean.time_travel_to(Date.parse("Thu, 10 Jul 2008 03:29:56 GMT"))

    request_hash = {
      'REQUEST_METHOD' => 'PUT',
      'content-type' => 'text/plain',
      'content-md5' => 'blahblah',
      'date' => "Thu, 10 Jul 2008 03:29:56 GMT",
      'PATH_INFO' => '/notify'
    }

    standard_request = Net::HTTP::Put.new("/notify",
      'content-type' => 'text/plain',
      'content-md5' => 'blahblah',
      'date' => "Thu, 10 Jul 2008 03:29:56 GMT")

    sig = Captivus::AuthHMAC.signature(request_hash, 'secret')
    sig.should == Captivus::AuthHMAC.signature(standard_request, 'secret')

    back_to_the_present
  end
end