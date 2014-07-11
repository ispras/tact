#!/usr/bin/ruby

require 'rexml/document'
require 'set'
require 'optparse'
require 'TestRunner.rb'
include REXML
include Math

####################################################################################################
def normalize(flag)
  r = \
  case flag
  when /^(.+)=(.*)$/
    $1
  when /^-fno-(.+)$/
    "-f" + $1
  when /^-mno-(.+)$/
    "-m" + $1
  when /^-DNO_(.+)$/
    "-D" + $1
  when /^(-f.+)$/
    $1
  when /^(-m.+)$/
    $1
  when /^(-D.+)$/
    $1
  when /^(.+)$/
    $1
  end

  @all_flags.add(r)

  if not @order_done
    if @order.has_key?(r)
      m = @order[r]
      if @order_n > m
        @order[r] = @order_n 
        @order_n += 1
      end
    else
      @order[r] = @order_n
      @order_n += 1
    end
  end

  if !@order.has_key?(r)
  	@order[r] = @order_n
        @order_n += 1
  end


  return r
end

def parse_flags(compile_str)
  if compile_str.match(/(\s*(--param\s+\S+|\S+)\s*)*/)
    cs = compile_str.scan(/\s*(--param\s+\S+|\S+)\s*/).map {|f| [normalize(f[0]), f[0]]}
    @order_done = true
    return cs
  else
    $stderr.puts "Wrong compile string! ignored"
  end
end

def flags_to_string(flags)
#	puts "[[["
#	flags.each_pair{|k,v| puts  "#{k} => #{v}" }
#	puts "###"
#	puts "###"
  flags.to_a.reject {|k,v| v == "" }.sort {|a,b| @order[a[0]] <=> @order[b[0]]}.map {|k,v| v}.join(" ")
end

def diff(a, b)
  u = [].to_set
  b[:flags].each do |k,v|
    a[:flags][k] = "" if not a[:flags].has_key?(k)
  end
  a[:flags].each do |k,v|
    b[:flags][k] = "" if not b[:flags].has_key?(k)
    if b[:flags][k] != v
      u.add(k) 
    end
  end
  return u
end

def run(flags, prefix = "", original = false)
  @total_runs += 1

  check = original && !@norerun

  comp_str = flags_to_string(flags)
  $stderr.puts "CHECKING #{comp_str}"
  cs_hash = comp_str
  cached_hash = nil
  if @cached.has_key?(cs_hash)
    $stderr.puts "CACHED #{@cached[cs_hash][:file]}"
    $stderr.flush
    cached_hash = @cached[cs_hash][:binary_hash]
    return @cached[cs_hash] if not check
  end

  `mkdir -p "#{@cachedir}"`
  rand_name = prefix + (0...16).map{ ('a'..'z').to_a[rand(26)] }.join

  begin
  runner = TestRunner.new({
     :compile_options => $config.static_params[:prime] + " " + comp_str,
     :generation_num => 0,
     :population_num => 1,
     :run_num => nil,
     :do_profiling => original && @profile != nil,
     :profile_dir => @profile,
     :force_profile_use => @profile != nil && !original,
     :greater_is_better => false,
     :compile_only => true,
     :xml_run_log => "#{@cachedir}/#{rand_name}.xml",
     :reference_run => false,
     :unfailing => true,
     :testboards => 1
   })
  rescue SystemExit => e
  end
  @gcc_runs += 1

  runner.binary_hash = "undef" if runner.binary_hash == nil

  $stderr.puts "XML: #{@cachedir}/#{rand_name}.xml"
  $stderr.puts "BINARY_HASH: #{runner.binary_hash}\n"

  new = {:flags => flags, :binary_hash => runner.binary_hash, :file => "#{@cachedir}/#{rand_name}.xml"}
  @cached[cs_hash] = new

  # @by_hash[runner.hash] = [] if @by_hash[runner.hash] == nil
  # @by_hash[runner.hash].each {|s| diff(s,new).each {|f| @recommended[f] -= 1}}
  # @by_hash[runner.hash].push(new)

  if check and cached_hash != nil and cached_hash != new[:binary_hash]
    $stderr.puts("ERROR: HASH MISMATCH! THE CACHE IS WRONG, please delete it and restart the script")
    exit 1
  end

  return new
end


def reduce(a,b, level1 = true)
  d = diff(a,b).to_a

  fulldist = diff(a,@init_samples[1]).size
  @best = @best < fulldist ? @best : fulldist

  return a if d.size == 0 

  if d.size == 1
    if a[:binary_hash] == b[:binary_hash]
      return b
    else
      @recommended[d[0]] -= 10
      return a
    end
  end

  d.sort! {|a1,b1| @recommended[b1] == @recommended[a1] ? b1 <=> a1 : @recommended[b1] <=> @recommended[a1]}
  flgs_a = a[:flags].clone
  flgs_b = b[:flags].clone
  for i in 0..(d.size > 30 ? ((d.size - 1) / 2) :  0)
    flgs_a[d[i]] = b[:flags][d[i]]
    flgs_b[d[i]] = a[:flags][d[i]]
  end

  $stderr.puts "TRYING TO REDUCE #{diff(a,@init_samples[1]).size} to #{diff(b,@init_samples[1]).size} by checking #{d[0]}"
  $stderr.puts "DIST #{d.size} BEST RESULT: #{@best}/#{@all_flags.size} INIT_HASH: #{@init_samples[0][:binary_hash]}"
  $stderr.flush
  
  c1 = run(flgs_a)
  if c1[:binary_hash] == a[:binary_hash]
    return reduce(c1,b)
  end

  c2 = run(flgs_b)
  if c2[:binary_hash] == a[:binary_hash]
    return reduce(c2,b)
  end

  r1 = reduce(a,c1)
  if r1[:flags] != a[:flags]
    return reduce(r1,b)
  end

  r2 = reduce(a,c2)
  if r2[:flags] != a[:flags]
    return reduce(r2,b)
  end

  return a
end
