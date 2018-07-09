# frozen_string_literal: true

require 'spec_helper'

describe Capybara::Mechanize::Driver, 'local' do
  let(:driver) { Capybara::Mechanize::Driver.new(ExtendedTestApp) }

  describe '#configure' do
    it 'allows extended configuration of the agent' do
      expect_any_instance_of(::Mechanize).to receive(:foo=).with('test')
      driver.configure do |agent|
        agent.foo = 'test'
      end
    end
  end

  describe ':headers option' do
    it 'should always set headers' do
      driver = Capybara::RackTest::Driver.new(TestApp, headers: { 'HTTP_FOO' => 'foobar' })
      driver.visit('/get_header')
      expect(driver.html).to include('foobar')
    end

    it 'should keep headers on link clicks' do
      driver = Capybara::RackTest::Driver.new(TestApp, headers: { 'HTTP_FOO' => 'foobar' })
      driver.visit('/header_links')
      driver.find_xpath('.//a').first.click
      expect(driver.html).to include('foobar')
    end

    it 'should keep headers on form submit' do
      driver = Capybara::RackTest::Driver.new(TestApp, headers: { 'HTTP_FOO' => 'foobar' })
      driver.visit('/header_links')
      driver.find_xpath('.//input').first.click
      expect(driver.html).to include('foobar')
    end

    it 'should keep headers on redirects' do
      driver = Capybara::RackTest::Driver.new(TestApp, headers: { 'HTTP_FOO' => 'foobar' })
      driver.visit('/get_header_via_redirect')
      expect(driver.html).to include('foobar')
    end
  end

  describe ':follow_redirects option' do
    it 'defaults to following redirects' do
      driver = Capybara::RackTest::Driver.new(TestApp)

      driver.visit('/redirect')
      expect(driver.response.header['Location']).to be_nil
      expect(driver.browser.current_url).to match %r{/landed$}
    end

    it 'is possible to not follow redirects' do
      driver = Capybara::RackTest::Driver.new(TestApp, follow_redirects: false)

      driver.visit('/redirect')
      expect(driver.response.header['Location']).to match %r{/redirect_again$}
      expect(driver.browser.current_url).to match %r{/redirect$}
    end
  end

  describe ':redirect_limit option' do
    context 'with default redirect limit' do
      let(:driver) { Capybara::RackTest::Driver.new(TestApp) }

      it 'should follow 5 redirects' do
        driver.visit('/redirect/5/times')
        expect(driver.html).to include('redirection complete')
      end

      it 'should not follow more than 6 redirects' do
        expect do
          driver.visit('/redirect/6/times')
        end.to raise_error(Capybara::InfiniteRedirectError)
      end
    end

    context 'with 21 redirect limit' do
      let(:driver) { Capybara::RackTest::Driver.new(TestApp, redirect_limit: 21) }

      it 'should follow 21 redirects' do
        driver.visit('/redirect/21/times')
        expect(driver.html).to include('redirection complete')
      end

      it 'should not follow more than 21 redirects' do
        expect do
          driver.visit('/redirect/22/times')
        end.to raise_error(Capybara::InfiniteRedirectError)
      end
    end
  end

  it 'should default to local mode for relative paths' do
    expect(driver).not_to be_remote('/')
  end

  it 'should default to local mode for the default host' do
    expect(driver).not_to be_remote('http://www.example.com')
  end

  context 'with an app_host' do
    before do
      Capybara.app_host = 'http://www.remote.com'
    end

    after do
      Capybara.app_host = nil
    end

    it 'should treat urls as remote' do
      expect(driver).to be_remote('http://www.remote.com')
    end
  end

  context 'with a default url, no app host' do
    before do
      Capybara.default_host = 'http://www.local.com'
    end

    after do
      Capybara.default_host = CAPYBARA_DEFAULT_HOST
    end

    context 'local hosts' do
      before do
        Capybara::Mechanize.local_hosts = ['subdomain.local.com']
      end

      after do
        Capybara::Mechanize.local_hosts = nil
      end

      it 'should allow local hosts to be set' do
        expect(driver).not_to be_remote('http://subdomain.local.com')
      end
    end

    it 'should treat urls with the same host names as local' do
      expect(driver).not_to be_remote('http://www.local.com')
    end

    it 'should treat other urls as remote' do
      expect(driver).to be_remote('http://www.remote.com')
    end

    it 'should treat relative paths as remote if the previous request was remote' do
      driver.visit(remote_test_url)
      expect(driver).to be_remote('/some_relative_link')
    end

    it 'should treat relative paths as local if the previous request was local' do
      driver.visit('http://www.local.com')
      expect(driver).not_to be_remote('/some_relative_link')
    end

    it 'should receive the right host' do
      driver.visit('http://www.local.com/host')
      should_be_a_local_get
    end

    it 'should consider relative paths to be local when the previous request was local' do
      driver.visit('http://www.local.com/host')
      driver.visit('/host')

      should_be_a_local_get
      expect(driver).not_to be_remote('/first_local')
    end

    it 'should consider relative paths to be remote when the previous request was remote' do
      driver.visit("#{remote_test_url}/host")
      driver.get('/host')

      should_be_a_remote_get
      expect(driver).to be_remote('/second_remote')
    end

    it 'should always switch to the right context' do
      driver.visit('http://www.local.com/host')
      driver.get('/host')
      driver.get("#{remote_test_url}/host")
      driver.get('/host')
      driver.get('http://www.local.com/host')

      should_be_a_local_get
      expect(driver).not_to be_remote('/second_local')
    end

    it 'should follow redirects from local to remote' do
      driver.visit("http://www.local.com/redirect_to/#{remote_test_url}/host")
      should_be_a_remote_get
    end

    it 'should follow redirects from remote to local' do
      driver.visit("#{remote_test_url}/redirect_to/http://www.local.com/host")
      should_be_a_local_get
    end

    it 'passes the status code of remote calls back to be validated' do
      quietly do
        driver.visit(remote_test_url)
        driver.get('/asdfafadfsdfs')
        expect(driver.response.status).to be >= 400
      end
    end

    context 'when errors are set to true' do
      it 'raises an useful error because it is probably a misconfiguration' do
        quietly do
          original = Capybara.raise_server_errors

          expect do
            driver.visit(remote_test_url)
            Capybara.raise_server_errors = true
            driver.get('/asdfafadfsdfs')
          end.to raise_error(%r{Received the following error for a GET request to /asdfafadfsdfs:})
          Capybara.raise_server_errors = original
        end
      end
    end
  end

  it 'should include the right host when remote' do
    driver.visit("#{remote_test_url}/host")
    should_be_a_remote_get
  end

  describe '#reset!' do
    before do
      Capybara.default_host = 'http://www.local.com'
    end

    after do
      Capybara.default_host = CAPYBARA_DEFAULT_HOST
    end

    it 'should reset remote host' do
      driver.visit("#{remote_test_url}/host")
      should_be_a_remote_get
      driver.reset!
      driver.visit('/host')
      should_be_a_local_get
    end
  end

  def should_be_a_remote_get
    expect(driver.current_url).to include(remote_test_url)
  end

  def should_be_a_local_get
    expect(driver.current_url).to include('www.local.com')
  end
end
