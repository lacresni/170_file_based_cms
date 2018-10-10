require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis" # erb view templates
require "redcarpet" # markdown parser

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

def error_for_filename(filename)
  error_message = nil
  if filename.size == 0
    error_message = "A name is required."
  elsif %w(.md .txt).include?(File.extname(filename)) == false
    error_message = "A file extension is required."
  end
  error_message
end

def credentials_valid?(username, password)
  username == "admin" && password == "secret"
end

def user_authorized?
  session[:username] == "admin"
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
