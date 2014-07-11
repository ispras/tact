require 'rexml/document'                                                                                                                                                                                           
include REXML

@all_flags = Set.new
@flags_values = Hash.new
@order = Hash.new
@order_n = 0
@order_done = false

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

  @flags_values[r] = [] if not @flags_values.has_key?(r)
  @flags_values[r].push(flag) if @flags_values[r].index(flag) == nil

  if not @order_done or not @order.has_key?(r)
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
  flags.to_a.reject {|k,v| v == ""}.sort {|a,b| @order[a[0]] <=> @order[b[0]]}.map {|k,v| v}.join(" ")
end

def string_to_flags(flags)
  Hash[parse_flags(flags.match(/^(.*)(-O2.*)$/)[2])] #TEMPORARY FIX!!!
end

def samples_from_files(files)
  files.map {|a|
    begin
      XPath.match(Document.new(File.new(a)), "//benchmark_run").map {|r| \
        arr = parse_flags(r.attributes['compile_str'].match(/^(.*)(-O(2|s).*)$/)[2]) #TEMPORARY FIX!!!
        {:flags => Hash[arr], :binary_hash => r.attributes['binary_hash'], :file => a, :arr => arr} \
      } 
    rescue
      []
    end
  }.flatten
end

def samples_from_log(file, addfails=false)
  samp = []
  f = File.new(file, "r")
  while (l = f.gets)
    begin
      if l.match(/^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+'(.+)'\s*$/)
        score = $1
        str = $5.match(/^(.*)(-O2.*)$/)[2]
        arr = parse_flags(str)
        if score.to_f > 0 and score.to_f < 10000
          samp.push({:flags => Hash[arr], :arr => arr, :score => score.to_f, :fail => false})
        elsif addfails
          samp.push({:flags => Hash[arr], :arr => arr, :score => score.to_f, :fail => true })
        end
      end
    rescue
    end
  end
  f.close
  return samp
end

####################################################################################################

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
