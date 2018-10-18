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

def render_markdown(text)
  renderer = Redcarpet::Render::HTML.new(no_styles: true)
  markdown = Redcarpet::Markdown.new(renderer)
  markdown.render(text)
end

# files helpers
def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def load_file_content(file)
  content = File.read(file)
  case File.extname(file)
  when ".md"
    erb render_markdown(content), layout: :layout
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".jpg", ".jpeg", ".png"
    send_file(file)
  end
end

def valid_extension?(filename)
  %w[.md .txt .jpeg .jpg .png].include?(File.extname(filename))
end

def image_extension?(filename)
  %w[.jpeg .jpg .png].include?(File.extname(filename))
end

def extract_name_extension(filename)
  filename.split('.')
end

def rename_file(old_file, new_file)
  orig_file_path = File.join(data_path, old_file)
  new_file_path = File.join(data_path, new_file)

  content = File.read(orig_file_path)
  File.write(new_file_path, content)
  File.delete(orig_file_path)
end

def error_for_filename(filename)
  error_message = nil
  if filename.empty?
    error_message = "A name is required."
  elsif valid_extension?(filename) == false
    error_message = "A valid file extension is required."
  end
  error_message
end

def yaml_path(type)
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/#{type}.yml", __FILE__)
  else
    File.expand_path("../#{type}.yml", __FILE__)
  end
end

# credentials helpers

def credentials_path
  yaml_path("users")
end

def store_credentials(username, password)
  credentials = load_user_credentials
  credentials[username] = BCrypt::Password.create(password).to_s

  File.open(credentials_path, "w") { |file| file.write(credentials.to_yaml) }
end

def load_user_credentials
  YAML.load_file(credentials_path)
end

def credentials_valid?(username, password)
  credentials = load_user_credentials

  credentials.any? do |name, pwd|
    name == username && BCrypt::Password.new(pwd) == password
  end
end

def signup_credentials_valid?(username, password)
  error_message = nil
  credentials = load_user_credentials

  if username.empty? || password.empty?
    error_message = "A username and a password are required."
  elsif credentials.key?(username)
    error_message = "Username already existing. Please choose another one."
  end
  error_message
end

# user helpers

def user_authorized?
  session.key?(:username)
end

def require_signed_in_user
  return if user_authorized?
  session[:message] = "You must be signed in to do that."
  redirect "/"
end

# history helpers
def history_path
  yaml_path("history")
end

def load_history
  YAML.load_file(history_path)
end

def store_history(filename)
  history = load_history || {}

  if history.key?(filename)
    file_path = File.join(data_path, filename)
    history[filename] << File.read(file_path)
  else
    history[filename] = []
  end

  File.open(history_path, "w") { |file| file.write(history.to_yaml) }
end

def delete_history(filename)
  history = load_history
  history.delete(filename)
  File.open(history_path, "w") { |file| file.write(history.to_yaml) }
end

def rename_history(oldname, newname)
  history = load_history
  history[newname] = history.delete(oldname) if history.key?(oldname)
  File.open(history_path, "w") { |file| file.write(history.to_yaml) }
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
    store_history(filename)
    session[:message] = "#{filename} was created."

    redirect "/"
  end
end

# Display list of files in data directory
get "/" do
  pattern = File.join(data_path, "*")
  allfiles = Dir.glob(pattern).map { |path| File.basename(path) }
  @images, @files = allfiles.partition do |file|
    image_extension?(file)
  end
  @history = load_history

  erb :index
end

# Upload image form
get "/img_upload" do
  require_signed_in_user

  erb :img_upload
end

# Upload an image
post "/img_upload" do
  require_signed_in_user

  name = params[:image][:filename]
  image = params[:image][:tempfile]

  image_path = File.join(data_path, name)
  File.write(image_path, image.read)

  session[:message] = "An image #{name} has been uploaded."
  redirect "/"
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

  store_history(params[:filename])

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
    delete_history(params[:filename])
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
    filename, extension = extract_name_extension(params[:filename])
    new_filename = filename + "_copy" + "." + extension
    new_file_path = File.join(data_path, new_filename)
    content = File.read(orig_file_path)
    File.write(new_file_path, content)
    store_history(new_filename)
    session[:message] = "#{params[:filename]} was duplicated."
  else
    session[:message] = "#{params[:filename]} does not exist."
  end

  redirect "/"
end

# Form to rename a file
get "/:filename/rename" do
  require_signed_in_user

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
      rename_file(params[:filename], new_filename)
      rename_history(params[:filename], new_filename)
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

# Signup form
get "/users/signup" do
  erb :signup
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

# Signup validation
post "/users/signup" do
  username = params[:username].to_s
  password = params[:password].to_s

  error_message = signup_credentials_valid?(username, password)
  if error_message
    session[:message] = error_message
    status 422 # Unprocessable Entity
    erb :signup
  else
    store_credentials(username, password)
    session[:username] = username
    session[:message] = "Welcome, you've been registered!"
    redirect "/"
  end
end

# Sign out
post "/users/signout" do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect "/"
end

# view file history
get "/:filename/history" do
  history = load_history
  @versions = history[params[:filename]]

  erb :history
end
