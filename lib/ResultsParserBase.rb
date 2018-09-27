#!/usr/bin/ruby

require 'rexml/document'
include REXML

class ResultsParserBase
    attr_accessor :state
    attr_accessor :input
    attr_accessor :xmldata
    attr_accessor :test_descr

    attr_accessor :current_test_num
    attr_accessor :current_test_name
    attr_accessor :current_repetition
    attr_accessor :results
    attr_accessor :num_tests
    attr_accessor :num_reps
    attr_accessor :benchmark_run
    attr_accessor :in_custom_output_section


    # Function to be implemented in derived class
    def user_handle_single_line(line)
    end

    def set_current_test_name(test_name)
	@current_test_name = test_name
    end

    # Public functions
    def get_current_value(name)
	return @current_test_data[name]
    end

    def store_current_value(name, value)
	@current_test_data[name] = value
    end

    def store_current_test_data
	# If test name wasn't defined, get it from test description by its ordinal number
	#if !@current_test_name
	#    @current_test_name = XPath.first(@test_descr, "//test[#{@current_test_num}]").attributes['name']
	#end
	# TODO: if test name was set, make sure a corresponding description exists

	# Find DOM node to store data into
	test_node = XPath.first(@benchmark_run, "//test[@name='#{@current_test_name}']")

	# Create a test node if it doesn't exist
	if !test_node
	    test_node = @benchmark_run.add_element("test", 
						   { 'num' => @current_test_num, 'name' => @current_test_name } )
	end

	# Finally, save current_test_data into test_node
	test_node.add_element("run", @current_test_data )
	
	@current_test_data = Hash.new
    end

    def note_next_test
	# Store currently collected data, if this is not the first test
	if @current_test_num > 0
	    store_current_test_data
	end
	# Clear data
	@current_test_data = Hash.new

	# Before the first test @current_test_num == 0
	@current_test_num += 1
    end

    # The following functions generally should be private, but can be redefined as needed
    def initialize(params,file="-")
	if !ENV.has_key?('TEST_DIR')
	    puts 'error: TEST_DIR environment variable should be set'
	    exit 2
	end

	if (file == '-')
	  @input = $stdin
	else
          begin
             @input = File.open(file, 'r')
             rescue Exception
                 sleep 1
             retry
          end
	end

	@current_test_data = Hash.new

	@compile_only = params[:compile_only]
	
	@xmldata = Document.new
	params1 = {}
        params.each_key{|k|
          params1[k.to_s] = params[k] if k.class == Symbol
          params.delete(k) if k.class == Symbol
        }
	params.merge!(params1)
	@benchmark_run = @xmldata.add_element("benchmark_run", params)

	@test_descr = Document.new(File.new(ENV['TEST_DIR'] + "/etc/test-descr.xml"))
	@current_repetition = 0
        @bad_thing = nil
    end

    def run(out_file = $stdout)
        @current_test_num = 0
	if !@compile_only
	  while (line = @input.gets)
	    line.chomp!
	    handle_single_line(line)
	  end
	else
          @benchmark_run.attributes["result"] = "OK"
	end

	# Store data for the last test; otherwise it would have been called from
	# note_next_test()
	if @current_test_num > 0
	  store_current_test_data
	end

        @benchmark_run.attributes["compiler"] = `compiler-version`.strip

	# Output XML file
	@xmldata.write(out_file, 2)
	return @xmldata
    end
    

    def default_handle_single_line(line)
      matches = line.match(/^REPETITION=(\d+)/)
      if matches && matches.length == 2
	# Store current test data from the previous repetition, if any
	if @current_repetition > 0
	    store_current_test_data
	end
        @current_repetition = matches[1].to_i
        @current_test_num = 0
      end

      matches = line.match(/^HASH=(.+)$/)
      if matches && matches.length == 2
        store_current_value('hash', matches[1])
      end

      matches = line.match(/^STATUS=(.+)$/)
      if matches && matches.length == 2
        store_current_value('result', matches[1])
        if matches[1] != "OK"
          @bad_thing = matches[1]
        end
      end
    end

    def handle_single_line(line)
      if user_handle_single_line(line) != :handled
        default_handle_single_line(line)
      end
      
      matches = line.match(/^BINARY_HASH=([0-9a-fA-F]+)/)
      if matches && matches.length == 2
        @benchmark_run.attributes["binary_hash"] = matches[1]
      end
      
      matches = line.match(/^OVERALL_STATUS=(\w+)/)
      if matches && matches.length == 2 && @bad_thing == nil
        @benchmark_run.attributes["result"] = matches[1]
      end
      
      if @bad_thing != nil
        @benchmark_run.attributes["result"] = @bad_thing
      end
    end
end
