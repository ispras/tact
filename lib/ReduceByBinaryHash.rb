#!/usr/bin/ruby

require 'rexml/document'
require 'set'
require 'TestRunner.rb'
require 'Entity.rb'
include REXML

class Reduce_by_binary_hash

  def initialize(from, config, class_board,first = false)

    @sample_board = config.static_params[:pop_join][class_board][0]
    @boards = config.static_params[:pop_join][class_board]
    @to = "#{$test_dir}/log/current/ref/#{@sample_board}-1.xml"
    @recfile = "#{$test_dir}/log/current/reduce-flags-recommendation"
    @cachedir = "#{$test_dir}/log/current/reduce-flags-cache"
    @prime = config.static_params[:prime]
    @baselines = config.static_params[:baselines]
    @options = config.options
    @all_flags = Set.new
    @best = -1
    @successful_runs = 0
    @total_runs = 0
    @recommended = Hash.new
    @cached = Hash.new
    @config = config
    @from_path = from
    @class_board = class_board
    @to_path = "#{$test_dir}/log/current/ref/#{@sample_board}-1.xml"
    @first = first

    run_reduce_flags    
  end

  def diff(a, b)
    u = [].to_set
    a.options.each{ |option1|
      exist = false
      if option1.exists
        b.options.each{ |option2|
          if option1.name == option2.name
            exist = true if !option2.exists
            break
          end
        }
      end
      u.add(option1.name) if exist
    }
    return u
  end

  def run_reduce_flags
    entities = ([@from_path, @to_path] + Dir.new(@cachedir).entries.reject {|f| [".", ".."].include? f}.map{|f| @cachedir + "/" + f} ).map { |xml|
      begin
        puts "A - #{xml}"
        entity = nil
        xml_doc = Document.new(File.new(xml))
        XPath.each(xml_doc, "//benchmark_run") do |r|
          string = r.attributes['compile_str'].match(/^(#{@prime}|#{@baselines[0]})(.*)$/).to_s
          entity = Entity.new(@options, " " + string, true )
          entity.binary_hash = r.attributes['binary_hash']
          entity.file_name = xml          
        end
        entity
      rescue
        puts "Warning!!! Somthing is incorrect" 
        entity = Entity.new(@options)
      end
    }

    @from = entities[0]
    @to = entities[1]
    @from.options.each { |option|
      @all_flags.add(option.name)
    }
    @best = @all_flags.size
    @all_flags.each {|f| @recommended[f] = f.length }

    if File.exists?(@recfile)
      file = File.new(@recfile, "r")
      while (line = file.gets)
        if line =~ /^([0-9-]+)\s*(.+)\s*$/
          @recommended[$2] = $1.to_i
        end
      end
      file.close
    end

    entities[2..-1].each do |entity|
      next if entity.binary_hash == nil or entity.binary_hash == "" or  entity.binary_hash == "undef"
      string = entity.options_string
      c = @cached[string]
      if c != nil and c.binary_hash != entity.binary_hash  
        $stderr.puts("We have a problem with these files:")
        $stderr.puts("#{c.file_name}")
        $stderr.puts("#{entity.file_name}")
        $stderr.puts("ERROR: THE CACHE IS INCONSISTENT! please delete it and restart the script")
        exit 1
      end
      @cached[string] = entity  
    end

    @from = run_one(@from.options_string, "original-", true)
    @to = run_one(@to.options_string, "reference-")

    
    @start_point = @from
    @start_dist = diff(@start_point, @to).size

    entities[2..-1].each do |cashed_entity|
      if @start_point.binary_hash == cashed_entity.binary_hash
        d = diff(cashed_entity, @to).size
        if d < @start_dist
          @start_dist = d
          @start_point = cashed_entity
        end
      end
    end
  
    if @first
     r = simple_reduce(@start_point, @to)
    else
     r = reduce(@start_point, @to) 
    end

    reduce_flags_file = File.new("#{$test_dir}/log/current/reduce_flags_file", "a")
    reduce_flags_file.puts "\nBEFORE: (#{@from.binary_hash}) #{@from.file_name}"
    reduce_flags_file.puts @from.options_string
    reduce_flags_file.puts "\nAFTER: (#{r.binary_hash}) #{r.file_name}"
    reduce_flags_file.puts r.options_string
    reduce_flags_file.puts "\nSuccessful gcc runs: " + @successful_runs.to_s
    reduce_flags_file.puts "Total runs (including cached): " + @total_runs.to_s
    reduce_flags_file.close
    puts "\nBEFORE: (#{@from.binary_hash}) #{@from.file_name}" 
    puts @from.options_string
    puts "\nAFTER: (#{r.binary_hash}) #{r.file_name}"  
    puts r.options_string

    puts "\nSuccessful gcc runs: " + @successful_runs.to_s  
    puts "Total runs (including cached): " + @total_runs.to_s

    FileUtils.cp(r.file_name, "#{$test_dir}/log/current/best-reduced_#{@class_board}/#{@from_path.split("/")[-1]}")

    if @recfile != nil 
      file = File.new(@recfile, "w")
      @all_flags.each do |k|
        r.options.each{ |option|
          if option.name == k and option.exists == false
            @recommended[k] += 100  
            break
          end
        }
        file.puts("#{@recommended[k]} #{k}")
      end
    end

  end

  def run_one(comp_string, prefix = "", original = false)
    @total_runs += 1

    $stderr.puts "CHECKING #{comp_string}"
    cached_hash = nil
    if @cached.has_key?(comp_string)
      $stderr.puts "CACHED #{@cached[comp_string].file_name}"
      $stderr.flush
      cached_hash = @cached[comp_string].binary_hash
      return @cached[comp_string] if not original and @cached[comp_string].options_string == comp_string 
    end
     
    rand_name = prefix + (0...16).map{ ('a'..'z').to_a[rand(26)] }.join

    begin
    runner = TestRunner.new({
      :compile_options => @prime + " " + comp_string,
      :generation_num => 0,
      :population_num => 1,
      :greater_is_better => @config.runtime_params[:greater_is_better],
      :compile_only => true,
      :xml_run_log => "#{@cachedir}/#{rand_name}.xml", 
      :reference_run => false,
    })
    rescue SystemExit => e
    end      
    @successful_runs += 1
    puts "@successful_runs #{@successful_runs}"
    runner.binary_hash = "undef" if runner.binary_hash == nil    

    $stderr.puts "XML: #{@cachedir}/#{rand_name}.xml"
    $stderr.puts "BINARY_HASH: #{runner.binary_hash}\n"

    new_entity = Entity.new(@options, " " + comp_string, true)
    new_entity.binary_hash = runner.binary_hash
    new_entity.file_name = "#{@cachedir}/#{rand_name}.xml"
    
    @cached[comp_string] = new_entity 

    if original and cached_hash != nil and cached_hash != new_entity.binary_hash
      $stderr.puts("ERROR: HASH MISMATCH! THE CACHE IS WRONG, please delete it and restart the script")
      exit 1
    end

    return new_entity
  end

  def simple_reduce(a,b)
    d = diff(a,b).to_a

    current_best = a.clone
    d.each{ |option|
      puts "Reducing #{option}"
      new_string = remove_option_from_string(current_best.options_string, option)
      entity = run_one(new_string)
      if entity.binary_hash == current_best.binary_hash
        current_best = entity.clone 
      end
      @recommended[option] -= 20
    }
    return current_best
  end

  def reduce(a, b)
    d = diff(a,b).to_a

    d.sort! {|a1,b1| @recommended[b1] == @recommended[a1] ? b1 <=> a1 : @recommended[b1] <=> @recommended[a1]}

    d_size = d.size / 2
    while d_size > 2
      new_string = a.options_string.clone
      d[0..d_size].each{ |option|
        new_string = remove_option_from_string(new_string, option)
      }
      new_entity = run_one(new_string)
      if new_entity.binary_hash == a.binary_hash
        puts "EVERICA #{d_size}"
        return simple_reduce(new_entity, b)
      else
        d_size = d_size / 2
      end
    end 
    return simple_reduce(a,b)   
  end

  def remove_option_from_string(string, option)
    flag = option.clone
    if flag[0] == '-'
     flag[0] = ''
    end 
    string.match(/^(.*)(\s|^)[-](f|fno-|-param|m|mno-|D|)(|\s)#{flag}($|\s|=\d*)(.*)$/)
    a = $1
    b = $6
    a + " " + b
  end


end






























