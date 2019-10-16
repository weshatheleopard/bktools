# encoding: utf-8
require 'rubygems'

require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end

desc 'Start IRB with all runtime dependencies loaded'
task :console, [:script] do |_t, args|
  # TODO: move to a command
  dirs = %w(ext lib).select { |dir| File.directory?(dir) }

  original_load_path = $LOAD_PATH

  _cmd = if File.exist?('Gemfile')
           require 'bundler'
           Bundler.setup(:default)
        end

  # add the project code directories
  $LOAD_PATH.unshift(*dirs)

  # clear ARGV so IRB is not confused
  ARGV.clear

  require 'irb'

  # set the optional script to run
  IRB.conf[:SCRIPT] = args.script
  IRB.start

  # return the $LOAD_PATH to it's original state
  $LOAD_PATH.reject! { |path| !original_load_path.include?(path) }
end
