#!/usr/bin/ruby -w

# If this script exists, do not run test, just evaluate the compiler options given
# LOCAL_RUN_SCRIPT="./local_run_test" # commented fornow

# Custom handler is needed for ruby to pass SIGINT into process executed with system()
Signal.trap("INT") do
    thread_count = 0
    Thread.list.each do |t|
      thread_count += 1
      err_msg = "[DEBUG] thread #{thread_count} of total #{Thread.list.size} backtrace:\n"
      err_msg += t.backtrace.join("\n")
      err_msg += "\n\n"
      puts(err_msg)
    end
  raise Interrupt, "SIGINT catched"
end

require File.expand_path(File.dirname(__FILE__)) + '/WorkDirPool.rb'
require File.expand_path(File.dirname(__FILE__)) + '/TactLogger.rb'
require 'fileutils.rb'
require File.expand_path(File.dirname(__FILE__)) + '/ResultsParserBase.rb'
require File.expand_path(File.dirname(__FILE__)) + '/VerifyResults.rb'
require File.expand_path(File.dirname(__FILE__)) + '/ComputeScore.rb'
require 'thread'

def run_system(command)
	res = `#{command}`
	ret_val = $?.exitstatus
	puts "[SYSTEM] #{res}" if res != ""
	return ret_val
end

class TestRunner
  attr_accessor :binary_size
  attr_accessor :binary_hash
  attr_accessor :score
  attr_accessor :asm

  def initialize(params)
    #initialize some useful variables
    @work_dir = nil     # working directory
    @local_result = nil # result of run
    @binary_size = nil
    @binary_hash = ""
    @score = nil
    @compiled = nil
    @binary_size = 0
    @error = nil
    
    @params = params    # test parameters
    @total_testboards = @params[:testboards]
    @measure = @params[:measure]
    @compile_options = @params[:compile_options]
    @pgo_session = @params[:do_profiling]
    @population_num = @params[:population_num]
    @generation_num = @params[:generation_num] ? @params[:generation_num] : 0
    @greater_is_better = @params[:greater_is_better]
    @timeout = @params[:timeout] ? @params[:timeout] : 0

    @profiling_stages = {
      1 => "profile_generate",
      2 => "profile_use"
    }
    
    params[:compile_only] = true if @measure == "size"
    
