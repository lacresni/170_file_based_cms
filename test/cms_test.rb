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
    # clean-up test/user.yml (remove newly created new_user)
    credentials = load_user_credentials
    if credentials.key?("new_user")
      credentials.delete("new_user")
      File.open(credentials_path, "w") do |file|
        file.write(credentials.to_yaml)
      end
    end
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { username: "admin" } }
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

    assert_equal "unknown.ext does not exist.", session[:message]
    assert_equal 302, last_response.status # Assert that the user was redirected

    get last_response["Location"] # Request the page that the user was redirected to

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

    get "/changes.txt/edit", {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit">Save Changes</button>)
  end

  def test_editing_document_signed_out
    create_document("changes.txt")

    get "/changes.txt/edit"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_updating_document
    create_document("changes.txt")

    post "/changes.txt", { content: "New content" }, admin_session
    assert_equal 302, last_response.status  # Sinatra uses 303 but Rack::Test always sets 302
    assert_equal "changes.txt has been updated.", session[:message]

    get last_response["Location"]

    get "/"
    refute_includes last_response.body, "changes.txt has been updated."

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "New content"
  end

  def test_updating_document_signed_out
    create_document("changes.txt")

    post "/changes.txt"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_view_new_document_form
    get "/new", {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_view_new_document_form_signed_out
    get "/new"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_create_new_document
    post "/create", { filename: "new_file.md" }, admin_session
    assert_equal 302, last_response.status
    assert_equal "new_file.md was created.", session[:message]

    get "/"
    assert_includes last_response.body, "new_file.md"
  end

  def test_create_new_document_without_filename
    post "/create", { filename: "" }, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
  end

  def test_create_new_document_without_extension
    post "/create", { filename: "test" }, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A valid file extension is required."
  end

  def test_create_new_document_with_unsupported_extension
    post "/create", { filename: "test.z" }, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A valid file extension is required."
  end

  def test_create_new_document_signed_out
    post "/create", { filename: "new_file.md" }
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_delete_file
    create_document("test.txt")

    post "/test.txt/delete", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "test.txt was deleted.", session[:message]

    get "/"
    refute_includes last_response.body, %q(href="test.txt")
  end

  def test_delete_file_signed_out
    create_document("test.txt")

    post "/test.txt/delete"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_delete_non_existing_file
    create_document("test.txt")

    post "/unknown.txt/delete", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "unknown.txt does not exist.", session[:message]
  end

  def test_signed_out_user_index
    get "/"
    assert_equal 200, last_response.status
    assert_nil session[:username]
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
    assert_nil session[:username]
    assert_includes last_response.body, "Invalid Credentials"
    assert_includes last_response.body, %q(<input class="inline" name="username")
    assert_includes last_response.body, %q(input class="inline" name="password")
  end

  def test_signin_with_admin_credentials
    post "/users/signin", username: "admin", password: "secret"
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:username]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Signed in as admin"
  end

  def test_signin_with_user_credentials
    post "/users/signin", username: "user_test", password: "test1234"
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "user_test", session[:username]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Signed in as user_test"
  end

  def test_sign_out
    get "/", {}, admin_session
    assert_includes last_response.body, "Signed in as admin"

    post "/users/signout"
    assert_equal 302, last_response.status
    assert_nil session[:username]
    assert_equal "You have been signed out.", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    refute_includes last_response.body, "Signed in as"
  end

  def test_duplicating_document_signed_out
    create_document("test.txt")

    post "/test.txt/duplicate"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_duplicating_document
    create_document("test.txt")

    post "/test.txt/duplicate", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "test.txt was duplicated.", session[:message]

    get last_response["Location"]
    assert_includes last_response.body, "test_copy.txt"
  end

  def test_renaming_document_signed_out
    create_document("test.txt")

    get "/test.txt/rename"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]

    post "/test.txt/rename"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_renaming_document
    create_document("test_copy.txt")

    post "/test_copy.txt/rename", { rename: "test.txt" }, admin_session
    assert_equal 302, last_response.status
    assert_equal "test_copy.txt was renamed.", session[:message]

    get last_response["Location"]
    assert_includes last_response.body, "test.txt"

    get "/"
    refute_includes last_response.body, "test_copy.txt"
  end

  def test_signup_form
    get "/users/signup"

    assert_equal 200, last_response.status
    text = %q(<label>Please choose a username and a password to sign up)
    assert_includes last_response.body, text
    assert_includes last_response.body, %q(<input class="inline" name="username")
    assert_includes last_response.body, %q(input class="inline" name="password")
  end

  def test_signup_with_empty_password
    post "/users/signup", username: "new_user", password: ""
    assert_equal 422, last_response.status
    assert_nil session[:username]
    assert_includes last_response.body, "A username and a password are required."
    assert_includes last_response.body, %q(<input class="inline" name="username")
    assert_includes last_response.body, %q(input class="inline" name="password")
  end

  def test_signup_with_existing_username
    post "/users/signup", username: "nicolas", password: "secret"
    assert_equal 422, last_response.status
    assert_nil session[:username]
    expected_text = "Username already existing. Please choose another one."
    assert_includes last_response.body, expected_text
    assert_includes last_response.body, %q(<input class="inline" name="username")
    assert_includes last_response.body, %q(input class="inline" name="password")
  end

  def test_signup_with_valid_credentials
    post "/users/signup", username: "new_user", password: "secret"
    assert_equal 302, last_response.status
    assert_equal "Welcome, you've been registered!", session[:message]
    assert_equal "new_user", session[:username]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Signed in as new_user"
  end

  def test_upload_form_signed_out
    get "/img_upload"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_upload_form
    get "/img_upload", {}, admin_session

    assert_equal 200, last_response.status
    expected_text = %q(<input name="image" type="file" accept=".png, .jpg,)
    assert_includes last_response.body, expected_text
    expected_text = %q(<label for="image">Select image to upload:)
    assert_includes last_response.body, expected_text
  end

  def test_upload_image
    img_path_dir = File.expand_path("..", __FILE__)
    img_path = File.join(img_path_dir, "/images/ruby.jpg")
    img = Rack::Test::UploadedFile.new(img_path, "image/jpeg")

    post "/img_upload", { image: img }, admin_session
    assert_equal "An image ruby.jpg has been uploaded.", session[:message]
    assert_equal 302, last_response.status

    get last_response["Location"]

    get "/"
    assert_includes last_response.body, "ruby.jpg"
  end
end
