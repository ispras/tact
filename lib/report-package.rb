#!/usr/bin/ruby

#gem install fast_xs
#gem install rubyzip

require 'rexml/document'
#include REXML

#require 'rubygems'
require File.expand_path(File.dirname(__FILE__)) + '/simple_xlsx.rb'
package_dir = ARGV[0]

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

if File.exists?("#{package_dir}/log/current/results.xlsx")
  system("rm #{package_dir}/log/current/results.xlsx")
end
SimpleXlsx::Serializer.new("/#{package_dir}/log/current/results.xlsx") do |doc|
  doc.add_sheet("Perf_results") do |sheet|
    apps_dir = "#{package_dir}/log/current/tests"
    contains_tests = Dir.new(apps_dir).entries.reject!{|i| i == "." or i == ".."}

    row_array = Array.new
    row_index = 0
    contains_tests.each { |dirname|
      row_array[row_index] = Array.new
      row_array[row_index].push("#{dirname}")
      row_array[row_index + 1] = Array.new
      row_array[row_index + 1].push("PERFORMANCE") #add name of application

      #test_descr.xml
      weights_array = Array.new
      test_descr = REXML::Document.new(File.new("#{apps_dir}/#{dirname}/etc/test-descr.xml"))
      REXML::XPath.each(test_descr, "//test") do |test|
        weights_array.push(test.attributes["weight"])
      end

      case REXML::XPath.first(test_descr, "//benchmark_description").attributes['summary_method']
      when "geomean"
        weighted = false
        isgeom = true
        size = false
      when "weighted_geomean"
        weighted = true
        isgeom = true
        size = false
      when "mean"
        weighted = false
        isgeom = false
        size = false
      when "weighted_mean"
        weighted = true
        isgeom = false
        size = false
      when "size"
	size = true
	weighted = false
	isgeom = false
      end
      
      case REXML::XPath.first(test_descr, "//benchmark_description").attributes['greater_is_better']
      when "true"
        isbiggerbetter = true
      when "false"
        isbiggerbetter = false
      end
      
      index = 0 #current row index
      first_test_xml = true #true if the first test xml file in considered
      xml_dir = ["ref.xml"] + Dir.new("#{apps_dir}/#{dirname}").entries.delete_if{ |i| i[/^.*\.xml$/] == nil}.reject!{ |i| i == "ref.xml"}
      xml_dir.each { |filename|

        puts filename
        
        xml_name = REXML::Document.new(File.new("#{apps_dir}/#{dirname}/#{filename}"))
        compile_str = REXML::XPath.first(xml_name, "/benchmark_run").attributes["compile_str"]
        repetitions = REXML::XPath.first(xml_name, "/benchmark_run").attributes["repetitions"]
        result = REXML::XPath.first(xml_name, "/benchmark_run").attributes["result"]
        
        if first_test_xml
          row_array[row_index + 1].push(compile_str)
          row_index += 2
        else
          next_xml_column = row_array[row_index - 1].size 
          row_array[row_index - 1][next_xml_column] = compile_str
        end
       
        index = row_index
        REXML::XPath.each(xml_name, "//test") do |test|
          if first_test_xml
            row_array[index] = Array.new
            name = test.attributes["name"]
            row_array[index].push(name)
          end

          REXML::XPath.each(test, "run") do |run|
            run_value = run.attributes["value"]

            if result == "ok" or result == "OK" 
              row_array[index].push(run_value.to_f)
            else
              row_array[index].push("error_run")
            end
          end
          median_from = row_array[index].size - repetitions.to_i
          median_to = row_array[index].size - 1
          row_array[index].push("=MEDIAN(#{column_char(median_from)}#{index + 1}:#{column_char(median_to)}#{index + 1})")
          index += 1
        end

        row_array[row_index - 1][row_array[index - 1].size - 1] = "Median"
        
        #Compute Mean
        if first_test_xml
          mean_row = row_array[index] = Array.new
          mean_row.push("Mean")
        end
        current_size = row_array[index - 1].size
        ((current_size - repetitions.to_i - 1)...current_size).each { |col|
          row_array[index].push(compute_mean_formula(row_index, col , isgeom, weighted, weights_array))
        }
       
        #Compute delta 
        if first_test_xml == false
          row_array[row_index - 1][row_array[index - 1].size] = "Delta"
          if isbiggerbetter == true 
            minus = ""
          else
            minus = "-"
          end
          (row_index..index).each{ |row|
            row_array[row].push("=(#{column_char(row_array[row].size - 1)}#{row + 1}/#{column_char(repetitions.to_i + 1)}#{row + 1} - 1)*(#{minus}100)") 
          }
        end

        first_test_xml = false
      }
      row_index = index + 3
      row_array[row_index - 2] = Array.new
      row_array[row_index - 1] = Array.new
      row_array[row_index] = Array.new
      row_array[row_index + 1] = Array.new
      row_array[row_index - 1][0] = "#{dirname}"  
      row_array[row_index][0] = "BINARY_SIZE"
      row_array[row_index + 1 ][0] = ""

      first_baseline = true
      xml_dir.each{ |filename|
        xml_name = REXML::Document.new(File.new("#{apps_dir}/#{dirname}/#{filename}"))
        compile_str = REXML::XPath.first(xml_name, "/benchmark_run").attributes["compile_str"]
        binary_size = REXML::XPath.first(xml_name, "/benchmark_run").attributes["binary_size"]

        row_array[row_index].push(compile_str)
        row_array[row_index + 1].push(binary_size)

        if first_baseline == false
          row_array[row_index].push("Delta %")
          row_array[row_index + 1].push("=(1 - #{column_char(row_array[row_index].size - 2)}#{row_index + 2}/B#{row_index + 2})*100")
        end
        first_baseline = false
      }
      row_index = row_index + 3

      row_array[row_index - 1] =  Array.new #empty line between application results
      row_array[row_index] =  Array.new
      
    }

    # write the containing of row_array to the sheet of xlsx document
    (0...row_array.size).each { |row|
      sheet.add_row(row_array[row])
    }

  end
end
  
