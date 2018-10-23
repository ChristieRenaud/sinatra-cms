ENV["RACK_ENV"] = "test"

require 'minitest/autorun'
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

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { username: "admin" } }
  end

  def test_index
    create_document("about.md")
    create_document("changes.txt")

    get "/"
    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(last_response.body, "about.md")
    assert_includes(last_response.body, "changes.txt")
  end

  def test_sort_by_abc
    create_document("about.md")
    create_document("changes.txt")

    post "/sort/abc"
    assert_equal(302, last_response.status)
    assert_equal("abc", session[:sort])

    get "/"
    assert_equal(["about.md", "changes.txt"], @files)
  end

  def test_sort_by_date
    create_document("about.md")
    create_document("changes.txt")

    post "/sort/date"
    assert_equal(302, last_response.status)
    assert_equal("date", session[:sort])
  end

  def test_text

    create_document("changes.txt", "Ch-ch-changes")

    get "/changes.txt"
    assert_equal(200, last_response.status)
    assert_equal("text/plain", last_response["Content-Type"])
    assert_includes(last_response.body, "Ch-ch-changes")
  end

  def test_no_file
    get "/not_a_file"
    assert_equal(302, last_response.status)

    assert_equal("not_a_file does not exist.", session[:message])
  end

  def test_viewing_markdown_document
    create_document("about.md", "###Redcarpet")

    get "/about.md"
    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(last_response.body, "<h3>Redcarpet</h3>" )
  end

  def test_editing_document
    create_document("changes.txt")

    get "/changes.txt/edit", {}, admin_session
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "<textarea")
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_editing_document_signed_out
    create_document("changes.txt")
    get "/changes.txt/edit"
    assert_equal("You must be signed in to perform this action.", session[:message])
    assert_equal(302, last_response.status)
  end

  def test_updating_document
    create_document("changes.txt")

    post "/changes.txt", { content: "new content" }, admin_session
    
    assert_equal(302, last_response.status)

    assert_equal("changes.txt has been updated.", session[:message])

    get "/changes.txt"
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "new content")
  end

  def test_updating_document_signed_out
    post "/changes.txt", {content: "new content"}
    assert_equal("You must be signed in to perform this action.", session[:message])
    assert_equal(302, last_response.status)
  end

  def test_view_new_document_form_signed_in
    get "/new", {}, admin_session
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "<input")
    assert_includes(last_response.body, %q(<button type="submit"))
  end

  def test_view_new_document_form_signed_out
    get "/new"
    assert_equal("You must be signed in to perform this action.", session[:message])
    assert_equal(302, last_response.status)
  end

  def test_create_new_document
    post "/create", { filename:"test.txt" }, admin_session
    assert_equal(302, last_response.status)
    assert_equal("test.txt has been created.", session[:message])

    get "/"
    assert_includes(last_response.body, "test.txt")
  end

  def test_create_new_document_signed_out
    post "/create", { filename:"test.txt" }
    assert_equal("You must be signed in to perform this action.", session[:message])
    assert_equal(302, last_response.status)
  end

  def test_create_new_document_without_filename
    post "/create", {filename:""}, admin_session
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, "A name is required")
  end

    def test_create_new_document_without_valid_extension
    post "/create", {filename:"some_file"}, admin_session
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, "File must have a .txt or .md extension.")
  end

  def test_deleting_document
    create_document("test.txt")

    post "test.txt/delete", {}, admin_session

    assert_equal(302, last_response.status)

    assert_equal("test.txt has been deleted.", session[:message])

    get "/"
    refute_includes(last_response.body, %q(href="test.txt"))
  end

  def test_deleting_document_not_signed_in
    create_document("test.txt")

    post "test.txt/delete"
    assert_equal("You must be signed in to perform this action.", session[:message])
    assert_equal(302, last_response.status)
  end

  def test_view_signin_form
    get "/users/signin"

    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "<input")
  end

  def test_signin
    post "/users/signin", username:"admin", password:"secret"
    assert_equal(302, last_response.status)
    assert_equal("Welcome", session[:message])
    assert_equal("admin", session[:username])

    get last_response["Location"]
    assert_includes(last_response.body, "Signed in as admin")
  end

  def test_signin_with_wrong_credentials
    post "/users/signin", username:"guest", password:"secret"
    assert_equal(422, last_response.status)
    assert_nil(session[:username])
    assert_includes(last_response.body, "Invalid credentials")

    post "/users/signin", username:"admin", password:"shhh"
    assert_equal(422, last_response.status)
    assert_nil(session[:username])
    assert_includes(last_response.body, "Invalid credentials")
  end

  def test_signout
    get "/", {}, {"rack.session"=> { username: "admin" } }
    assert_includes(last_response.body, "Signed in as admin")

    post "/users/signout"
    get last_response["Location"]

    assert_nil(session[:username])
    assert_includes(last_response.body, "You have been signed out")
    assert_includes(last_response.body, "Sign In")
  end

end