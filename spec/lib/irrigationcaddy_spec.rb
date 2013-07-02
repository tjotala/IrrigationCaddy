require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'irrigationcaddy')

describe IrrigationCaddy::Controller do
	before(:each) do
		@host = "192.168.1.#{Random.rand(0..255)}".freeze
	end

	describe '#parse_js' do
		it 'should clean-up a chunk of JS response' do
			js = <<-JS
var iv = {
	progNumber : '1',
	progAllowRun : 1,
	days : [1,1,0,1,1,1,1],
	progStartTimeHr : [7,8,12,12,12],
	progStartTimeMin : [0,0,0,0,0],
	isAM : [1,0,1,1,1],
	zNames : ["Backyard Lawn Left","Backyard Lawn Right","Backyard Perimeter","Front Lawn Close","Front Lawn Far","Backyard Trees By Fence","Trees by Tunbridge","Raised bed on Tunbridge","Driveway Trees",""],
	maxZRunTime : 60,
	maxZones : 10,
	zDur : [{hr:0, min:10},{hr:0, min:10},{hr:0, min:10},{hr:0, min:10},{hr:0, min:10},{hr:0, min:10},{hr:0, min:10},{hr:0, min:0},{hr:0, min:10},{hr:0, min:0}],
	everyNDays : 1,
	evenOdd : 2,
	maxProgs : 3,
	startTimesStatus : [0, 0, 0, 0],
	hostname : 'IRRIGATIONCADDY',
	ipAddress : '192.168.3.70'
}
JS
			parsed = IrrigationCaddy::Controller.parse_js(js)
			parsed.should be_an_instance_of(Hash)
			parsed.should have_key('progNumber')
			parsed.should have_key('ipAddress')
		end
	end

	describe '#initialize' do
		it 'should return a blank instance' do
			IrrigationCaddy::Controller.new.to_s.should be_empty
			IrrigationCaddy::Controller.new(nil).to_s.should be_empty
		end

		it 'should return an instance with host address' do
			IrrigationCaddy::Controller.new(@host).to_s.should == @host
		end
	end

	describe '#local_ip_addresses' do
		it 'should handle empty list of local addresses' do
			Socket.should_receive(:ip_address_list).with(no_args()).and_return([ ])
			IrrigationCaddy::Controller.local_ip_addresses.should == [ ]
		end

		it 'should handle non-empty list of local addresses' do
			sockaddr_v4_priv = Addrinfo.new([ 'AF_INET', Random.rand(1..65535), 'en0', '192.168.1.100' ])
			sockaddr_v4_goog = Addrinfo.new([ 'AF_INET', Random.rand(1..65535), 'en1', '74.125.239.105' ])
			sockaddr_v6 = Addrinfo.new([ 'AF_INET6', Random.rand(1..65535), 'en2', '::1' ])
			sockaddr_unix = Addrinfo.new([ 'AF_UNIX', '/tmp/sock' ])
			Socket.should_receive(:ip_address_list).with(no_args()).and_return([ sockaddr_v4_priv, sockaddr_v4_goog, sockaddr_v6, sockaddr_unix ])
			IrrigationCaddy::Controller.local_ip_addresses.should == [ sockaddr_v4_priv.ip_address ]
		end
	end

	describe '#discover' do
		before(:each) do
			IrrigationCaddy::Controller.should_receive(:local_ip_addresses).and_return([ @host ])
		end

		it 'should handle timeouts' do
			req = Net::HTTP.new(@host)
			req.should_receive(:get).exactly(256).times.and_raise(Timeout::Error)
			Net::HTTP.should_receive(:new).exactly(256).times.and_return(req)
			IrrigationCaddy::Controller.discover.should be_empty
		end

		it 'should handle system errors' do
			req = Net::HTTP.new(@host)
			req.should_receive(:get).exactly(256).times.and_raise(SystemCallError.new('dummy', -1))
			Net::HTTP.should_receive(:new).exactly(256).times.and_return(req)
			IrrigationCaddy::Controller.discover.should be_empty
		end
	end

	describe 'instance method' do
		before(:each) do
			@ic = IrrigationCaddy::Controller.new(@host)
		end

		describe '#status' do
			it 'should return a valid response' do
				ok = double(:code => '200', :body => { 'dummy' => 'response' })
				@ic.should_receive(:get).once.with('/status.json').and_return(ok)
				@ic.status.should == ok.body
			end
		end

		describe '#alive?' do
			it 'should return success' do
				ok = double(:code => '200', :body => { 'dummy' => 'response' })
				@ic.should_receive(:get).once.and_return(ok)
				@ic.alive?.should be_true
			end

			it 'should return failure' do
				fail = double(:code => '404', :body => { 'failed' => 'response' })
				@ic.should_receive(:get).once.and_return(fail)
				@ic.alive?.should be_false
			end
		end

		describe '#boot_time' do
			it 'should be able to parse an invalid response' do
				time = { "hr" => 7, "min" => 26 }
				ok = double(:code => '200', :body => time)
				@ic.should_receive(:get).once.and_return(ok)
				@ic.boot_time.should == Time.new(2000, 1, 1, 7, 26, 0)
			end

			it 'should be able to parse a valid response' do
				time = { "hr" => 7, "min" => 26, "sec" => 32, "day" => 6, "date" => 14, "month" => 6, "year" => 13 }
				ok = double(:code => '200', :body => time)
				@ic.should_receive(:get).once.and_return(ok)
				@ic.boot_time.should == Time.new(2013, 6, 14, 7, 26, 32)
			end
		end

		describe '#system_time' do
			it 'should be able to parse an invalid response' do
				time = { "hr" => 7, "min" => 26 }
				ok = double(:code => '200', :body => time)
				@ic.should_receive(:get).once.and_return(ok)
				@ic.system_time.should == Time.new(2000, 1, 1, 7, 26, 0)
			end

			it 'should be able to parse a valid response' do
				time = { "hr" => 7, "min" => 26, "sec" => 32, "day" => 6, "date" => 14, "month" => 6, "year" => 13 }
				ok = double(:code => '200', :body => time)
				@ic.should_receive(:get).once.and_return(ok)
				@ic.system_time.should == Time.new(2013, 6, 14, 7, 26, 32)
			end
		end

		describe '#calendar' do
			it 'should be able to parse an empty response' do
				calendar = [ { } ]
				ok = double(:code => '200', :body => calendar)
				@ic.should_receive(:get).once.and_return(ok)
				@ic.calendar.should == calendar
			end
		end
	end
end
