#!/usr/bin/ruby

# Do debug logger output to stderr
DEBUG=false

class TactLogger
  def initialize
    @log = nil
  end
  
  def set_log(path)
    self.close_log if @log
    @log = File.new(path, "a")
  end

  def close_log
    @log.close if @log != nil
    @log = nil
  end

  def print(str)
    str = "Warning: empty log str.\n" if !str || str.to_s.empty?
    
    if DEBUG
      $stderr.print("Logger: "+str)
    end
    
    if @log
      @log.print(str)
      @log.flush
    end
  end

  def puts(str)
    str = "Warning: empty log str." if !str || str.to_s.empty?
    self.print(str.to_s+"\n")
  end
end
