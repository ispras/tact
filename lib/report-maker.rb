#!/usr/bin/ruby

#gem install fast_xs
#gem install rubyzip

require 'rexml/document'
#include REXML

#require 'rubygems'
require File.expand_path(File.dirname(__FILE__)) + '/simple_xlsx.rb'
require File.expand_path(File.dirname(__FILE__)) + '/ConfParser.rb'

=begin
board_class = ARGV[1]
board = ARGV[2]
reduce = ARGV[3]
measure = ConfParser.new.runtime_params[:measure]
if measure == "pareto"
  log_dir = ARGV[0] 
  num_generations = Dir.new("#{log_dir}/joint_archives_#{board_class}").entries.delete_if{|i| i[/^generation.*$/] == nil}.size 
  archive_dir = "#{log_dir}/joint_archives_#{board_class}/generation_#{num_generations}" 
else
  best_dir = ARGV[0]
  log_dir = File.dirname(best_dir)
end
=end

reduce = ARGV[1]
best_dir = ARGV[0]
board_class = File.basename(best_dir).gsub(/^best_/,'')
config = ConfParser.new
board = config.static_params[:pop_join][board_class][0]
measure = config.runtime_params[:measure]
log_dir = File.dirname(best_dir)

def column_char n 
    i = 0
    m = n % 26
    while  n / 26 !=  0
      i+= 1
      m = n % 26
      n -= 26
    end
          
    return (i == 0) ? (m + 65).chr : (i + 64).chr + (m + 65).chr  
end

def compute_mean_formula(row_from, col_num, isgeom, weighted, weights_array)
  row_to = row_from + weights_array.size
  formula = "="
  if isgeom
    formula += "POWER(1.00"
    if weighted
      (1..weights_array.size).each { |cell|
        formula += "*POWER(#{column_char(col_num)}#{row_from + cell},#{weights_array[cell - 1]})"        
      }
      formula += ",#{1.to_f / weights_array.size})"
    else
      (1..weights_array.size).each { |cell|
        formula += "*#{column_char(col_num)}#{row_from + cell}"
      }
      formula += ",#{1.to_f / weights_array.size})"
    end
  else
    if weighted
      formula += "(0+"
      (1..weights_array.size).each { |cell|
        formula += "+#{column_char(col_num)}#{row_from + cell}*#{weights_array[cell - 1]}"
      }
      formula += ")/#{weights_array.size}"
    else
      formula += "SUM(#{column_char(col_num)}#{row_from}:#{column_char(col_num)}#{row_to})"
      formula += "/#{weights_array.size}"
    end
  end
  return formula
end

def test_description(test_descr_dir)
  $weights_array = Array.new
  test_descr = REXML::Document.new(File.new(test_descr_dir))
  REXML::XPath.each(test_descr, "//test") do |test|
    $weights_array.push(test.attributes["weight"])
  end

  case REXML::XPath.first(test_descr, "//benchmark_description").attributes['summary_method']
    when "geomean"
      $weighted = false
      $isgeom = true
      $size = false
    when "weighted_geomean"
      $weighted = true
      $isgeom = true
      $size = false
    when "mean"
      $weighted = false
      $isgeom = false
      $size = false
    when "weighted_mean"
      $weighted = true
      $isgeom = false
      $size = false
    when "size"
      $size = true
      $weighted = false
      $isgeom = false
    end
      
    case REXML::XPath.first(test_descr, "//benchmark_description").attributes['greater_is_better']
    when "true"
      $isbiggerbetter = true
    when "false"
      $isbiggerbetter = false
    end
end
=begin
def add_size_table($row_array, $row_index, xml_dir)
    
  $row_array[$row_index - 1] = Array.new
  $row_array[$row_index] = Array.new
  $row_array[$row_index + 1] = Array.new
  $row_array[$row_index][0] = "BINARY_SIZE"
  $row_array[$row_index + 1][0] = ""
   
  first_baseline = true
  xml_dir.each { |filename|
    
    if ref_dir.include?(filename)
      xml_name = REXML::Document.new(File.new("#{log_dir}/ref/#{filename}"))
    else
      xml_name = REXML::Document.new(File.new("#{best_dir}/#{filename}"))
    end

    compile_str = REXML::XPath.first(xml_name, "/benchmark_run").attributes["compile_str"]
    binary_size = REXML::XPath.first(xml_name, "/benchmark_run").attributes["binary_size"]

    $row_array[$row_index].push(compile_str)
    $row_array[$row_index + 1].push(binary_size)
    if first_baseline == false
      $row_array[$row_index].push("Delta %")
      $row_array[$row_index + 1].push("=(1 - #{column_char(row_array[$row_index + 1].size - 1)}#{$row_index + 2}/B#{$row_index + 2})*100")
    end
    first_baseline = false   
  }

