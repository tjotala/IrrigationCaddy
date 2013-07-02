#!/usr/bin/env ruby
require 'rubygems'
require 'bundler'
require File.join(File.dirname(__FILE__), 'lib', 'irrigationcaddy')

puts "scanning..."
caddies = IrrigationCaddy::Controller.discover()
puts "found #{caddies.length} controllers"
caddies.each_with_index do |caddy, i|
	puts "IrrigationCaddy ##{i + 1} @ #{caddy}:"
	puts "Last Boot Time: #{caddy.boot_time}"
	puts "System Time: #{caddy.system_time}"
	puts "Status:\n#{JSON.pretty_generate(caddy.status)}"

	puts "Current Calendar:\n#{JSON.pretty_generate(caddy.calendar)}"

	(1..3).each do |prog|
		puts "Program ##{prog}:\n#{JSON.pretty_generate(caddy.program(prog))}"
	end
end
