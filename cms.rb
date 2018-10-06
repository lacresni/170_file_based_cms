require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis" # erb view templates
require "redcarpet" # markdown parser

root = File.expand_path("..", __FILE__)

configure do
  enable :sessions
  set :session_secret, 'secret'
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def load_file_content(file)
  content = File.read(file)
  case File.extname(file)
  when ".md"
    render_markdown(content)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  end
end

# Display list of files in data directory
get "/" do
  @files = Dir.glob(root + "/data/*").map { |path| File.basename(path) }
  erb :index
end

# Open a file
get "/:filename" do
  file_path = root + "/data/" + params[:filename]

  if File.file?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

# Edit file content
get "/:filename/edit" do
  file_path = root + "/data/" + params[:filename]

  @fileread = params[:filename]
  @content = File.read(file_path)
  
  erb :edit
end

# Save changes to edited file
post "/:filename" do
  file_path = root + "/data/" + params[:filename]

  File.write(file_path, params[:content])

  session[:message] = "#{params[:filename]} has been updated."
  redirect "/"
end
