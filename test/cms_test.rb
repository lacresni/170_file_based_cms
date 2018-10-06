ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"

require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    @root = File.expand_path("..", __FILE__)
    @files = Dir.glob(@root + "/../data/*").map { |path| File.basename(path) }
  end

  def test_index
    get "/"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    @files.each do |file|
      assert_includes last_response.body, file
    end
  end

  def test_viewing_text_document
    @files.each do |file|
      if File.extname(file) == ".txt"
        get "/#{file}"
        assert_equal 200, last_response.status
        assert_equal "text/plain", last_response["Content-Type"]
      end
    end

    get "/history.txt"
    assert_includes last_response.body, "1993 - Yukihiro Matsumoto dreams up Ruby."
    assert_includes last_response.body, "2003 - Ruby 1.8 released."
    assert_includes last_response.body, "2015 - Ruby 2.3 released."
  end

  def test_document_not_existing
    get "/unknown.txt" # Attempt to access a nonexistent file

    assert_equal 302, last_response.status # Assert that the user was redirected

    get last_response["Location"] # Request the page that the user was redirected to

    assert_equal 200, last_response.status
    assert_includes last_response.body, "unknown.txt does not exist"

    get "/" # Reload the page
    refute_includes last_response.body, "unknown.txt does not exist" # Assert that our message has been removed
  end

  def test_markdown_file
    get "/about.md"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end
end
