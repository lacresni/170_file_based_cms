ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def test_index
    create_document("changes.txt")
    create_document("about.md")

    get "/"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "changes.txt"
    assert_includes last_response.body, "about.md"
  end

  def test_viewing_text_document
    content = <<~CONTENT
    1993 - Yukihiro Matsumoto dreams up Ruby.
    1995 - Ruby 0.95 released.
    1996 - Ruby 1.0 released.
    1998 - Ruby 1.2 released.
    1999 - Ruby 1.4 released.
    2000 - Ruby 1.6 released.
    2003 - Ruby 1.8 released.
    2007 - Ruby 1.9 released.
    2013 - Ruby 2.0 released.
    2013 - Ruby 2.1 released.
    2014 - Ruby 2.2 released.
    2015 - Ruby 2.3 released.
    CONTENT
    create_document("history.txt", content)

    get "/history.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "1993 - Yukihiro Matsumoto dreams up Ruby."
    assert_includes last_response.body, "2003 - Ruby 1.8 released."
    assert_includes last_response.body, "2015 - Ruby 2.3 released."
  end

  def test_document_not_existing
    get "/unknown.ext" # Attempt to access a nonexistent file

    assert_equal 302, last_response.status # Assert that the user was redirected

    get last_response["Location"] # Request the page that the user was redirected to

    assert_equal 200, last_response.status
    assert_includes last_response.body, "unknown.ext does not exist"

    get "/" # Reload the page
    refute_includes last_response.body, "unknown.ext does not exist" # Assert that our message has been removed
  end

  def test_markdown_file
    content = <<~CONTENT
    # Ruby is...
    A dynamic language, open source programming language with a focus on simplicity and productivity.
    CONTENT
    create_document("about.md", content)

    get "/about.md"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end

  def test_editing_document
    create_document("changes.txt")

    get "/changes.txt/edit"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit">Save Changes</button>)
  end

  def test_updating_document
    create_document("changes.txt")

    post "/changes.txt", content: "New content"
    assert_equal 302, last_response.status  # Sinatra uses 303 but Rack::Test always sets 302

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "changes.txt has been updated."

    get "/"
    assert_equal 200, last_response.status
    refute_includes last_response.body, "changes.txt has been updated."

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "New content"
  end

  def test_view_new_document_form
    get "/new"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_create_new_document
    post "/create", filename: "new_file.md"
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_includes last_response.body, "new_file.md was created."

    get "/"
    assert_includes last_response.body, "new_file.md"
  end

  def test_create_new_document_without_filename
    post "/create", filename: ""
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
  end

  def test_create_new_document_without_extension
    post "/create", filename: "test"
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A file extension is required."

    post "/create", filename: "test.z"
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A file extension is required."
  end

  def test_delete_file
    create_document("test.txt")

    post "/test.txt/delete"
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_includes last_response.body, "test.txt was deleted."

    get "/"
    refute_includes last_response.body, "test.txt"
  end

  def test_delete_non_existing_file
    create_document("test.txt")

    post "/unknown.txt/delete"
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_includes last_response.body, "unknown.txt does not exist."

    get "/"
    refute_includes last_response.body, "unknown.txt"
  end

  def test_signed_out_user_index
    get "/"
    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<button type="submit">Sign In</button>)
    refute_includes last_response.body, "Signed in as"
  end

  def test_signin_form
    get "/users/signin"

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<input class="inline" name="username")
    assert_includes last_response.body, %q(input class="inline" name="password")
  end

  def test_signin_with_invalid_credentials
    post "/users/signin", username: "nicolas", password: "test"
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Invalid Credentials"
    assert_includes last_response.body, %q(<input class="inline" name="username")
    assert_includes last_response.body, %q(input class="inline" name="password")
  end

  def test_signin_with_valid_credentials
    post "/users/signin", username: "admin", password: "secret"
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Welcome!"
    assert_includes last_response.body, "Signed in as admin"
    assert_includes last_response.body, %q(<button type="submit">Sign Out</button>)
  end

  def test_sign_out
    post "/users/signin", username: "admin", password: "secret"
    get last_response["Location"]
    assert_includes last_response.body, "Welcome!"

    post "/users/signout"
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You have been signed out."
    assert_includes last_response.body, %q(<button type="submit">Sign In</button>)
    refute_includes last_response.body, "Signed in as"
  end
end
