#!/usr/bin/ruby

require 'rexml/document'
require 'set'
require 'thread'
require 'fileutils.rb'
require File.expand_path(File.dirname(__FILE__)) + '/../lib/TestRunner.rb'
require File.expand_path(File.dirname(__FILE__)) + '/TactLogger.rb'
include REXML
include Math

class Reduce_by_score

  def initialize(from, config, class_board)
    @class_board = class_board
    @sample_board = config.static_params[:pop_join][class_board][0]
    @boards = config.static_params[:pop_join][class_board]
    @to_path = "#{$test_dir}/log/current/ref/#{@sample_board}-1.xml"
    @cachedir = "#{$test_dir}/log/current/score-by-flag-runs_#{class_board}"
    @config = config
    @from_path = from
    @options = config.options
    @greater_is_better = config.runtime_params[:greater_is_better]
    @direction = @greater_is_better ? -1 : 1
    @measure = config.runtime_params[:measure]
    @prime = config.static_params[:prime]
    @baselines = config.static_params[:baselines]
    @recommended = Hash.new
    @coefficent = nil
    @reducing_process = Array.new
    @best_entity = nil
    @best_number = 0

    run_reduce_by_score
  end

  def recover_flags(options_array)
    options_string = ""
    options_array.each{ |option|
      flag = nil 
      if option[0] == '-'
        flag = option[0][1..-1]
      else
        flag = option
      end
      @from.options_string.match(/^.*\s-(f|fno-|-param |m|mno-|)#{flag}(=\d*|).*$/)
      options_string += "-#{$1}#{option}#{$2} "
    }
    return options_string        
  end

  def remove_option_from_string(string, option)
    begin
      flag = nil
      if option[0] == '-'
        flag = option[1..-1]
      else
        flag = option
      end 
      string.match(/^(.*)(\s|^)[-](f|fno-|-param|m|mno-|D|)(|\s)#{flag}($|\s|=\d*)(.*)$/)
      a = $1
      b = $6
      a + " " + b
    rescue
      puts "#{option} doesn't exists in #{string}"
      string
    end

  end

  def set_coefficent_of_distance
    if @from.performance_score < @from.binary_size
      @coefficent = (@from.binary_size / @from.performance_score).to_i
    else
      @coefficent = (@from.performance_score / @from.binary_size).to_i    
    end
  end

  def run_reduce_by_score
    entities = ([@from_path, @to_path]).map{ |xml|
      begin
        puts "A - #{xml}"
        entity = nil
        xml_doc = Document.new(File.new(xml))
        XPath.each(xml_doc, "//benchmark_run") do |r|
          string = r.attributes['compile_str'].match(/^(#{@prime}|#{@baselines[0]})(.*)$/)[2]
          entity = Entity.new(@options, string, true )  
          entity.binary_hash = r.attributes['binary_hash']
          entity.file_name = xml
          entity.performance_score = r.attributes['score'] if r.attributes['score'] != nil
          entity.binary_size = r.attributes['binary_size'] if r.attributes['binary_size'] != nil
        end
        entity
      rescue
        puts "Warning!!! Somthing is incorrect"
        return
      end
    }

    @from = entities[0]
    @to = entities[1]

    @from = run_one(@from.options_string, "original-", true)
    @to = run_one(@to.options_string, "reference-")
    
    if !@from.performance_score or !@to.performance_score 
      puts "Reducing for #{@from_path} is stopping"
      return
    end

    if @measure == "pareto" and !@from.binary_size or !@to.binary_size
      puts "Reducing for #{@from_path} is stopping "
      return
    end
    
    set_coefficent_of_distance if @measure == "pareto"

    make_recommended_options_list

    @start_point = @from
    @dist_array = diff(@start_point, @to).to_a

    @dist_array.sort! {|a1,b1| @recommended[a1][0].to_f <=> @recommended[b1][0].to_f}

    size = @dist_array.size / 2
    while size > 1
      start_string = @start_point.options_string.clone
      @dist_array[0...size].each { |option|
       
        start_string = remove_option_from_string(start_string, option)
      }
      puts "new string #{start_string}"
      current_entity = run_one(start_string)
      assign_dist_value(current_entity,@start_point)
      puts "TO score #{@to.performance_score}"
      puts "Start_point score #{@start_point.performance_score}"
      puts "New score #{current_entity.performance_score}"
      if !current_entity.dist
        size = size/2
        next
      end

      if current_entity.dist <= 0 or (@to.performance_score - @start_point.performance_score) / (current_entity.performance_score - @start_point.performance_score) > 10
        @reducing_process.push([diff(@start_point, current_entity).to_a, current_entity.performance_score, current_entity.binary_size])
        @start_point = current_entity
        break
      else
        size = size/2
      end
    end
    
    FileUtils.cp(@start_point.file_name ,"#{$test_dir}/log/current/best-byscore-reduced_#{@class_board}/#{@from_path.split("/")[-1]}")

    @best_entity = @start_point.clone

    reduce(@start_point, @to)

    generate_report

  end

  def generate_report
    @log = TactLogger.new

    if File.exists?("#{$test_dir}/log/current/best-byscore-reduced_#{@class_board}/#{@from_path.split("/")[-1]}.log")
      FileUtils.rm("#{$test_dir}/log/current/best-byscore-reduced_#{@class_board}/#{@from_path.split("/")[-1]}.log")
    end
    @log.set_log("#{$test_dir}/log/current/best-byscore-reduced_#{@class_board}/#{@from_path.split("/")[-1]}.log")

    print_brief_summary("Original options",@from)
    print_brief_summary("Reduced to", @to)
    print_brief_summary("Best options", @best_entity)

    first_report
    second_report
    @log.close_log    
    
  end

  def second_report
    if @measure == "performance"
      @log.puts "Relative score of excluding single option from best:\n"
      @log.puts " Score\t%Best\tFlags diff"

      #@recommended.sort!.reverse#{|a1,b1| @recommended[a1][0] <=> @recommended[b1][0]}
      dist_array = []
      @recommended.each_key{ |key|
        dist_array.push(@recommended[key]) if @recommended[key][0] != nil
      }
      dist_array.sort!#{|a1,b1| dist_array[a1][0] <=> dist_array[b1][0]}
      dist_array.reverse!

      (0...dist_array.size).each { |i|
        best = (1- dist_array[i][1] / @from.performance_score)*100
        option = recover_flags([dist_array[i][3]])
        string = "%5.3f\t%5.3f\t%s\n" % [dist_array[i][1], best, option]
        @log.print "#{string}"
      }
    else
    end
  end

  def first_report
    if @measure == "performance"
      @log.puts " Score\t%Prev\t%Base\t%Best\tFlags diff"
      best_score = @best_entity.performance_score
      reverse_array = @reducing_process.reverse
      base_score =reverse_array[0][1]
      puts "@best_number =#{@best_number}"
      @best_number = reverse_array.size - @best_number - 1
      (0...reverse_array.size).each{ |i|
        score = reverse_array[i][1]
        if i == 0
          options = @prime
          prev = 0.0
          base = 0.0
        else
          options = recover_flags(reverse_array[i-1][0])
          options = options + " " + recover_flags(reverse_array[i][0]) if i == reverse_array.size - 1
          prev = (1.0 - reverse_array[i][1]/reverse_array[i-1][1])*100
          base = (1.0 - reverse_array[i][1]/base_score)*100
        end  
        best = (1.0 - reverse_array[i][1]/best_score)*100
        if i == @best_number
          mark = '*'
        else
          mark = ' '
        end
        string = "%s%.3f\t%5.2f%%\t%5.2f%%\t%5.2f%%\t%s" % [mark, score, prev, base, best, options]
        @log.puts "#{string}"  
      }
    else
    end
    @log.puts "\n"
  end


  def print_brief_summary(desc, entity)

    @log.puts( "#{desc} (#{diff(entity, @to).to_a.size}): #{@prime + " " + entity.options_string} ")
    @log.puts "Performance: #{entity.performance_score}" 
    @log.puts "Binary_size: #{entity.binary_size}\n" if @measure == "pareto"
    @log.puts "           "
  end

  def reduce(a,b)
    d = diff(a, b).to_a

    puts "REDUCING from #{a.options_string} To #{b.options_string}"

    if d.size > 0
      d.sort! {|a1,b1| @recommended[a1][0].to_f <=> @recommended[b1][0].to_f}
      current_entities = []
    
      threads = [] 
      d.each do |flag|
        threads << Thread.new(flag) { |f|
          puts "Trying reduce #{f}"
          current_string = remove_option_from_string(a.options_string, f)
          current_entity = run_one(current_string)
          assign_dist_value(current_entity,a)
          current_entities.push(current_entity) if current_entity.dist
        }
      end

      threads.each{|aThread|
        aThread.join
      }

      if current_entities.empty?
        puts "REDUCE BY SCORE CAN'T BE CONTINUED"
        return
      end
      current_entities.sort! { |a1,b1| a1.dist <=> b1.dist }

      puts "Trying to remove all flags with negative dist"
      new_string = a.options_string.clone
      negative_num = 0
      current_entities.each { |entity|
        if entity.dist < 0 and 
          negative_num += 1
          puts "try remove #{diff(a, entity).to_a}"
          new_string = remove_option_from_string(new_string,diff(a, entity).to_a[0])
        end
      }
      current_best_entity = current_entities[0]
      if negative_num > 1
        new_entity = run_one(new_string)
        assign_dist_value(new_entity,a)
        if new_entity.dist and (new_entity.dist <= 0 or new_entity.dist <= current_best_entity.dist)
          puts "!!!We've found new best reduced set"
          current_best_entity = new_entity
        end
      end
      assign_dist_value(current_best_entity, @best_entity)
      if current_best_entity.dist <= 0
        @reducing_process.push([diff(a,current_best_entity).to_a, current_best_entity.performance_score, current_best_entity.binary_size])
        FileUtils.cp(current_best_entity.file_name ,"#{$test_dir}/log/current/best-byscore-reduced_#{@class_board}/#{@from_path.split("/")[-1]}")
        @best_number = @reducing_process.size - 1
        @best_entity = current_best_entity
      else
        @reducing_process.push([diff(a,current_best_entity).to_a, current_best_entity.performance_score, current_best_entity.binary_size])
      end
        
      puts "WIN SCORE: #{current_best_entity.performance_score} BINARY_SIZE: #{current_best_entity.binary_size} DIST #{current_best_entity.dist}" if current_best_entity != nil
      
      reduce(current_best_entity, b)
      
    end    
  end

  def diff(a, b)
    u = [].to_set
    a.options.each{ |option1|
      exist = false
      if option1.exists
        b.options.each{ |option2|
          if option1.name == option2.name or (option2.class == GCC_enum ? option2.enum_values.include?(option1.name) : false)
            exist = true if !option2.exists
            break
          end
        }
      end
      u.add(option1.name) if exist
    }
    return u
  end

  def make_recommended_options_list
    original_options = @from.options.clone
    original_string = @from.options_string.clone
    threads = []
    original_options.each { |flag|
      threads << Thread.new(flag) { |option| 
        begin
          if option.exists
            puts "Original String  #{original_string}"
            puts "reducing option #{option.name} #{option}"
            current_string = remove_option_from_string(original_string, option.name)
            current_entity = run_one(current_string)
            assign_dist_value(current_entity, @from)
            puts "#{current_entity.performance_score} #{@from.performance_score}"
            @recommended["#{option.name}"] = [current_entity.dist, current_entity.performance_score, current_entity.binary_size, option.name]
            puts current_entity.performance_score
            puts "Current String #{current_string}"        
          end
        rescue
          puts "help! its option #{option.name}"
          @recommended["#{option.name}"] = [(@from.performance_score - @to.performance_score)*100, current_entity.performance_score, current_entity.binary_size]
        end
      }
    }

    threads.each{|aThread|
      aThread.join
    }
    @recommended.each_key{ |option|
      puts "#{option}   dist: #{@recommended[option][0]} score: #{@recommended[option][1]} size: #{@recommended[option][2]} option #{@recommended[option][3]}"
    }
  end

  def assign_dist_value(new_entity, original_entity)
    begin
      if @measure == "pareto"
        sign_coef = 0
        
        new_entity.dist = nil if !new_entity.performance_score or !new_entity.binary_size
        new_entity.dist = nil if !original_entity.performance_score or !original_entity.binary_size
        
        if new_entity.performance_score <= original_entity.performance_score and new_entity.binary_size <= original_entity.binary_size and !@greater_is_better
          sign_coef = -1
        elsif new_entity.performance_score >= original_entity.performance_score and new_entity.binary_size >= original_entity.binary_size and @greater_is_better
          sign_coef = -1
        else      
          sign_coef = 1
        end

        size_diff = original_entity.binary_size - new_entity.binary_size
        perf_diff = original_entity.performance_score - new_entity.performance_score

        if new_entity.binary_size > new_entity.performance_score
          new_entity.dist = sign_coef * Math.sqrt(size_diff**2 + (@coefficent * perf_diff)**2)
        else
          new_entity.dist = sign_coef * Math.sqrt(perf_diff**2 + (@coefficent * size_diff)**2)
        end
      else 
        new_entity.dist = (new_entity.performance_score - original_entity.performance_score) * @direction
      end
    rescue
      puts "Warning!!!!!!!!!!!!!!!!!"
      new_entity.dist = nil
    end
  end

  def run_one(comp_string, prefix = "", original = false)
    
    puts "CHECKING #{comp_string}"
    rand_name = prefix + (0...16).map{ ('a'..'z').to_a[rand(26)] }.join
   
    new_entity = Entity.new(@options, comp_string, true)
    begin
      new_params = @config.runtime_params.clone
      new_params.merge!({
      :compile_options => @prime + " " + comp_string,
      :generation_num => 0,
      :population_num => 1,
      :compile_only => false,
      :xml_run_log => "#{@cachedir}/#{rand_name}.xml", 
      :reference_run => false,
      :board_id => @sample_board
    })
      runner = TestRunner.new(new_params)

      if runner != nil
        new_entity.performance_score = runner.score
        new_entity.binary_size = runner.binary_size
        new_entity.binary_hash = runner.binary_hash
        new_entity.file_name = "#{@cachedir}/#{rand_name}.xml"
      end

    rescue SystemExit => e
      new_entity.performance_score = nil
      new_entity.binary_size = nil 
    end

    puts "XML: #{@cachedir}/#{rand_name}.xml"
    puts "SCORE: #{new_entity.performance_score} BINARY_SIZE: #{new_entity.binary_size}\n"
    
    return new_entity

  end

end
