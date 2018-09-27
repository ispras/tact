#!/usr/bin/ruby -w

require 'ConfParser.rb'

class Entity
  include Comparable
  attr_accessor :fitness
  attr_accessor :performance_score
  attr_accessor :binary_size
  attr_accessor :binary_hash
  attr_accessor :file_name
  attr_accessor :dist #it's using during reducing to note the distance from otiginal entity
  attr_accessor :strength_value
  attr_accessor :raw_value
  attr_accessor :density_value
  attr_accessor :distances #sorted array of distances from all points 
  attr_accessor :gen_number
  attr_accessor :pop_number
  attr_accessor :run_number
  attr_accessor :options

  remove_method :to_s
  alias old_init initialize
  def initialize(options, string = nil, reducing = false)
    @string_of_options = nil
    @options = []
    (0...options.size).each{ |i|
      @options[i] = options[i].clone
      @options[i].exists = false if reducing
    }
    
    if string != nil then
      if reducing
        @options.each{ |instance|
           (" " + string.split(" ").join(" ")).split(" -").each{ |option|
            if instance.init_from_string("-" + option + " ")
              instance.exists = true
              break
            end
          }
        }
      else
        string.split(" -").each{ |option|
          @options.each{ |instance|
            if instance.init_from_string("-" + option) then
  	      break
	    end
  	  }	
        }
      end
    end

    
    @fitness = -1
    @performance_score = nil
    @binary_size = nil
    @binary_hash = nil
    @file_name = nil
    @dist = nil
    @strength_value = 0
    @raw_value = 0
    @density_value = 0
    @gen_number = 0
    @pop_number = 0
    @run_number = 0
    @distances = []		
  end

  def to_s
    "#{@fitness} : " # FIXME + @options.join(" ")
  end

  def options_string
    string = ""
    @options.each{ |option| string += option.to_s + " " if option.to_s != "" }
    return string
  end

  def mutate(rate)
    @options.each{ |option| if rand() < rate && !option.nil? then option.mutate end}
  end
	
  def init
    @options.each{ |option|
      option.init
    }
  end

  def cross(second_entity)
    new_options = []
    (0...@options.size).each{ |i|
        new_options.push(@options[i].cross(second_entity[i]))
    }
    return new_options    
  end

  def <=>(other)
    #pre = compare(@fitness,other.fitness)
    #return pre if pre != nil
    c = nil
    c = 0 if self == nil && other == nil
    c = 1 if other == nil && c == nil
    c = -1 if self == nil && c == nil
    c = @fitness <=> other.fitness if c == nil
    c
  end
end


