require "sinatra"
require "sinatra/reloader" if development?
require "sinatra/content_for"
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "bcrypt"

configure do
  enable :sessions
  set :session_secret, 'secret'
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def load_user_credentials
  credentials_path = if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
  YAML.load_file(credentials_path)
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def load_file_content(path)
  content = File.read(path)
  case File.extname(path)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".md"
    erb render_markdown(content)
  end
end

def load_filenames
  pattern = File.join(data_path, "*")
  files = Dir.glob(pattern).map do |path|
    File.basename(path)
  end
end

def user_signed_in?
  session.key?(:username)
end

def require_signed_in_user
  if !user_signed_in?
    session[:message] = "You must be signed in to perform this action."
    redirect "/"
  end
end

def valid_extension?(filename)
  [".md", ".txt"].any? { |ext| filename.match(ext) }
end

def valid_credentials?(username, password)
  credentials = load_user_credentials

  if credentials.key?(username)
    bcrypt_password = BCrypt::Password.new(credentials[username])
    bcrypt_password == password
  else
    false
  end
end

get "/" do 
  @files = load_filenames

  if session[:sort] == "abc"
    @files = @files.sort_by { |file| file.downcase }
  elsif session[:sort] == "date"
    @files = @files.sort_by{ |file| File.mtime(File.join(data_path, file)) }
  end

  erb :index
end

post "/sort/abc" do
  session[:sort] = "abc"
  redirect "/"
end

post "/sort/date" do
  session[:sort] = "date"
  redirect "/"
end
# shows a form to create a new document
get "/new" do
  require_signed_in_user
  erb :new
end

def filename_error(filename)
  if filename.size == 0
    "no name"
  elsif !valid_extension?(filename)
    "invalid extension"
  elsif load_filenames.include?(filename)
    "name already used"
  end
end

def error_action(error_message, view)
  session[:message] = "#{error_message}"
  status 422
  erb view
end

def process_error(filename, view)
  case filename_error(filename)
  when "no name"
    error_action("A name is required.", view)
  when "invalid extension"
    error_action("File must have a .txt or .md extension.", view)
  when "name already used"
    error_action("Filename already used. Please choose a new filename.", view)
  end
end


# post "/create" do
#   require_signed_in_user
#   filename = params[:filename].to_s
#   case filename_error(filename)
#   when "no name"
#     error_action("A name is required.", :new)
#   when "invalid extension"
#     error_action("File must have a .txt or .md extension.", :new)
#   when "name already used"
#     error_action("Filename already used. Please choose a new filename.", :new)
#   else
#     file_path = File.join(data_path, filename)

#     File.write(file_path, "")
#     session[:message] = "#{params[:filename]} has been created."
    
#     redirect "/"
#   end
# end

post "/create" do
  require_signed_in_user
  filename = params[:filename].to_s
  if filename_error(filename)
    process_error(filename, :new)
  else
    file_path = File.join(data_path, filename)

    File.write(file_path, "")
    session[:message] = "#{params[:filename]} has been created."
    
    redirect "/"
  end
end

get "/users/signin" do
  erb :signin
end

post "/users/signin" do
  username = params[:username]

  if valid_credentials?(username, params[:password])
    session[:username] = username
    session[:message] = "Welcome"
    redirect "/"
  else
    session[:message] = "Invalid credentials"
    status 422
    erb :signin
  end
end

post "/users/signout" do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect "/"
end

get "/:filename" do
  file_path = File.join(data_path, params[:filename])

  if File.exist?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

# Shows form to edit document
get "/:filename/edit" do
  require_signed_in_user
  file_path = File.join(data_path, params[:filename])
  
  @filename = params[:filename]
  @content = File.read(file_path)
  
  erb :edit
end

get "/:filename/rename" do
  require_signed_in_user
  @filename = params[:filename]
  
  erb :rename
end

post "/:filename/rename" do
  require_signed_in_user
  @filename = params[:filename]
  file_path = File.join(data_path, @filename)
  new_file_path = File.join(data_path, params[:new_filename])
  if filename_error(params[:new_filename])
    process_error(params[:new_filename], :rename)
  else
  
    File.rename(file_path, new_file_path)

    session[:message] = "File has been renamed."
    redirect "/"
  end
end

# sends form and updates document
post "/:filename" do
  require_signed_in_user
  file_path = File.join(data_path, params[:filename])
  File.write(file_path, params[:content])
  
  session[:message] = "#{params[:filename]} has been updated."
  redirect "/"
end

post "/:filename/duplicate" do
  require_signed_in_user
  file_path = File.join(data_path, params[:filename])

  extension = File.extname(file_path)
  new_filename = File.basename(params[:filename], ".*") + "copy" + extension
  new_file_path = File.join(data_path, new_filename)
  File.write(new_file_path, File.read(file_path))

  redirect "/"
end

# deletes file
post "/:filename/delete" do
  require_signed_in_user
  file_path = File.join(data_path, params[:filename])
  File.delete(file_path)

  session[:message] = "#{params[:filename]} has been deleted."
  redirect "/"
end
