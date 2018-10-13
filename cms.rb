require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis" # erb view templates
require "redcarpet" # markdown parser
require 'yaml' # YAML format parser
require 'bcrypt' # passwords encryption

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

def render_markdown(text)
  renderer = Redcarpet::Render::HTML.new(no_styles: true)
  markdown = Redcarpet::Markdown.new(renderer)
  markdown.render(text)
end

def load_file_content(file)
  content = File.read(file)
  case File.extname(file)
  when ".md"
    erb render_markdown(content), layout: :layout
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  end
end

def valid_extension?(filename)
  %w(.md .txt .jpg .png).include?(File.extname(filename))
end

def error_for_filename(filename)
  error_message = nil
  if filename.size == 0
    error_message = "A name is required."
  elsif valid_extension?(filename) == false
    error_message = "A valid file extension is required."
  end
  error_message
end

def load_user_credentials
  credentials_path = if ENV["RACK_ENV"] == "test"
                       File.expand_path("../test/users.yml", __FILE__)
                     else
                       File.expand_path("../users.yml", __FILE__)
                     end

  YAML.load_file(credentials_path)
end

def credentials_valid?(username, password)
  credentials = load_user_credentials

  credentials.any? do |name, pwd|
    name == username && BCrypt::Password.new(pwd) == password
  end
end

def extract_name_extension_from_filename(filename)
  filename.split('.')
end

def user_authorized?
  session.key?(:username)
end

def require_signed_in_user
  unless user_authorized?
    session[:message] = "You must be signed in to do that."
    redirect "/"
  end
end

# Add a new file
get "/new" do
  require_signed_in_user
  erb :new
end

# Create new file
post "/create" do
  require_signed_in_user

  filename = params[:filename].to_s

  error_message = error_for_filename(filename)
  if error_message
    session[:message] = error_message
    status 422 # Unprocessable Entity
    erb :new
  else
    file_path = File.join(data_path, filename)

    File.write(file_path, "")
    session[:message] = "#{filename} was created."

    redirect "/"
  end
end

# Display list of files in data directory
get "/" do
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map { |path| File.basename(path) }
  erb :index
end

# Open a file
get "/:filename" do
  file_path = File.join(data_path, params[:filename])

  if File.file?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

# Edit file content
get "/:filename/edit" do
  require_signed_in_user

  file_path = File.join(data_path, params[:filename])

  @fileread = params[:filename]
  @content = File.read(file_path)

  erb :edit, layout: :layout
end

# Save changes to edited file
post "/:filename" do
  require_signed_in_user

  file_path = File.join(data_path, params[:filename])

  File.write(file_path, params[:content])

  session[:message] = "#{params[:filename]} has been updated."
  redirect "/"
end

# Delete a file
post "/:filename/delete" do
  require_signed_in_user

  file_path = File.join(data_path, params[:filename])

  if File.file?(file_path)
    File.delete(file_path)
    session[:message] = "#{params[:filename]} was deleted."
  else
    session[:message] = "#{params[:filename]} does not exist."
  end

  redirect "/"
end

# Duplicating a file
post "/:filename/duplicate" do
  require_signed_in_user

  orig_file_path = File.join(data_path, params[:filename])

  if File.file?(orig_file_path)
    filename, extension = extract_name_extension_from_filename(params[:filename])
    new_file_path = File.join(data_path, filename + "_copy" + "." + extension)
    content = File.read(orig_file_path)
    File.write(new_file_path, content)
    session[:message] = "#{params[:filename]} was duplicated."
  else
    session[:message] = "#{params[:filename]} does not exist."
  end

  redirect "/"
end

# Form to rename a file
get "/:filename/rename" do
  require_signed_in_user

  file_path = File.join(data_path, params[:filename])
  @fileread = params[:filename]

  erb :rename, layout: :layout
end

# Renaming a file
post "/:filename/rename" do
  require_signed_in_user

  orig_file_path = File.join(data_path, params[:filename])
  new_filename = params[:rename].to_s

  if File.file?(orig_file_path)
    error_message = error_for_filename(new_filename)
    if error_message
      @fileread = params[:filename]
      session[:message] = error_message
      status 422 # Unprocessable Entity
      erb :rename
    else
      new_file_path = File.join(data_path, new_filename)
      content = File.read(orig_file_path)
      File.write(new_file_path, content)
      File.delete(orig_file_path)
      session[:message] = "#{params[:filename]} was renamed."
      redirect "/"
    end
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

# Login form
get "/users/signin" do
  erb :signin
end

# Login validation
post "/users/signin" do
  username = params[:username].to_s
  password = params[:password].to_s

  if credentials_valid?(username, password)
    session[:username] = username
    session[:message] = "Welcome!"
    redirect "/"
  else
    session[:message] = "Invalid Credentials"
    status 422 # Unprocessable Entity
    erb :signin
  end
end

# Sign out
post "/users/signout" do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect "/"
end
