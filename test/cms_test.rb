ENV["RACK_ENV"] = "test"

require "fileutils"

require "minitest/autorun"
require "rack/test"

require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def login
    post "/users/signin", username: "admin", password: "secret"
  end

  def teardown
    FileUtils.rm_rf(data_path)
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
    { "rack.session" => { username: "admin"} }
  end

  def test_index
    create_document "about.md"
    create_document "changes.txt"

    get "/"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
  end

  def test_view_text_document
    create_document "history.txt", "1993 - Yukihiro Matsumoto dreams up Ruby"

    get "/history.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_equal "1993 - Yukihiro Matsumoto dreams up Ruby", last_response.body
  end

  def test_view_nonexistent_file
    get "/made_up_file.txt"
    assert_equal 302, last_response.status
    assert_equal "'made_up_file.txt' does not exist", session[:message]
  end

  def test_view_markdown_document
    create_document("about.md", "# Ruby is...")

    get "/about.md"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end

  def test_edit_nonexistent_file
    get "/made_up_file.txt"
    assert_equal 302, last_response.status
    assert_equal "'made_up_file.txt' does not exist", session[:message]
  end

  def test_view_edit_form
    create_document("history.txt")

    get "/history.txt/edit", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_view_edit_form_logged_out
    create_document("history.txt")

    get "/history.txt/edit"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that", session[:message]
  end

  def test_update_document
    post "/changes.txt", {content: "new content"}, admin_session

    assert_equal 302, last_response.status
    assert_equal "'changes.txt' has been updated", session[:message]

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_update_document_logged_out
    post "/changes.txt", {content: "new content"}
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that", session[:message]
  end

  def test_view_new_document_form
    get "/new", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<input type="text")
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_view_new_document_form_logged_out
    get "/new"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that", session[:message]
  end

  def test_create_new_document
    post "/create", {filename: "sample.txt"}, admin_session
    assert_equal 302, last_response.status
    assert_equal "'sample.txt' was created", session[:message]

    get "/"
    assert_includes last_response.body, "sample.txt"
  end

  def test_creating_new_document_logged_out
    post "/create", {filename: "sample.txt"}
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that", session[:message]
  end

  def test_creating_new_document_with_empty_name
    post "/create", {filename: ""}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required"
  end

  def test_creating_new_document_with_no_extension
    post "/create", {filename: "test"}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Filename must include a valid extension"
  end

  def test_creating_new_document_with_existing_name
    create_document("test.txt")

    post "/create", {filename: "test.txt"}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "'test.txt' already exists"
  end

  def test_delete_a_document
    create_document("test.txt")

    post "/test.txt/delete", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "'test.txt' was deleted", session[:message]

    get "/"
    refute_includes last_response.body, %q(href="test.txt")
  end

  def test_delete_a_document_logged_out
    create_document("test.txt")

    post "/test.txt/delete"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that", session[:message]
  end

  def test_access_index_logged_in
    get "/", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Signed in as"
  end

  def test_access_index_logged_out
    get "/"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Sign In"
  end

  def test_access_signin_page
    get "/users/signin"

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<input type="text")
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_login_with_invalid_credentials
    post "/users/signin", username: "fake", password: "fake"

    assert_equal 422, last_response.status
    assert_nil session[:username]
    assert_includes last_response.body, "fake"
    assert_includes last_response.body, "Invalid Credentials"
  end

  def test_successful_login
    post "/users/signin", {username: "admin", password: "secret"}
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:username]

    get last_response["Location"]
    assert_includes last_response.body, "Signed in as admin"
  end

  def test_signout
    get "/", {}, admin_session
    assert_includes last_response.body, "Signed in as admin"

    post "users/signout"
    assert_equal "You have been signed out", session[:message]

    get last_response["Location"]
    assert_nil session[:username]
    assert_includes last_response.body, "Sign In"
  end
end