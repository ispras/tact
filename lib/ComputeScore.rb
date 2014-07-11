#!/usr/bin/ruby

require 'rexml/document'
require 'optparse'
include REXML
include Math

def merge_runs(values)
  values.sort!
  if values.length % 2 == 1
    return values[values.length / 2]
  else
    return (values[values.length / 2] + values[values.length / 2 - 1]) / 2
  end
end

def compute_score(results)
  test_descr = Document.new(File.new(ENV['TEST_DIR'] + "/etc/test-descr.xml"))
  case XPath.first(test_descr, "//benchmark_description").attributes['summary_method']
    when "geomean"
      function = Math.method(:log)
      unfunction = Math.method(:exp)
      weighted = false
    when "weighted_geomean"
      function = Math.method(:log)
      unfunction = Math.method(:exp)
      weighted = true
    when "mean"
      function = lambda {|x| x}
      unfunction = lambda {|x| x}
      weighted = false
    when "weighted_mean"
      function = lambda {|x| x}
      unfunction = lambda {|x| x}
      weighted = true
  end

  tests = Hash.new
  sum = 0.0
  total_weight = 0.0

  XPath.each(results, "//test") do |t|
    name = t.attributes['name']
    if weighted
      weight = XPath.first(test_descr, "//test[@name='#{name}']").attributes['weight'].to_f
    else
      weight = 1.0
    end

    if weight != 0
      sum += weight * 
        function.call( merge_runs( XPath.match(t, "run").map{|r| r.attributes['value'].to_f} ) )
    end
    total_weight += weight
  end

  score = unfunction.call(sum/total_weight)
  score = sprintf("%.6f",score).to_f

  XPath.first(results, "//benchmark_run").attributes['score'] = score
  return score
end

