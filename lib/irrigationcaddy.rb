#!/usr/bin/env ruby
require 'rubygems'
require 'bundler'
require 'uri'
require 'json'
require 'socket'
require 'net/http'
require 'parallel'

module IrrigationCaddy
	class NTP
		attr_reader :server, :timezone, :dst

		def initialize(server, timezone, dst)
			@server = server
			@timezone = timezone
			@dst = dst
		end
	end

	class Controller
		attr_reader :boot_time, :status
		attr_accessor :system_time, :zone_names

		public

		def initialize(host = nil, debug = nil)
			@http = Net::HTTP.new(host)
			@http.set_debug_output(debug) unless debug.nil?
			@http.open_timeout = 0.3
			@http.read_timeout = 5
		end

		def status
			get('/status.json').body
		end

		def boot_time
			self.class.parse_time(get('/bootTime.json').body)
		end

		def system_time
			self.class.parse_time(get('/dateTime.json').body)
		end

		def system_time=(time = Time.now)
			post('/setClock.htm', { :year => time.year - 2000, :month => time.month, :date => time.mday, :day => time.wday + 1, :hr => time.hour, :min => time.min, :sec => time.sec })
		end

		def ntp(ntp, server, tz, dst)
			post('/saveNTP.htm', { :isNTP => dtp ? 1 : 0, :ntpServer => server, :isDST => dst ? 1 : 0, :timezone => tz }).code.to_i == 200
		end

		def calendar(start_time = Time.now, end_time = Time.now + (60 * 60 * 24))
			get('/calendar.json', { :start => start_time.to_i, :end => end_time.to_i }).body
		end

		def zone_names
			program(1)[:zNames]
		end

		def zone_names=(names)
			params = { }
			names.each_with_index { |n, i| params[i] = n }
			post('/saveZoneNames.htm', params).code.to_i == 200
		end

		def program(n)
			# this op does not return proper Content-Type, plus the body is a chunk of JavaScript to boot
			Controller.parse_js(get('/js/indexVarsDyn.js', { :program => n }).body)
		end

		def alive?
			get('/status.json').code.to_i == 200
		end

		def to_s
			@http.address.to_s
		end

		class << self
			def discover(debug = nil)
				all_hosts = [ ]
				local_ip_addresses.each do |local|
					ip = local.split('.').map { |octet| octet.to_i }
					hosts = Parallel.map((0..255), :in_threads => 32) do |octet|
						host = ip.first(3).push(octet).join('.')
						ic = self.new(host, debug)
						ic.alive? ? ic : nil
					end
					all_hosts += hosts.compact
				end
				all_hosts
			end
		end

		private

		COMMON_HEADERS = {
			'User-Agent' => self.class.to_s,
			'Cache-Control' => 'no-cache',
			'Pragma' => 'no-cache',
			'Accept' => 'text/json, application/json'
		}

		def get(path, params = { }, headers = { })
			path = URI(path)
			path.query = "" if path.query.nil?
			params = { :time => Time.now.to_i.to_s }.merge(Hash.new(URI.decode_www_form(path.query))).merge(params)
			path.query = URI.encode_www_form(params)
			headers = COMMON_HEADERS.merge(headers)
			response = @http.get(path.to_s, headers)
			response.body = JSON.parse(response.body) if response['Content-Type'] =~ /.*\/json/
			response
		rescue Timeout::Error => e
			Net::HTTPRequestTimeOut.new('1.0', '408', 'Request Timeout')
		rescue SystemCallError => e
			Net::HTTPNotFound.new('1.0', '404', 'Not Found')
		end

		class << self
			def parse_time(dt)
				Time.new((dt['year'] || 0) + 2000, dt['month'], dt['date'], dt['hr'], dt['min'], dt['sec'])
			end

			def parse_js(str)
				JSON.parse(str.sub(/^\s*var\s*[^\s]+\s*=\s*/, '').gsub(/(\w+)(\s*:)/, '"\1"\2').gsub(/'([^']+)'/, '"\1"'))
			end

			def local_ip_addresses
				Socket.ip_address_list.keep_if { |a| a.ipv4_private? }.map { |a| a.ip_address }
			end
		end
	end
end