#    @current_testboard = ((@population_num - 1) % @total_testboards) + 1
    #FIXME
    @current_testboard = @params[:board_id]  

    @log = TactLogger.new

    # Assume that we were run from the test directory
    @test_dir = get_current_test_dir
    @work_dir_pool = WorkDirPool.new(@test_dir + "/pool")
    
    # Results parser
    require get_script_path('bin/parse-results.rb')
		
    output_msg("Begin")

    # Get us a directory
    @work_dir = @work_dir_pool.allocate_work_dir()

    output_msg("Working in #{@work_dir}")

    set_status("allocated")
    @work_dir_pool.prepare_dir_for_next_run(@work_dir)

    @log.set_log("#{@work_dir}/log/progress.log")
    datestamp_log("progress", "Start")

    @log.puts "Working in #{@work_dir}"
    
    begin
      do_compilation(1)
      return if !@compiled
      
      output_msg("Compiled")
	
      if @pgo_session 
        do_run(1)
        do_compilation(2)
        return if !@compiled
        do_run(2) if not params[:compile_only]
      else
        do_run(1) if not params[:compile_only]
      end

      analyze_size if @measure == "size" || @measure == "pareto"
      analyze_results
	
    ensure
      cleanup      
    end

  ensure
    if @work_dir
      @work_dir_pool.free_work_dir(@work_dir)
      @work_dir = nil
      output_msg("Work dir free")
    end
  end
	
  def analyze_size
    if !File.exist?("#{@test_dir}/bin/compute-size") then
      output_msg("[ERROR] Script compute-size not found!")
      @error = "ERR_NO_COMPUTE_SIZE"
      return
    end
    
    @binary_size = `#{@test_dir}/bin/compute-size '#{@work_dir}'`.to_f
    if @binary_size.to_i == 0
      @error = "ERR_ZERO_SIZE"
      @binary_size = nil
    end
  end
  
  def set_status(status)
    f = File.new(@work_dir+'/status', "w")
    f.print(@work_dir[/[^\/]+$/]+" ")
    f.print("p:#{@population_num} ")
    f.puts(status)
    f.close
  end

  def get_xml_log_file_name
    if @params[:xml_run_log]
      return @params[:xml_run_log]
    else
      xml_log_dir = @test_dir + "/log/current/runs"
      return sprintf("%s/res-%03d-%02d-%03d.xml", xml_log_dir, @params[:generation_num], @params[:population_num], 
        @params[:run_num])
    end
  end

  def datestamp_log(name, caption)
      `(echo -n '=== #{caption}: '; date; echo ) >> #{@work_dir}/log/#{name}.log`
  end

  def compile_error(msg, current_options)
    @log.puts "ERROR: #{msg}"
    write_results_log("ERR_BUILD", current_options, @generation_num, @population_num)
    gen_error_xml_script = ENV['TACT_DIR'] + '/bin/gen-xml-results-compile-error'
    xml_log_file = get_xml_log_file_name
    run_system("FLAGS='#{current_options}' #{gen_error_xml_script} >#{xml_log_file}")
  end

  def output_msg(msg)
    $stderr.puts("[gen: " + @generation_num.to_s + ", pop: " + @population_num.to_s + ", run: " + @params[:run_num].to_s + "] " + msg)
  end

  ###########################################################
  #  Compile test
  ###########################################################  
  def do_compilation(profiling_stage=1)
    @compiled = false
    current_options = @compile_options
    
    # Save current options here, to print them after to xml file, without profiling info
    current_options_clean = current_options

    profiling_stage = 2 if !@pgo_session and @params[:force_profile_use]
    
    if @pgo_session or @params[:force_profile_use]
      set_status("compiling\t["+ @profiling_stages[profiling_stage] + "]")
      @log.puts("Starting compilation for profiling stage #{profiling_stage} (" + @profiling_stages[profiling_stage] + ").")
      output_msg("Compiling for profiling stage: " + @profiling_stages[profiling_stage])
      
      profile_dir = @params[:profile_dir]
      profile_dir = @work_dir + "/profile" if profile_dir == nil
      
      if profiling_stage == 1
        FileUtils.rm_rf(profile_dir,:secure => true) if File.directory?(profile_dir)
        Dir.mkdir(profile_dir)
        
        current_options = "-fprofile-dir='#{profile_dir}' -fprofile-generate -ftest-coverage -fprofile-arcs " + current_options
      else
        if !File.directory?(profile_dir) or Dir.entries(profile_dir).size == 2
          output_msg("Error: '#{profile_dir}' is empty!")
          compile_error("'#{profile_dir}' doesn't contain anything (i.e. profile hasn't been gathered)", current_options_clean)
          exit 8
        end
        
        current_options = "-fprofile-dir='#{profile_dir}' -fprofile-use -fprofile-correction " + current_options
      end
    else
      output_msg("Compiling")
      set_status("compiling")
    end

    @log.puts("Compiling with options '#{current_options}'...")

    pid = fork do
      datestamp_log("build", "Start")
      wd = Dir.getwd
      failed = false
      
      begin
        compile_script_path = get_script_path('bin/rebuild-pool')
        Dir.chdir(@work_dir+"/build")

        if @params[:assembly] and (not @pgo_session or profiling_stage == 2)
          run_system("POOL_DIR='#{@work_dir}' FLAGS='#{current_options}' #{get_script_path('bin/assembly')} > #{@work_dir}/log/assembly.s 2>> #{@work_dir}/log/build.log")
          @asm = "#{@work_dir}/log/assembly.s"
        else
	  if run_system("POOL_DIR='#{@work_dir}' FLAGS='#{current_options}' #{compile_script_path} >> #{@work_dir}/log/build.log 2>&1") != 0
            compile_error("Compilation with '#{current_options}' failed.", current_options_clean)
            output_msg("Compilation failed")
	    failed = true
          end
        end
        
        rescue Interrupt => e
          failed = true
        ensure
          Dir.chdir(wd)
          datestamp_log("build", "Finish")
          exit(2) if failed
        end
        exit(0)
    end
    
    begin
    	Process.wait(pid)
    ensure
    	child_res = $?.exitstatus
	cleanup if child_res != 0
    end
    
    return if child_res != 0

    @compiled = true
    set_status("compilation_finished")
    @log.puts("Compilation finished successfully.")
    output_msg("Compilation finished succesfully.")

    # Compute binary hash for the build
    gen_binary_hash_script = get_script_path('bin/compute-binary-hash')
    @binary_hash = `POOL_DIR='#{@work_dir}' #{gen_binary_hash_script}`.chomp

  end

  ###########################################################
  #  Run test
  ###########################################################
  def do_run(profiling_stage)
    
    @log.print("Trying to obtain an exclusive lock on communication with a test board #{@current_testboard}...")
    if @pgo_session
      set_status("request_run\t["+ @profiling_stages[profiling_stage] +"]")
    else
      set_status("request_run")
    end
   
    #write everything needed to file to execute on test board
    begin
      file = File.new("#{@work_dir}/board_run", 'w', 0744)
    rescue Exception
      puts "[DEBUG] create file failed! file:{@work_dir}/board_run."
      sleep 0.2
      retry
    end
 
    file.puts("#!/bin/sh")
    file.puts("echo -n '=== Start (test board time): '; date")
    if @timeout > 0
      file.puts("current_pid=$$")
      file.puts("(sleep #{@timeout} ; (flock 105 ; echo END_RUN ; echo OVERALL_STATUS=TIMEOUT ; echo -n '=== Finish (test board time): ' ; date ; pgid=`ps -ejH | grep -m 1 $current_pid | awk '{ print $2 }'` ; kill -9 -$pgid) 105>1.lock) &")
      file.puts("pid=$!")
    end
    file.puts("export TACT_DIR=#{ENV["TACT_DIR"]}")
    file.puts("export TEST_DIR=#{ENV["TEST_DIR"]}")
    file.puts("export APP_DIR=#{ENV["APP_DIR"]}")
    file.puts("export POOL_DIR=#{@work_dir}")
    file.puts("export REPETITIONS=#{@params[:repetitions]}")
    file.puts("echo REPETITIONS=#{@params[:repetitions]}")
    file.puts("echo BEGIN_RUN")
    file.puts("cd #{@work_dir}")
    # FIXME: Add wrapper for timeout, and return time -p here
    file.puts("sh -c #{ENV["TEST_DIR"]}/bin/target-run-test ; c=$? ; echo END_RUN ; if [ $c == 0 ] ; then echo OVERALL_STATUS=OK ; else echo OVERALL_STATUS=ERROR ; fi")
    file.puts("echo -n '=== Finish (test board time): ' &&  date")
    file.puts("pgid=`ps -ejH | grep -m 1 $pid | awk '{ print $2 }'` && (flock 105 ; kill -9 -$pgid) 105>1.lock") if @timeout > 0
    file.close

    if @pgo_session
      @log.puts("Starting run for profiling stage #{profiling_stage} ("+ @profiling_stages[profiling_stage] +")...")
      set_status("running\t["+ @profiling_stages[profiling_stage] +"]")
      output_msg("Running for profiling stage "+ @profiling_stages[profiling_stage])
    else
      @log.puts("Starting run.")
      set_status("running")
      output_msg("Running")
    end

    $stderr.flush
    run_system("#{ENV["TACT_DIR"]}/task_manager/runb --board_id #{@current_testboard} --command \"#{@work_dir}/board_run\" >#{@work_dir}/log/run.log 2>&1")
 
    @log.print("Run finished.")
    output_msg("Run finished.")
    set_status("run_finished")

  end

  ###########################################################
  #  Analyze test results
  ###########################################################
  def analyze_results
    set_status("parsing_results")
    begin
      if @local_result
	@score = @local_result
      else
        params = { :result => "ok",
	    :repetitions => @params[:repetitions],
	    :compile_str => @compile_options,
	    :binary_size => @binary_size,
            :binary_hash => @binary_hash,
	    :test_board => @current_testboard,
	    :compile_only => @params[:compile_only]
        }          
          
        res_prefix = "#{@work_dir}/log/run"

	run_log = "-"
	run_log = "#{res_prefix}.log" if !@params[:compile_only]
          
        xml_file = File.new("#{res_prefix}.xml",'w')
        results = AppResultsParser.new(params,run_log).run(xml_file) if File.exists?(run_log) or run_log == "-"
        xml_file.close
        if File.exists?(run_log) or run_log == "-"
            overall_result = XPath.first(results, "//benchmark_run").attributes["result"]
        else
            overall_result = "ERR_XML"
        end

        if !overall_result.match(/^ok/i) && !@params[:compile_only]
          if overall_result == "TIMEOUT"
            @error = "ERR_TIMEOUT"
          else
            @error = "ERR_RUN"
          end
          @error = "ERR_XML" if overall_result == "ERR_XML"
          FileUtils.cp("#{res_prefix}.xml",get_xml_log_file_name)
        end

        if !@params[:compile_only] and !@error
          reference_file = "#{@test_dir}/log/current/ref/#{@current_testboard}-1.xml"
          params = { :reference_run => @params[:reference_run],
                     :reference_file => reference_file
          }
          # Verify xml structure and hashes
          verified = VerifyResults.new(results,params).run
          
          @error = "ERR_VERIFY" if !verified
            
	  # Parse xml and compute a final value
	  @score = compute_score(results) if verified
	    
        end
	@score = "COMPILE_ONLY" if @params[:compile_only]
        xml_file = File.new(get_xml_log_file_name,'w')
        results.write(xml_file, 2) if results
        xml_file.close
      end

      begin
	if @error
	  @log.puts("Run for '#{@compile_options}' failed (#{@error}).")
	  output_msg("Run failed (#{@error})")
	  @score = @error
	end
      ensure
	@score_log = "#{@score} (#{@binary_size})"
	@log.puts("Result = #{@score_log}")
        output_msg("Result = #{@score_log}")

	write_results_log(@score_log, @compile_options, @generation_num, @population_num)
	@score = nil if @error
      end
 
    end
    set_status("results_parsed")
  end
  
  # Write to results collection
  def write_results_log(val, compile_options, generation_num, population_num)
    begin
      CriticalSection.enter
      results_log=File.new("#{@test_dir}/log/current/results.log", "a")
      results_log.puts("#{val}\t#{generation_num}\t#{population_num}\t'#{@compile_options}'")
      results_log.close
    ensure
      CriticalSection.leave
    end
  end

  ###########################################################
  #  Cleanup
  ###########################################################
  def cleanup
    return if @work_dir == nil
    begin
	    @log.puts("Cleaning up.")
	    set_status("cleanup")

	    output_msg("Cleanup for #{@work_dir}")

	    datestamp_log("progress", "Finish")
	    #output_msg("Datestamp log")
	    @log.close_log
	    leaved = true

	    if !defined?($cleanMutex) or $cleanMutex == nil
		    $cleanMutex = Mutex.new
	    end

	    $cleanMutex.synchronize do
	        output_msg("Cleanup mutex for #{@work_dir}")
	    	# Save logs to global ones
	      	for name in ["build", "progress", "run" ] do
			`cat #{@work_dir}/log/#{name}.log >>#{@test_dir}/log/current/#{name}.log 2>/dev/null`
			# Do not delete logs in case we'd like to debug the last run
		end
		output_msg("Cleanup mutex free for #{@work_dir}")
	    end
    ensure
	    output_msg("Ensure cleanup")
	    set_status("free")
	    @work_dir_pool.free_work_dir(@work_dir)
            @work_dir = nil
    end
  end
end
