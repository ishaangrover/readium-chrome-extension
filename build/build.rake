require 'digest/md5'

# the root directory of the project. all other paths should
# be specified as relative paths to this
proj_root_dir = "/Users/matthew/ep/readium/readium"

# name of the directory that contains application scripts
scripts_dir = "scripts"

# a list of scripts that should not be compressed durring the build
# process
exclude_scripts = ["scripts/libs/plugins.js"]

# the directory to publish into
publish_dir = "readium"

# path the closure compiler jar
cc_jar_path = "build/tools/closure-compiler-v1346.jar"

# list of files and dirs that need to be copied over to 
# the deploy dir as are with no processing
simple_copies = ["background/**/*", "css/viewer_manifest.css", "css/library.css", "images/**/*", "manifest.json", "LICENSE"]


js_libs = ["lib/jquery-1.7.1.min.js", "lib/mathjax/**/*", "lib/pan_and_zoom.js", "scripts/libs/plugins.js", "lib/modernizr-2.5.3.min.js", "lib/2.5.3-crypto-sha1.js"]

# html view files that need to have 
html_files = ["views/library.html", "views/viewer.html"]

# absolute path to chrome pem key
pem_path = "/Users/matthew/ep/readium/packing-dir/readium.pem"

# the command used to start chrome when building the extension
chrome_command = "/Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome"

# the regular expression used to identify the list of scripts that
# should be concatenated together into one file
scripts_regex = /<!-- scripts concatenated and minified via build script -->((?:.|\s)*?)<!-- end scripts -->/

# get a temporary name for a script file to hold concatenated
# scripts in an html file
def concat_script_name html_name
	name = "contcatenated-#{ html_name }#{'.js'}"
	name.gsub /\//, "" #get rid of any /'s
end

# generate a name for a script file by taking a MD5
# hash of its contents
def hash_script_name path, opts = {}
	opts[:prefix] ||= ""
	opts[:ext] ||= ".js"
	# hash the file and append.js
	"#{opts[:prefix]}#{Digest::MD5.file(path).to_s}.js"
end

def concat_scripts script_files, output_path
	puts script_files.join "\n"
	File.open output_path, "w" do |out|
		script_files.each { |in_path| out.puts(IO.read(in_path)) }
	end
end

def script_tag src
	"<script src='#{src}' type='text/javascript'></script>"
end

def create_leading_dirs path
	dir_path = File.dirname(path)
	FileUtils.mkdir_p dir_path unless File.exists? dir_path
end

namespace :build do

	desc "build extension" 
	task :crx do
		path = File.join proj_root_dir, publish_dir
		puts "packaging contents of #{path} as a .crx"
		puts `#{chrome_command} --pack-extension=#{path} --pack-extension-key=#{pem_path}`
	end

	desc "Minify and copy all scripts into publish dir"
	task :copy_scripts => "create_workspace" do
		puts "compressing the individual scripts and moving into #{publish_dir}"
		jsfiles = File.join(scripts_dir, "**", "*.js")
		script_list = Dir.glob(jsfiles)

		# remove any scripts that should be excluded
		script_list.reject! {|path| exclude_scripts.include? path }

		script_list.each do |in_path|
			out_path = File.join(publish_dir, in_path)

			# we need to create the leading subdirs because
			# yui will fail if they do not exist
			dir_path = File.dirname(out_path)
			FileUtils.mkdir_p dir_path unless File.exists? dir_path

			puts "compressing #{in_path}"
			output = `java -jar #{cc_jar_path} --js #{in_path} --js_output_file #{out_path}`
		end
	end

	desc "copy over files that require no processing"
	task :simple_copies do
		cops = simple_copies + js_libs
		cops.each do |pattrn|
			Dir.glob(pattrn).each do |in_path|

				out_path = File.join(publish_dir, in_path)

				create_leading_dirs out_path
				
				if File.directory? in_path
					FileUtils.mkdir_p out_path
				else
					FileUtils.cp in_path, out_path
				end
			end

		end
	end

	desc "copy over the html files and replace script tags with ref to one concat script"
	task :copy_html do
		html_files.each do |in_path|
			out_path = File.join(publish_dir, in_path)
			content = IO.read(in_path)
			puts in_path

			script_name = concat_script_name in_path
			script_name = File.join publish_dir, scripts_dir, script_name
			puts "concatenating scripts into #{script_name}"

			
			x = scripts_regex.match content
			x ||= ""
			srcs = []
			x.to_s.scan(/<script src=(['"])(.+?)\1 .+?<\/script>/)  { |res| srcs << res[1]}
			srcs.map! {|src| File.join publish_dir, src }
			concat_scripts srcs, script_name

			hash_name = hash_script_name script_name
			hash_name = File.join "/", scripts_dir, hash_name
			File.rename script_name, File.join(publish_dir, hash_name)

			


			x = content.gsub scripts_regex, script_tag(hash_name)

			out_path = File.join(publish_dir, in_path)
			create_leading_dirs out_path

			File.open out_path, "w" do |out|
				out.puts x
			end
		end
	end

	task :replace_tag do |t, args| 

	end

	desc "Create working dirs for the build process"
	task :create_workspace => "clean:total" do
		puts "creating the working dir"
		puts `mkdir #{publish_dir}`
	end

	namespace :clean do

		desc "clean up the results of the last build"
		task :total do
			puts "removing the old publish dir if it exists"
			`rm -rf #{publish_dir}`
		end

		task :default => :total

	end

	desc "The default clean task"
	task :clean => "clean:total"

end

#define the default build process
task :build => ["build:copy_scripts", "build:simple_copies", "build:copy_html", "build:crx"]