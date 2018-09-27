#!/usr/bin/ruby -w
# 1) parse configs
# 2) make initial populations
# 3) score it
# 4) kill bad
# 5) mutate/cross

# Ugly ad hoc workaround follows
$migration_archive = nil
$current_generation = 1
$current_board_class = nil

require 'rexml/document'
require 'thread'
$LOAD_PATH.push(File.expand_path(File.dirname(__FILE__)))
require 'TestRunner.rb'
require 'ConfParser.rb'
require 'ParetoChartCreator.rb'
require 'Entity.rb'

$mutex = Mutex.new

include REXML

class MathP
  def get_rand_normal_distribution(sigma)
    sum = 0.0
    (1..12).each{ |i| sum += rand()}
    (sum / 6.0 - 1) * sigma
  end
end


class Population
  attr_accessor :number
  attr_accessor :generation
  attr_accessor :archive
  attr_accessor :board_class

  def initialize(static_params, options, runtime_params)
    @size = static_params[:pop_size] # population size
    @cross_size = @size * static_params[:crossover_vs_mutation_rate]
    @mutate_size = @size - @cross_size
    @single_option_mutation_rate = static_params[:single_option_mutation_rate]
    @after_crossover_mutation_rate = static_params[:after_crossover_mutation_rate]
    @migration_rate = static_params[:migration_rate]
    @basepath = static_params[:basepath] # test dir
    @number = static_params[:number] # population number
    @recover = static_params[:recover]
    @prime = static_params[:prime]
    @num_threads = static_params[:num_threads]
    @entities = []
    @archive = []
    @generation = 1
    @options = options
    @runtime_params = runtime_params
    @force_initial = static_params[:force_initial]
    @greater_is_better = runtime_params[:greater_is_better]
    @measure = runtime_params[:measure]
    @board_id = runtime_params[:board_id]
    @board_class = runtime_params[:board_class]
    @archive_size = @size
    @tuning_process = true
  end

  def mutate
    (0...@mutate_size).each{ |i| 
      entity = Entity.new(@archive[rand(@archive.size)].options)
      entity.mutate(@single_option_mutation_rate)
      @entities.push(entity)
    }
  end

  def cross
    rest_of_archives = []
    (0...$migration_archive.size).each{ |i|
      if i != @number - 1
	rest_of_archives += $migration_archive[i]	
      end		
    }

    (0...@cross_size).each{ |i|
      first_migrated = false
      #choosing of first entity for crossbreeding
      if rand() < @migration_rate and rest_of_archives.size > 1
	first = rand(rest_of_archives.size)
 	first_entity = rest_of_archives[first]
	first_migrated = true
      else
	first = rand(@archive.size)
	first_entity = @archive[first]
      end	
      #choosing of second entity for crossbreeding			
      if rand() < @migration_rate and rest_of_archives.size > 1 
	if first_migrated == true 
          while first == (second = rand(rest_of_archives.size))
	  end
	else
	  second = rand(rest_of_archives.size)
	end
	second_entity = rest_of_archives[second]
     else
	if first_migrated == false  
          while first == (second = rand(@archive.size))
	  end
	else
	  second = rand(@archive.size)
        end
        second_entity = @archive[second]
     end
      
      entity = Entity.new(first_entity.cross(second_entity.options))
      entity.mutate(@after_crossover_mutation_rate)
      @entities.push(entity)
    }
  end

  def init_from_xml
    (0...@size).each{ |i| entity = Entity.new(@options)
      entity.init
      @entities.push(entity)
    }
    estimate
  end

  def init_from_log(from)
    folder = @basepath + "/log/current/runs"
    @generation = from
		
    #extract all scores
    contains = Dir.new(folder).entries
    mask = "res-[0]*" + from.to_s + "-[0]*" + @number.to_s + "-[0-9][0-9][0-9]\.xml"
    		
    contains.each {|filename|
      if filename == filename[/#{mask}/]
        bench_run = Document.new(File.new(folder+"/"+filename))
	string = XPath.first(bench_run, "/benchmark_run").attributes["compile_str"]
	score = XPath.first(bench_run, "/benchmark_run").attributes["score"]
        binary_size = XPath.first(bench_run, "/benchmark_run").attributes["binary_size"]
	if (string != nil) && (score != nil) && (binary_size != nil)
	  string.gsub!(@prime,"")
	  entity = Entity.new(@options, string)
	  entity.performance_score = score.to_f
          entity.binary_size = binary_size.to_f
	  @entities.push(entity)
	end
      end
    }
    (@entities.size...@size).each{ |i| entity = Entity.new(@options)
      entity.init
      @entities.push(entity)
    }

    return from
  end

  def collect_current_best_xmls(archive)
    folder = @basepath + "/log/current/runs"
    contains = Dir.new(folder).entries
    j = 0
    (0...archive.size).each{ |i|
      j += 1
      gen_num = archive[i].gen_number.to_s
      pop_num = archive[i].pop_number.to_s
      run_num = archive[i].run_number.to_s
      mask = "res-[0]*" + gen_num + "-[0]*" + pop_num + "-[0]*" + run_num  + ".xml"
      contains.each { |filename|  
        if filename == filename[/#{mask}/]
          run_system("cp #{folder}/#{filename} #{@basepath}/log/current/best_#{$current_board_class}/#{j}.xml")
        end
      }
    }

  end

  def update_archive
    if @measure == "size"
      @entities.each{ |e| e.fitness = e.binary_size }
    else
      @entities.each{ |e| e.fitness = e.performance_score }
    end

    archive1 = @archive + @entities
   
    archive1.sort! { |a1,b1|
      a = a1.fitness
      b = b1.fitness
      c = nil
      c = 0 if a == nil && b == nil
      c = 1 if a == nil && c == nil
      c = -1 if b == nil && c == nil
      c = b <=> a if @greater_is_better && c == nil
      c = a <=> b if c == nil
      c
    }

    @archive = []
    (0...archive1.size).each{ |i| 
      @archive.push(archive1[i]) if archive1[i].fitness != nil
      break if @archive.size >= @archive_size
    }
    collect_current_best_xmls(@archive[0...5]) if @tuning_process == false

    @entities = []
  end

  def breed
    mutate
    cross
    @generation += 1
    $current_generation = @generation
  end

  def estimate_one(number)
    initial = @generation == 1
    params = @runtime_params.clone
    params[:compile_options] = @prime + @entities[number].options_string
    params[:generation_num] = @generation
    params[:population_num] = @number
    params[:run_num] = number + 1

    value = nil
    binary_size = nil

    begin
      puts "[DEBUG] Now will be estimated entity ##{number + 1}"
      runner = TestRunner.new(params)
      value = runner.score
      binary_size = runner.binary_size
      puts "[DEBUG] Estimated entity ##{number + 1} - #{value}"
      if (initial && @force_initial && value == nil) then
        @entities[number] = Entity.new(@options)
	@entities[number].init
	params[:compile_options] = @prime + @entities[number].options_string
      end
    end until !initial || !@force_initial || value != nil 

    @entities[number].performance_score = value
    @entities[number].binary_size = binary_size
    @entities[number].gen_number = params[:generation_num]
    @entities[number].pop_number = params[:population_num]
    @entities[number].run_number = number + 1
  end

  def estimate
    threads = []
    emutex = Mutex.new
    current = 0
    to = @entities.size
		
    (0...@num_threads).each{ |i| 
      threads << Thread.new(i) { |threadNum|
        puts "[DEBUG] I'm thread #{threadNum} ready to estimate"
        loop do
          myEntity = -1
	  emutex.synchronize do
	    if current >= to then break end
	    myEntity = current
	    current += 1
	  end

          if myEntity == -1 then break end
   
          puts "[DEBUG] I'm thread #{threadNum} and I will estimate #{myEntity}"
	  estimate_one(myEntity)
	#  value = @entities[myEntity].fitness
	  puts "[DEBUG] I'm thread #{threadNum} and I estimated #{myEntity} "
        end
      }
    }
		
    threads.each { |aThread|
      begin
        aThread.join
        #rescue Interrupt => e
        #threads.each { |bThread|
        #bThread.raise(e)
        #}
        #sleep 1
        #raise
      end
    }
    threads = nil
  end

  def to_s
    (0...@archive.size).each{ |i| puts i.to_s + ": " +  @archive[i].to_s}
  end

  def opt
    @options
  end

  def average_fitness
    sum = 0.0
    @archive.each{ |entity| sum += entity.fitness }
    sum / @archive_size
  end
end

class ParetoPopulation < Population
  attr_accessor :archive
  attr_accessor :board_class  
				
  def initialize(static_params, options, runtime_params)
    super(static_params, options, runtime_params)
    @archive_size = static_params[:archive_size]
    @pareto_best_size = static_params[:pareto_best_size]
    @archive = []
    @pareto_best = []
    @tuning_process = true
    @coefficient = 1
  end

  def sort_archive_by_performance(archive_original)
    archive = archive_original.clone			
    archive.sort! { |a1,b1|
      a = a1.performance_score
      b = b1.performance_score
      c = nil
      c = 0 if a == nil && b == nil
      c = 1 if a == nil && c == nil
      c = -1 if b == nil && c == nil
      c = b <=> a if @greater_is_better && c == nil
      c = a <=> b if c == nil
      c
    }

    return archive
  end

  def create_archive_log(archive)
    if @tuning_process
      if !File::directory?("#{@log_dir}/archives/") then
        Dir::mkdir("#{@log_dir}/archives/")
      end
      @archive_folder = "#{@log_dir}/archives/generation#{@generation}_#{@number}"
      @pareto_front_folder = "#{@log_dir}/archives/generation#{@generation}_#{@number}/Pareto-front"
      @pareto_best_front_folder = "#{@log_dir}/archives/generation#{@generation}_#{@number}/Pareto-best-front"
    else
      if !File::directory?( "#{@log_dir}/joint_archives_#{$current_board_class}") then
        Dir::mkdir("#{@log_dir}/joint_archives_#{$current_board_class}")
      end
      @archive_folder = "#{@log_dir}/joint_archives_#{$current_board_class}/generation_#{$current_generation}"
      @pareto_front_folder = "#{@log_dir}/joint_archives_#{$current_board_class}/generation_#{$current_generation}/Pareto-front"
      @pareto_best_front_folder = "#{@log_dir}/joint_archives_#{$current_board_class}/generation_#{$current_generation}/Pareto-best-front"
    end	
    
    if !File::directory?( @archive_folder) then
      Dir::mkdir(@archive_folder)
      Dir::mkdir(@pareto_front_folder)
      Dir::mkdir(@pareto_best_front_folder)
    end
    
    archive_log=File.new("#{@archive_folder}/archive.log", "w")
    pareto_log=File.new("#{@archive_folder}/pareto.log", "w")
    pareto_best_log=File.new("#{@archive_folder}/pareto-best.log", "w")
  					
    #archive_log.puts("generation #{@generation}\tpopulation #{@number}")       
    j = 1
    k = 1
    (0...archive.size).each{ |i|
      score = archive[i].performance_score
      size = archive[i].binary_size
      fitness = archive[i].fitness
      options = archive[i].options.join(" ")
      archive_log.puts("#{score}\t#{size}\t#{fitness}\t'#{options}'")
      if fitness < 1
        pareto_log.puts("#{j}) #{score}\t#{size}\t#{fitness}\t'#{options}'")
        if @pareto_best.include?(archive[i])
          pareto_best_log.puts("#{k}) #{score}\t#{size}\t#{fitness}\t'#{options}'")
          k += 1
        end
	j += 1
      end			
    }
    archive_log.close
    pareto_log.close
    pareto_best_log.close
  end

  def collect_pareto_front_xmls(archive)
    folder = @basepath + "/log/current/runs"
    contains = Dir.new(folder).entries

    j = 0
    k = 0
    (0...archive.size).each{ |i|
      if archive[i].fitness < 1 then
        j += 1
 	gen_num = archive[i].gen_number.to_s
	pop_num = archive[i].pop_number.to_s
	run_num = archive[i].run_number.to_s
   	mask = "res-[0]*" + gen_num + "-[0]*" + pop_num + "-[0]*" + run_num  + ".xml"
    	contains.each { |filename|
      	  if filename == filename[/#{mask}/]
      	    run_system("cp #{folder}/#{filename} #{@pareto_front_folder}/#{j}.xml")
            if @pareto_best.include?(archive[i])
              k += 1
              run_system("cp #{folder}/#{filename} #{@pareto_best_front_folder}/#{k}.xml")  
            end
      	  end
   	}
      end     
    }
  end

  def compare_score(first, second, equality)
    return false if first.performance_score == nil
    return true if second.performance_score == nil
   
    if equality then
      return (first.performance_score.to_f <= second.performance_score.to_f) != @greater_is_better
    else
      return (first.performance_score.to_f < second.performance_score.to_f) != @greater_is_better
    end
  end

  def compare_size(first, second, equality)
    return false if first.binary_size == nil
    return true if second.binary_size == nil
  
    if equality then
      return first.binary_size.to_i <= second.binary_size.to_i
    else    
      return first.binary_size.to_i < second.binary_size.to_i
    end     
  end 

  def pareto_dominant(first, second)
    compare_score(first, second, false) and compare_size(first, second, true) or 
	  (compare_score(first, second, true) and compare_size(first, second, false))
  end

  def set_coefficient_of_comparability(entities_set)
    #compute max(the worst) performance_score between @entities and @archive  
    
    max_perf = min_perf = entities_set[0].performance_score.to_f
    max_size = min_size = entities_set[0].binary_size.to_i     
    (entities_set).each{ |i|
      if i.performance_score.to_f < min_perf.to_f
        min_perf = i.performance_score
      end
       
      if i.binary_size.to_i < min_size.to_i
        min_size = i.binary_size
      end
			
      if i.performance_score.to_f > max_perf.to_f
        max_perf = i.performance_score
      end

      if i.binary_size.to_i > max_size.to_i
        max_size = i.binary_size
      end
    }

    size_diff = (max_size - min_size)
    performance_diff = (max_perf - min_perf)
    if size_diff > performance_diff
      @coefficient = size_diff / performance_diff
      return true
    else
      if size_diff.to_i == 0
        @coefficient = 1
      else	
        @coefficient =  performance_diff / size_diff
      end
      return false
    end
  end

  def set_distances_between_entities
    size_is_greater = set_coefficient_of_comparability(@entities + @archive)
    (@entities + @archive).each{ |i|
      array = []
      (@entities + @archive).each{ |j|
        array.push(euclidean_distance(i, j, size_is_greater))
      }
      i.distances = array.sort
    }		
  end
	
  def set_density_values
    @entities.delete_if { |x| x.performance_score == nil or x.binary_size == nil }

    set_distances_between_entities
    k = Math.sqrt(@entities.size + @archive.size)
    (@entities + @archive).each{ |i|
      dens = 0  
      (0...k.to_i).each{ |j|
        dens += i.distances[j]
      }
      dens /= k.to_i
      i.density_value = 1.0 / ( dens + 2) 
    }
  end

  def set_strength_values
    (@entities + @archive).each{ |i|
      i.strength_value = 0    
      (@entities + @archive).each{ |j|
        if pareto_dominant(i, j) then
          i.strength_value += 1
        end
      }
    }
  end
 
  def set_raw_values
    set_strength_values
      
    (@entities + @archive).each{ |i|
      i.raw_value = 0
      (@entities + @archive).each { |j|
        if pareto_dominant(j, i) then
          i.raw_value += j.strength_value 
        end
      }
    }
  end
 
  def set_fitness
    @log_dir = @basepath + "/log/current"

    set_raw_values
    set_density_values
                
    (@entities + @archive).each{ |entity|
      entity.fitness = entity.raw_value + entity.density_value
    }
  end

  def euclidean_distance(entity1, entity2, size_is_greater)
    return 0 if @coefficient.to_f.nan?
    perf_diff = (entity1.performance_score - entity2.performance_score).abs
    size_diff = (entity1.binary_size - entity2.binary_size).abs
    if size_is_greater
      dist = Math.sqrt((@coefficient*perf_diff)**2 + size_diff**2).to_i
    else
      dist = Math.sqrt(perf_diff**2 + (@coefficient*size_diff)**2).to_i
    end

    return dist
  end
 
  def euclidean_distance1(entity, pair, size_is_greater)
    return 0 if @coefficient.to_f.nan?
    perf_diff = (entity.performance_score - pair[0]).abs
    size_diff = (entity.binary_size - pair[1]).abs
    if size_is_greater
      dist = Math.sqrt((@coefficient*perf_diff)**2 + size_diff**2).to_i
    else
      dist = Math.sqrt(perf_diff**2 + (@coefficient*size_diff)**2).to_i
    end

    return dist
  end

  def archive_clustering(archive)
  # using k-means clustering method
    pareto_set = []
    archive.each{ |entity|
      if entity.fitness < 1
        pareto_set.push(entity)
      end
    }
    
    size = pareto_set.size
    if size <= @pareto_best_size
      @pareto_best = pareto_set
    else
      @centers = []
      initial_set = []
      #randomly select centers from pareto_set

      j = 0
      while initial_set.size < @pareto_best_size and j < size
        if !initial_set.include?(pareto_set[i=rand(size)])
          initial_set.push(pareto_set[i])
          @centers.push([pareto_set[i].performance_score, pareto_set[i].binary_size])  
        end
        j += 1
      end
  
      size_is_greater = set_coefficient_of_comparability(pareto_set)

      #main step of algorithm
      iteration = 1
      temp_centers = []
      clusters = {}
      while (@centers - temp_centers != []) and iteration < 30
        #inilializing clusters  
        clusters = {}
        @centers.each{ |center|
          clusters[center] = []
        }
        (0...size).each{ |i|
          min_distance = [euclidean_distance1(pareto_set[i], @centers[0], size_is_greater), @centers[0]]
          @centers.each{ |center|
            if (dist = euclidean_distance1(pareto_set[i], center, size_is_greater)) < min_distance[0]
              min_distance = [dist, center]
            end
          }
          clusters[min_distance[1]].push(pareto_set[i])
        }
      
        #updating the center of cluster
        temp_centers = @centers.clone
        @centers = []
        clusters.each{ |cluster|
          center = [0, 0]
          cluster[1].each{ |entity|
            center[0] += entity.performance_score
            center[1] += entity.binary_size       
          }
          center[0] /= cluster[1].size if cluster[1].size > 0
          center[1] /= cluster[1].size if cluster[1].size > 0
          @centers.push(center)
        }
        iteration += 1
      end

      @pareto_best = []
      clusters.each{ |cluster|
        min_distance = [euclidean_distance1(cluster[1][0], cluster[0], size_is_greater), cluster[1][0]]
        cluster[1].each { |entity|
          if (dist = euclidean_distance1(entity, cluster[0], size_is_greater)) < min_distance[0]
            min_distance = [dist, entity]
          end
        }  
        @pareto_best.push(min_distance[1])
      }
    end
  end

  def update_archive(by_pareto = true)
    if by_pareto == false
      super()
      return
    end
    
    set_fitness

    archive1 = []
    temp_array = (@entities + @archive).sort
    
    temp_array[0...@archive_size].each { |entity|
      if entity.fitness < 1 then
        ok = true
        archive1.each { |entity1|
          if entity.options == entity1.options then
            ok = false
            break
          end             
        }
        archive1.push(entity) if ok
      end
    }
    if archive1.size < @archive_size then
      from = archive1.size
      temp_array[from...temp_array.size].each { |entity|
        ok = true
        archive1.each{ |entity1|
          if entity.options == entity1.options then
            ok = false
	    break
          end
        }
        archive1.push(entity) if ok
        break if archive1.size >= @archive_size
      }
    end

    @archive = archive1
    @entities = []
 
    archive_clustering(@archive)

    archive = sort_archive_by_performance(@archive)
    create_archive_log(archive)
    collect_pareto_front_xmls(archive)
		
    # Create Pareto-chart
    create_chart(@archive_folder, @board_id)
  end
end

class ParetoPopulationJoint < ParetoPopulation
  def initialize(archive_joint)
    conf = ConfParser.new
       
    @entities = archive_joint
    @archive = []
    @pareto_best = []
    @pareto_best_size = conf.static_params[:pareto_best_size]
    @archive_size = conf.static_params[:archive_size] 
    @tuning_process = false
    @greater_is_better = conf.runtime_params[:greater_is_better]
    @basepath = conf.static_params[:basepath]
    @measure = conf.runtime_params[:measure]
  end
end				

class Generation
  attr_accessor :runtime_params
  attr_accessor :static_params

  def initialize(first = 0)
    @recover = first != 0
    @first = 1 if !@recover
   		
    @config_file = "/etc/tuning.conf"
    @basepath = get_current_test_dir
  
    if !File.exist?(@basepath + @config_file) then
      @config_file = "/../../../template/tests/template" + @config_file
      if !File.exist?(@basepath + @config_file) then
        $stderr.puts("Error: tuning.conf not found!")
	exit(2)
      end
      $stderr.puts("!!! WARNING !!!: You are using default tuning.conf !!!")
    end

    @conf = ConfParser.new
    @static_params = @conf.static_params
    @runtime_params = @conf.runtime_params
    @runtime_params[:compile_only] = false
    @runtime_params[:xml_run_log] = nil
    @runtime_params[:reference_run] = false
    @runtime_params[:assembly] = false
    @runtime_params[:oprofile] = false
    @runtime_params[:oprofile_cpu_cycles] = 5000
    
    @options = @conf.options
    @measure = @runtime_params[:measure]   

    @first = first.to_i
  end

  def init_one_population(runtime_params, generation,number)
    static_params = @static_params.clone
    static_params[:number] = number
 
    if runtime_params[:measure] == "pareto"
      population = ParetoPopulation.new(static_params, @options, runtime_params)
    else
      population = Population.new(static_params, @options, runtime_params)
    end

    if @recover then
      puts "[Debug] Recover population #{number}"
      population.init_from_log(generation)
    else
      puts "[Debug] Init from xml for population #{number}"
      population.init_from_xml
    end

    return population
  end

  def init_populations
    @populations = []

    population_boards = @static_params[:pop_join]

    threads = []
    current_pop = 0
    popmutex = Mutex.new

    population_boards.each_key{ |class_board|
      threads << Thread.new(class_board) { |current_class|
        puts "[Debug] I'm thread #{current_pop} ready to initialize populations"
        inner_threads = []
        population_boards[current_class].each{ |board_id|
          inner_threads << Thread.new(board_id) { |id|
            runtime_params = @runtime_params.clone
            runtime_params[:board_id] = id
            runtime_params[:board_class] = current_class 
            curr_pop = 0
            popmutex.synchronize do
              if current_pop > @static_params[:populations] then break end
              curr_pop = current_pop
              current_pop += 1 
            end
            @populations.push(init_one_population(runtime_params, @first, curr_pop + 1))        
          }
        }
        inner_threads.each { |aThread|
          aThread.join 
        }
      }
    }
    threads.each { |aThread|
      aThread.join
    }

      @populations.sort! { |a,b|
        a.number <=> b.number
      }
  end

  def run_one_population(population_number)
    num = population_number + 1
    puts "[Debug] Started population #{num} of #{@static_params[:populations]} on #{num % @static_params[:num_testboards]}"
    population = @populations[population_number]
    population.breed
    population.estimate
    population.update_archive
    puts "[Statistic] Generation #{population.generation} population #{num}"
    puts "----------------------------------------"
    puts population
    puts "----------------------------------------"
    printf("[Statistic] Average fitness: %.5f\n\n", population.average_fitness)
  end

  def run
    init_populations
    (0...@static_params[:populations]).each{ |i| 
      @populations[i].update_archive
    }

    join_population_best_results_for_each_board_class

    @first = 2 if @first == 0
   
    build_log = "#{@basepath}/log/current/build.log"

    (@first..@static_params[:num_generations]).each{ |i|
      update_migration_archive
      puts "[Debug] Started generation ##{i+1}"
      threads = []
      (0...@static_params[:populations]).each{ |j|  
        threads << Thread.new(j) { |pop|
          run_one_population(pop)
        }      
      }
      threads.each { |aThread|
        aThread.join
      }
      run_system("cp -f #{build_log} #{build_log}.old")
      run_system("echo 'Build log for generation #{i} in build.log.old' > #{build_log}")
      join_population_best_results_for_each_board_class      
    }

  end

  def get_current_test_dir
    test_dir=Dir.getwd
    # TODO: assert that we're running within test directory
    if (test_dir[/^\/.+\/tests\/([^\/]+)$/] == nil)
      $stderr.puts "[Debug] This script should be run from one of the 'tests/*' subdirectories."
      exit 1
    end
    return test_dir
  end

  def join_population_best_results_for_each_board_class
    @static_params[:pop_join].each_key{ |board_class_i| 
      
      $current_board_class = board_class_i
      archive_joint = []
      (0...@static_params[:populations]).each{ |pop|
        if @populations[pop].board_class == board_class_i then
          archive_joint = archive_joint + @populations[pop].archive
        end
      }

      log_dir = @basepath + "/log/current"
      if !File::directory?("#{log_dir}/best_#{board_class_i}") then
        Dir::mkdir("#{log_dir}/best_#{board_class_i}")
      end
      #run_system("rm #{log_dir}/best_#{board_class_i}/*.xml")

      population = ParetoPopulationJoint.new(archive_joint)
      if @measure == "pareto"
        population.update_archive
      else
        population.update_archive(false)
      end 
      
      run_system("rm #{log_dir}/best_#{board_class_i}/*.xml") if @measure == "pareto"
      run_system("cp #{log_dir}/joint_archives_#{board_class_i}/generation_#{$current_generation}/Pareto-best-front/*.xml #{log_dir}/best_#{board_class_i}") if @measure == "pareto"

    }
  end

  def update_migration_archive
    migration_archive = []
    (0...@static_params[:populations]).each{ |number|			
      population = @populations[number]
      temp_archive = population.archive.clone
      if @measure == "pareto"
        pareto_front = []
	(0...temp_archive.size).each{ |i|
	  if temp_archive[i].fitness < 1
	    pareto_front.push(temp_archive[i])		
	  end
	}
        migration_archive[number] = pareto_front
      else
        migration_archive[number] = temp_archive		
      end
    }
    $migration_archive = migration_archive.clone	
  end
end



