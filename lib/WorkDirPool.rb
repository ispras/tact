#!/usr/bin/ruby -w

# Returns absolute path to given script, searching first in TEST_DIR, then in APP_DIR
def get_script_path(name)
  res = ENV['TEST_DIR'] + '/' + name

  if !File.exist?(res)
    res = ENV['APP_DIR'] + '/' + name
  end

  if !File.exist?(res)
    $stderr.puts "ERROR: '#{name}' script doesn't exist neither in TEST_DIR or APP_DIR"
    exit 7
  end
    
  return res
end

def get_current_test_dir
  curr_dir = Dir.getwd

  if curr_dir[/^.*\/packages\/.*$/]
    matches = curr_dir.match(/^(\/.+\/packages\/[^\/]+)\/?.*$/)
    if (!matches)
      $stderr.puts "This script should be run from one of the 'packages/*' subdirectories. \nNot from #{curr_dir}"
      exit 1
    end
    package_dir = matches[1]
    ENV["PACKAGE_DIR"] = package_dir
    return package_dir
  else
    matches = Dir.getwd.match(/^(\/.+\/tests\/[^\/]+)\/?.*$/)
    if (!matches)
      $stderr.puts "This script should be run from one of the 'tests/*' subdirectories. \nNot from #{test_dir}"
#      puts Kernel.backtrace
      exit 1
    end
    test_dir = matches[1]
    ENV['TEST_DIR'] = test_dir
    return test_dir
  end
end

# Handle critical sections across all instances of the same script.
# We use this to operate lock files.
class CriticalSection
def initialize
@lock_file = nil
end
def CriticalSection.enter
  $mutex.synchronize do
    if !defined?(@lock_file) or !@lock_file then @lock_file = File.open(__FILE__) end
  end
  @lock_file.flock(File::LOCK_EX)
end

def CriticalSection.leave
@lock_file.flock(File::LOCK_UN)
end
end

class WorkDirPool
  def initialize(pool_dir = false)
    @pool_dir = (pool_dir)?(pool_dir):(get_current_test_dir + "/pool")
    @work_dir = nil
  end

  def allocate_work_dir()
  # FIXME: rewrite using semaphores (through lockfiles?)
		# flock("pool/lock") if no free dirs
    while true do # wait for free pool directory
    begin
      CriticalSection.enter
		
      Dir.new(@pool_dir).each do |x|
	dir = @pool_dir+'/'+x
	# Skip regular files, '.' and '..' dirs.
	next if !File.directory?(dir) || x[/^\.\.?$/]
		
	lock = dir +'/in_use'
	
	# Create a lock file if it doesn't exist
	if !File.exist?(lock)
          File.open(lock, "w").close
	  @work_dir = dir
	  return dir
	end
      end
		
      ensure
	CriticalSection.leave
      end

      sleep 1 # wait 1 second if all dirs are busy
    end
  end

  def prepare_dir_for_next_run(work_dir)
    # Clean old local logs
    for name in ["build", "progress", "run", "checksum" ] do
      begin
	filename = "#{work_dir}/log/#{name}.log"
	begin
          File.unlink(filename) if File.exist?(filename)
        rescue Exception
          sleep 1
          retry
        end
      end
    end
  end

  def free_work_dir(work_dir)
      return if work_dir == nil
      if work_dir.index(@pool_dir) != 0
	#raise "Working directory #{work_dir} should be within the pool #{@pool_dir}"
	return
      end

      begin
	CriticalSection.enter

	lock = work_dir + '/in_use'
	begin
	  File.unlink(lock) if File.exist?(lock)
        rescue Exception
          sleep 0.1
          retry
	end
      ensure
	CriticalSection.leave
      end
  end

end
    
