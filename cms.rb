require "bcrypt"
require "sinatra"
require "sinatra/reloader"
require "securerandom"
require "tilt/erubis"
require "redcarpet"
require "yaml"

VALID_FILE_EXTENSIONS = %w(.txt .md)

configure do
  enable :sessions
  set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def get_file_names
  pattern = File.join(data_path, "*")
  Dir.glob(pattern).map do |path|
    File.basename(path)
  end
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def load_file_contents(path)
  content = File.read(path)
  case File.extname(path)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".md"
    erb render_markdown(content)
  end
end

def user_signed_in?
  session[:username]
end

def require_signed_in_user
  unless user_signed_in?
    session[:message] = "You must be signed in to do that"
    redirect "/"
  end
end

def redirect_not_found(path)
  unless File.exist?(path)
    session[:message] = "'#{params[:filename]}' does not exist"
    redirect "/"
  end
end

# View all files
get "/" do
  @files = get_file_names
  puts @users
  erb :index, layout: :layout
end

# View sign in
get "/users/signin" do
  erb :signin, layout: :layout
end

def load_user_credentials
  credentials_path = if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end

  YAML.load_file(credentials_path)
end

def valid_credentials?(username, password)
  credentials = load_user_credentials
  credentials[username] == password
end

# Sign in into account
post "/users/signin" do
  username = params[:username]

  if valid_credentials? username, params[:password]
    session[:username] = username
    session[:message] = "Welcome!"
    redirect "/"
  else
    session[:message] = "Invalid Credentials"
    status 422
    erb :signin, layout: :layout
  end
end

# Sign out of account
post "/users/signout" do
  session.delete(:username)

  session[:message] = "You have been signed out"
  redirect "/"
end

# Add a new document
get "/new" do
  require_signed_in_user

  erb :new, layout: :layout
end

# View file contents
get "/:filename" do
  file_path = File.join(data_path, params[:filename])

  redirect_not_found(file_path)
  
  load_file_contents(file_path)
end

# Edit a file's contents
get "/:filename/edit" do
  require_signed_in_user

  file_path = File.join(data_path, params[:filename])

  redirect_not_found(file_path)

  @content = File.read(file_path)

  erb :edit, layout: :layout
end

def file_name_error(name)
  if name.strip.size == 0
    "A name is required"
  elsif VALID_FILE_EXTENSIONS.none? { |ext| name.end_with?(ext) }
    "Filename must include a valid extension"
  elsif get_file_names.include?(name)
    "'#{name}' already exists"
  else
    nil
  end
end

# Create a new document
post "/create" do
  require_signed_in_user

  filename = params[:filename]
  
  if error_message = file_name_error(filename)
    session[:message] = "#{error_message}"
    status 422

    erb :new, layout: :layout
  else
    file_path = File.join(data_path, filename)

    File.write(file_path, "")

    session[:message] = "'#{filename}' was created"
    redirect "/"
  end
end

# Update changes to a file's contents.
post "/:filename" do
  require_signed_in_user

  file_path = File.join(data_path, params[:filename])

  File.write(file_path, params[:content])

  session[:message] = "'#{params[:filename]}' has been updated"
  redirect "/"
end

# Delete a document
post "/:filename/delete" do
  require_signed_in_user

  file_path = File.join(data_path, params[:filename])

  File.delete(file_path)

  session[:message]= "'#{params[:filename]}' was deleted"
  redirect "/"
end