end
=end
if File.exists?("#{log_dir}/reports/results_#{board_class}.xlsx")
  system("rm #{log_dir}/reports/results_#{board_class}.xlsx")
end
SimpleXlsx::Serializer.new("#{log_dir}/reports/results_#{board_class}.xlsx") do |doc|
  doc.add_sheet("Results") do |sheet|

    $row_array = Array.new
    $row_index = 0
    best_xml_dir = Dir.new("#{best_dir}").entries.delete_if{ |i| i[/^.*\.xml$/] == nil}.sort

    ref_dir = Dir.new("#{log_dir}/ref").entries.delete_if{ |i| i[/^#{board}.*\.xml$/] == nil}
    ref_dir_base = Dir.new("#{log_dir}/ref").entries.delete_if{ |i| i[/^#{board}.*1\.xml$/] == nil}
    ref_dir_others = ref_dir - ref_dir_base

    $row_array[$row_index] = Array.new
    $row_array[$row_index].push("PERFORMANCE") 

    #test_descr.xml
    test_description("#{log_dir}/etc/test-descr.xml")
         
    #ComparItion by performance
    index = 0 #current row index
    first_test_xml = true #true if the first test xml file in considered
    xml_dir = ref_dir_base + ref_dir_others + best_xml_dir

    xml_dir.each { |filename|

      if ref_dir.include?(filename)
        xml_name = REXML::Document.new(File.new("#{log_dir}/ref/#{filename}"))
      else
        xml_name = REXML::Document.new(File.new("#{best_dir}/#{filename}"))
      end
      compile_str = REXML::XPath.first(xml_name, "/benchmark_run").attributes["compile_str"]
      repetitions = REXML::XPath.first(xml_name, "/benchmark_run").attributes["repetitions"]
      result = REXML::XPath.first(xml_name, "/benchmark_run").attributes["result"]
        
      if first_test_xml
        $row_array[$row_index].push(compile_str)
        $row_index += 1
      else
        next_xml_column = $row_array[$row_index - 1].size 
        $row_array[$row_index - 1][next_xml_column] = compile_str
      end
       
      index = $row_index
      REXML::XPath.each(xml_name, "//test") do |test|
        if first_test_xml
          $row_array[index] = Array.new
          name = test.attributes["name"]
          $row_array[index].push(name)
        end

        REXML::XPath.each(test, "run") do |run|
          run_value = run.attributes["value"]

          if result == "OK" 
            $row_array[index].push(run_value.to_f)
          else
            $row_array[index].push("error_run")
          end
        end
        median_from = $row_array[index].size - repetitions.to_i
        median_to = $row_array[index].size - 1
        $row_array[index].push("=MEDIAN(#{column_char(median_from)}#{index + 1}:#{column_char(median_to)}#{index + 1})")
        index += 1
      end

      $row_array[$row_index - 1][$row_array[index - 1].size - 1] = "Median"
        
      #Compute Mean
      if first_test_xml
        mean_row = $row_array[index] = Array.new
        mean_row.push("Mean")
      end
      current_size = $row_array[index - 1].size
      ((current_size - repetitions.to_i - 1)...current_size).each { |col|
        $row_array[index].push(compute_mean_formula($row_index, col , $isgeom, $weighted, $weights_array))
      }
       
      #Compute delta 
      if first_test_xml == false
        $row_array[$row_index - 1][$row_array[index - 1].size] = "Delta %"
        if $isbiggerbetter == true 
          minus = ""
        else
          minus = "-"
        end
        ($row_index..index).each{ |row|
          $row_array[row].push("=(#{column_char($row_array[row].size - 1)}#{row + 1}/#{column_char(repetitions.to_i + 1)}#{row + 1} - 1)*(#{minus}100)") 
        }
      end

      first_test_xml = false
    }
    $row_index = index + 2

    if measure == "pareto"
     
      #comparition by size
      $row_array[$row_index - 1] = Array.new
      $row_array[$row_index] = Array.new
      $row_array[$row_index + 1] = Array.new
      $row_array[$row_index][0] = "BINARY_SIZE"
      $row_array[$row_index + 1][0] = ""
   
      first_baseline = true
      xml_dir.each { |filename|
      
        if ref_dir.include?(filename)
          xml_name = REXML::Document.new(File.new("#{log_dir}/ref/#{filename}"))
        else
          xml_name = REXML::Document.new(File.new("#{best_dir}/#{filename}"))
        end

        compile_str = REXML::XPath.first(xml_name, "/benchmark_run").attributes["compile_str"]
        binary_size = REXML::XPath.first(xml_name, "/benchmark_run").attributes["binary_size"]

        $row_array[$row_index].push(compile_str)
        $row_array[$row_index + 1].push(binary_size)
        if first_baseline == false
          $row_array[$row_index].push("Delta %")
          $row_array[$row_index + 1].push("=(1 - #{column_char($row_array[$row_index + 1].size - 1)}#{$row_index + 2}/B#{$row_index + 2})*100")
        end
        first_baseline = false   
      }
    
      $row_index = $row_array.size  
      $row_array[$row_index] = Array.new

      num_generations = Dir.new("#{log_dir}/joint_archives_#{board_class}").entries.delete_if{|i| i[/^generation.*$/] == nil}.size 
      archive_dir = "#{log_dir}/joint_archives_#{board_class}/generation_#{num_generations}"
      pareto_front_file = File.open("#{archive_dir}/pareto.log", 'r')
   
      $row_array[$row_index + 1] = Array.new
      $row_array[$row_index + 1][1] = "Binary_size"
      $row_array[$row_index + 1][2] = "Performance"
      $row_array[$row_index + 1][3] = "Best tuned binary_size for perf. of this opt level"
      $row_array[$row_index + 1][4] = "Reduction in binary size, %"
      $row_array[$row_index + 1][5] = "Number in Pareto-Front"
      $row_array[$row_index + 1][6] = "Best tuned performance for size of this opt level"
      $row_array[$row_index + 1][7] = "Performance gain, %"
      $row_array[$row_index + 1][8] = "Number in Pareto-Front"

      index = $row_index + 2
      performances = []
      binary_sizes = []
      pareto_front_file.each do |line|
        performances.push(line.split[1])
        binary_sizes.push(line.split[2])
      end

      ref_dat_dir = Dir.new("#{log_dir}/ref").entries.delete_if{ |i| i[/^#{board}.*\.dat$/] == nil}.sort
      ref_dat_dir.each { |ref|
        current_row = $row_array[index] = Array.new

        ref_dat_file = File.open("#{log_dir}/ref/#{ref}","r") 
        dat_lines = ref_dat_file.to_a
      
        flags = dat_lines[0].split(/"/)[3]
        ref_size = dat_lines[1].split[1]
        ref_perf = dat_lines[1].split[0]

        satisfied_perfotmance = 0
        satisfied_size = 0
        pareto_number_size = 0
        pareto_number_perf = 0
        (0...binary_sizes.size).each { |size|
          if ref_size < binary_sizes[-1]
            satisfied_perfotmance = "--"
            break
          end
          satisfied_perfotmance = performances[size]
          pareto_number_perf = size + 1
          if binary_sizes[size].to_i <= ref_size.to_i 
            break
          end 
        }

        (0...performances.size).each { |perf|
          if ref_perf < performances[0]
            satisfied_size = "--"
            break
          end
          if performances[perf].to_f >= ref_perf.to_f
            break
	  end
	  satisfied_size = binary_sizes[perf]
          pareto_number_size = perf + 1
        }

        if satisfied_perfotmance == "--"
          percent_performance = "--"
          pareto_number_perf = "--"
        else
          if $isbiggerbetter == true
            minus = "-"
          else
            minus = ""
          end
          percent_performance = "=(1-G#{index + 1}/C#{index + 1})*(#{minus}100)"
        end
        if satisfied_size == "--"
          pareto_number_size = "--"
          precent_size = "--"
        else
          percent_size = "=(1 - D#{index + 1}/B#{index + 1}) * 100"
        end

        current_row.push(flags)
        current_row.push(ref_size)
        current_row.push(ref_perf)
        current_row.push(satisfied_size)
        current_row.push(percent_size)
        current_row.push(pareto_number_size)
        current_row.push(satisfied_perfotmance)
        current_row.push(percent_performance)
        current_row.push(pareto_number_perf)

        index += 1
      }

      pareto_front_file.close
      pareto_front_file = File.open("#{archive_dir}/pareto.log", 'r')
      $row_index = $row_array.size
      $row_array[$row_index] = Array.new

      index = $row_index + 1
      pareto_front_file.each do |line|
        $row_array[index] = Array.new
        line_array = line.split
      
        $row_array[index].push(line_array[0])
        $row_array[index].push(line_array[2])
        $row_array[index].push(line_array[1])
        $row_array[index].push(line_array[4...line_array.size].join(" "))
        index += 1
      end
      pareto_front_file.close

      #after reducing
      if reduce == "reduce-flags" or reduce == "reduce-by-score"

        $row_index = $row_array.size
        $row_array[$row_index] = Array.new
        $row_array[$row_index + 1] = Array.new
        $row_array[$row_index + 1][0] = "Clustered Pareto-front after Reduce-flags"

        best_reduced_dir = "#{log_dir}/best-reduced_#{board_class}"
        best_origial_dir = "#{log_dir}/best_#{board_class}"

        index = $row_index + 2
        local_index = 1
        reduced_files = Dir.new(best_reduced_dir).entries.delete_if{ |i| i[/^.*\.xml$/] == nil}.sort
        reduced_files.each { |filename|
          original_xml = REXML::Document.new(File.new("#{log_dir}/best_#{board_class}/#{filename}"))
          reduced_xml = REXML::Document.new(File.new("#{log_dir}/best-reduced_#{board_class}/#{filename}"))
          
          compile_str = REXML::XPath.first(reduced_xml, "/benchmark_run").attributes["compile_str"]
          performance = REXML::XPath.first(original_xml, "/benchmark_run").attributes["score"]
          binary_size = REXML::XPath.first(original_xml, "/benchmark_run").attributes["binary_size"]
          
          $row_array[index] = Array.new
          $row_array[index].push("#{local_index})")
          $row_array[index].push(binary_size)
          $row_array[index].push(performance)
          $row_array[index].push(compile_str)
          
          index += 1
          local_index +=1
        }

      end

      if reduce == "reduce-by-score"
        
        $row_index = $row_array.size
        $row_array[$row_index] = Array.new
        $row_array[$row_index + 1] = Array.new
        $row_array[$row_index + 1][0] = "Clustered Pareto-front after Reduce-by-score"

        best_reduced_dir = "#{log_dir}/best-byscore-reduced_#{board_class}"

        index = $row_index + 2
        local_index = 1
        reduced_files = Dir.new(best_reduced_dir).entries.delete_if{ |i| i[/^.*\.xml$/] == nil}.sort
        reduced_files.each { |filename|
          reduced_xml = REXML::Document.new(File.new("#{log_dir}/best-byscore-reduced_#{board_class}/#{filename}"))

          compile_str = REXML::XPath.first(reduced_xml, "/benchmark_run").attributes["compile_str"]
          performance = REXML::XPath.first(reduced_xml, "/benchmark_run").attributes["score"]
          binary_size = REXML::XPath.first(reduced_xml, "/benchmark_run").attributes["binary_size"]

          $row_array[index] = Array.new
          $row_array[index].push("#{local_index})")
          $row_array[index].push(binary_size)
          $row_array[index].push(performance)
          $row_array[index].push(compile_str)

          index += 1
          local_index +=1
        }
      end


    end


    # write the containing of $row_array to the sheet of xlsx document
    (0...$row_array.size).each { |row|
      sheet.add_row($row_array[row])
    }


  end
end
  
