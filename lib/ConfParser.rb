#!/usr/bin/ruby -w

require File.expand_path(File.dirname(__FILE__)) + '/WorkDirPool.rb'
require 'rexml/document'

class GCC_flag
  attr_reader :name
  attr_accessor :value
  attr_accessor :exists
  attr_accessor :enum_values
  def initialize(name)
    @name = name[2..name.size]
    @value = false
    @exists = true
    @enum_values = nil
    @static_params = ConfParser.new.static_params
  end

  def to_s
    if @exists
      if @value then "-f#{@name}" else "-fno-#{@name}" end
    else
      ""
    end
  end

  def help_name
    return "-f#{name}"
  end

  def mutate
    @value = @value ^ true
  end	

  def init
    @value = rand(2) == 0
  end

  def check_string(string)
    return string[/^(-f|-fno-)#{@name}$/] != nil
  end

  def cross(second_option)
    if rand() < 0.5
      return self
    else
      return second_option
    end
  end

  def init_from_string(string)
    if check_string(string) then
      @value = string[/^-fno-(.*)/] == nil
      return true
    else
     return false
    end
  end
end

class GCC_mflag < GCC_flag
  def to_s
    if @exists
      if @value then "-m#{@name}" else "-mno-#{@name}" end
    else
      ""
    end
  end
  
  def help_name
    return "-m#{name}"
  end

  def check_string(string)
    return string[/^(-m|-mno-)#{@name}$/] != nil
  end  

  def init_from_string(string)
    if check_string(string) then
      @value = string[/^-mno-(.*)/] == nil
      return true
    else    
      return false
    end     
  end     
end		

class GCC_enum < GCC_flag
  attr_accessor :enum_values
  def set_values(values)
    @enum_values = values
  end

  def to_s
    if @exists
      @enum_values[@value]
    else
      "" 
    end
  end

  def help_name
    return @enum_values
  end

  def mutate
    init
  end

  def init
    @value = rand(@enum_values.size)
  end

  def check_string(string)
    return @enum_values.index(string) != nil
  end

  def init_from_string(string)
    if check_string(string) then
      @value = @enum_values.index(string)
      @name = @enum_values[@value]
      return true
    else    
      return false
    end     
  end
end

class GCC_param < GCC_flag
  attr_accessor :default

  def set_constraints(value,min,max,step,separator = '=')
    @default = value
    @value = value
    @min = min
    @max = max
    @step = step
    @separator = separator
    @delta = @max - @min
    if @step == 0
      @step = 1
    end	
  end

  def to_s
    if @exists
      "--param #{@name}#{@separator}#{@value}"
    else
      "" 
    end
  end
  
  def help_name
    return "#{@name}"
  end

  def new_int_param_value(base, range, val_0_1)
    return base + (val_0_1*range/@step + 0.5).to_i * @step
  end

  def fit_value_in_range
    if @value > @max then @value = @max end
    if @value < @min then @value = @min end
  end

  def mutate
    if (@static_params[:mutation_strategy] == "normal_shift")
      # Shift by normally distributed value
      pr = MathP.new.get_rand_normal_distribution(0.5)
      @value += @delta * pr
      @value = @value.to_i
      mod = @value % @step
      @value -= mod
      mod = (mod.to_f / @step.to_f + 0.5).to_i * @step
      @value += mod
    else
      # mutation_strategy == "uniform_replace"
      # default strategy: replace with new uniformly distributed value
      puts "Mutating #{@name}, old value=#{@value}"
      @value = new_int_param_value(@min, @delta, rand)
      puts "\tnew value=#{@value}"
    end
		
    fit_value_in_range
  end

  def init
    if @static_params[:seed_strategy] == "normal"
      # Normal distribution around @default value
      n = 0
      while (@value < @min || @value >@max) && n < 100
        @value = new_int_param_value(@default, @delta, MathP.new.get_rand_normal_distribution(2.0))
        n += 1
      end
      fit_value_in_range
    else
      # Uniform distribution (default)
      @value = new_int_param_value(@min, @delta, rand)
      ##puts "Seed: #{@name}=#{@value}, min=#{@min}, max=#{@max}"
    end
  end

  def check_string(string)
    return string[/^--param #{@name}#{@separator}/] != nil
  end

  def init_from_string(string)
    if check_string(string) then
      @value = string.gsub(/^--param #{@name}#{@separator}/,"").to_i
      return true
    else
      return false
    end
  end
end

class Float_param < GCC_flag
  attr_accessor :default

  def set_constraints(value,min,max,step,separator = '=')
    @default = value
    @value = value
    @min = min
    @max = max
    @step = step
    @separator = separator
    @delta = @max - @min
    if @step == 0
      @step = 1
    end	
  end

  def to_s
    if @exists
      "--#{@name}#{@separator}#{@value}"
    else
      "" 
    end
  end
  
  def help_name
    return "#{@name}"
  end

  def new_param_value(base, range, val_0_1)
    return base + (val_0_1*range/@step + 0.5) * @step
  end

  def fit_value_in_range
    if @value > @max then @value = @max end
    if @value < @min then @value = @min end
  end

  def mutate
    if (@static_params[:mutation_strategy] == "normal_shift")
      # Shift by normally distributed value
      pr = MathP.new.get_rand_normal_distribution(0.5)
      @value += @delta * pr
#@value = @value.to_i
      mod = @value % @step
      @value -= mod
      mod = (mod.to_f / @step.to_f + 0.5) * @step
      @value += mod
    else
      # mutation_strategy == "uniform_replace"
      # default strategy: replace with new uniformly distributed value
      puts "Mutating #{@name}, old value=#{@value}"
      @value = new_param_value(@min, @delta, rand)
      puts "\tnew value=#{@value}"
    end
		
    fit_value_in_range
  end

  def cross(second_option)
    if rand() < 0.5
        super
    else
        new_option = self.clone
        new_option.value = (@value + second_option.value)/2.0
        return new_option
    end
  end

  def init
    if @static_params[:seed_strategy] == "normal"
      # Normal distribution around @default value
      n = 0
      while (@value < @min || @value >@max) && n < 100
        @value = new_param_value(@default, @delta, MathP.new.get_rand_normal_distribution(2.0))
        n += 1
      end
      fit_value_in_range
    else
      # Uniform distribution (default)
      @value = new_param_value(@min, @delta, rand)
      ##puts "Seed: #{@name}=#{@value}, min=#{@min}, max=#{@max}"
    end
  end

  def check_string(string)
    return string[/^--#{@name}#{@separator}/] != nil
  end

  def init_from_string(string)
    if check_string(string) then
      @value = string.gsub(/^--#{@name}#{@separator}/,"").to_f
      return true
    else
      return false
    end
  end
end


class ConfParser
  attr_accessor :path
  # make this class static  
  def self.new
    ObjectSpace.each_object(ConfParser){|o| return o if o.path==get_current_test_dir}
    super
  end
  
  def initialize
    @path = get_current_test_dir
    config_file = "/etc/tuning.conf"
    
    if !File.exist?(@path + config_file) then
      config_file = "/../../../template/tests/template" + config_file
      
      if !File.exist?(@path + config_file) then
        $stderr.puts("Error: tuning.conf not found!")
	exit(2)
      end
      
      $stderr.puts("!!! WARNING !!!: You are using default tuning.conf !!!")
    end
    
    @config_file = path + config_file
    
    @static_params = nil
    @runtime_params = nil
    @options = nil
    parse_params
  end
  
  def static_params
    parse_params if @static_params == nil
    @static_params  
  end
  
  def runtime_params
    parse_params if @runtime_params == nil
    @runtime_params
  end
  
  def options
    parse_params if @runtime_params == nil
    @options
  end
  
  def parse_params
    params_def = { :prime => { :path => "prime", :attr => "flags", :type => "string", :multiple => false, :static => true},
                          :baselines => { :path => "baseline", :attr => "flags", :type => "string", :multiple => true, :static => true},
                          :board_id => { :path => "board_id", :attr => "value", :type => "string", :multiple => false, :static => true},
                          :pop_size => { :path => "population_size", :attr => "value", :type => "int", :multiple => false, :static => true},
                          :single_option_mutation_rate => { :path => "single_option_mutation_rate", :attr => "value", :type => "float", :multiple => false, :static => true},
                          :mutation_strategy => { :path => "single_option_mutation_rate", :attr => "strategy", :type => "string", :multiple => false, :static => true},
                          :mutation_rate => { :path => "mutation_rate", :attr => "value", :type => "float", :multiple => false, :static => true},
                          :crossover_vs_mutation_rate => { :path => "crossover_vs_mutation_rate", :attr => "value", :type => "float", :multiple => false, :static => true},
                          :after_crossover_mutation_rate => { :path => "after_crossover_mutation_rate", :attr => "value", :type => "float", :multiple => false, :static => true},
                          :migration_rate => { :path => "migration_rate", :attr => "value", :type => "float", :multiple => false, :static => true},
                          :archive_size => { :path => "archive_size", :attr => "value", :type => "int", :multiple => false, :static => true},
                          :pareto_best_size => { :path => "pareto_best_size", :attr => "value", :type => "int", :multiple => false, :static => true},
                          :greater_is_better => { :path => "greater_is_better", :attr => "value", :type => "bool", :multiple => false, :static => false},
                          :repetitions => { :path => "repetitions", :attr => "value", :type => "int", :multiple => false, :static => false},
                          :pareto_summary_chart_generation_number => { :path => "pareto_summary_chart_generation_number", 
                                                                       :attr => "value", :type => "int", :multiple => false, :static => true},
                          :num_threads => { :path => "threads_per_testboard", :attr => "value", :type => "int", :multiple => false, :static => true},
                          :do_profiling => { :path => "do_profiling", :attr => "value", :type => "bool", :multiple => false, :static => false},
                          :timeout => { :path => "timeout", :attr => "value", :type => "int", :multiple => false, :static => false},
                          :num_generations => { :path => "num_generations", :attr => "value", :type => "int", :multiple => false, :static => true},
                          :measure => { :path => "measure", :attr => "value", :type => "string", :multiple => false, :static => false},
                          :force_initial => { :path => "force_initial", :attr => "value", :type => "bool", :multiple => false, :static => true},
                          :compiler => { :path => "compiler", :attr => "value", :type => "string", :multiple => false, :static => true},
    }

    @static_params = {}
    @runtime_params = {}
    
    @static_params[:basepath] = get_current_test_dir

    # by default measure by pareto
    @runtime_params[:measure] = "performance"

    # force initial population to have only good options
    @static_params[:force_initial] = true
    
    @root_name = 'config'
    @xmlconf = REXML::Document.new(File.new(@config_file))

    params_def.each {|key,opts|
        if opts[:multiple] then
            values = []
            @xmlconf.elements.each("#{@root_name}/#{opts[:path]}"){
                |e| values.push(e.attributes[opts[:attr]])
            }
            if opts[:type] == "int" then
                values.map {|x| x.to_i }
            end
            if opts[:type] == "float" then
                values.map {|x| x.to_f }
            end
            @static_params[key] = values if opts[:static]
            @runtime_params[key] = values if !opts[:static]
        else
	    value = nil
            @xmlconf.elements.each("#{@root_name}/#{opts[:path]}"){
                |e| value = e.attributes[opts[:attr]]
            }
            value = value.to_i if opts[:type] == "int"
            value = value.to_f if opts[:type] == "float"
            value = value == "true" if opts[:type] == "bool"
            @static_params[key] = value if opts[:static]
            @runtime_params[key] = value if !opts[:static]
        end

    }

    # populations
    populations = []
    populations_join = {} 
    @xmlconf.elements.each("#{@root_name}/populations/join_results"){ |e|
      curr_class_boards = []
      e.elements.each("population"){ |i|
        curr_class_boards.push(i.attributes["board_id"])
        populations.push(i.attributes["board_id"])
      }
      populations_join[e.attributes["name"]] = curr_class_boards
    }

    @static_params[:pop_join] = populations_join
    @static_params[:boards] = populations
    @static_params[:populations] = populations.size
    @static_params[:num_testboards] = populations.uniq.size
    
    # uniform_replace is the default mutation strategy
    @static_params[:mutation_strategy] = @static_params[:mutation_strategy] || "uniform_replace"
    
    # if measured by size - less size is better 
    if @runtime_params[:measure] == "size"
      @runtime_params[:greater_is_better] = false
    end
    
    # ===== options =====
    @options = []
    enums = 0
    @xmlconf.elements.each("#{@root_name}/flags/flag"){
      |e| option = nil
      case e.attributes["type"]
      when "gcc_flag"
        if e.attributes["value"][/^-f(.*)/] != nil then # TODO: review
	  option = GCC_flag.new(e.attributes["value"])
	else
	  option = GCC_mflag.new(e.attributes["value"])
	end
      when "enum"
        option = GCC_enum.new('enum'+enums.to_s)
	enums += 1
	option.set_values(e.attributes["value"].split('|'))
        option.mutate
      when "param"
        option = GCC_param.new(e.attributes["value"][6..-1])
	option.set_constraints(e.attributes["default"].to_i,
	                       e.attributes["min"].to_i,
	                       e.attributes["max"].to_i,
	                       e.attributes["step"].to_i,
	                       e.attributes["separator"])
      when "float_param"
        option = Float_param.new(e.attributes["value"][0..-1])
        option.set_constraints(e.attributes["default"].to_f,
                               e.attributes["min"].to_f,
                               e.attributes["max"].to_f,
                               e.attributes["step"].to_f,
                               e.attributes["separator"])
      end
      if option != nil then 
        @options.push(option)
      end
    }

    # finally - build config exports
    @xmlconf.elements.each("#{@root_name}/build_config") do |e|
      ENV[e.attributes["name"]] = eval(e.attributes["value"])
      @static_params[:build_config] = eval(e.attributes["value"])
    end

  end
end 
