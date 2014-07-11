#!/usr/bin/ruby

require 'rexml/document'
include REXML
include Math

class XMLVerificationException < Exception
  attr_accessor :error_node

  def initialize(text, error_node = nil)
    super(text)
    @error_node = error_node
  end
end

class VerifyResults

  def initialize(results,params)
    @results = results
    @reference_file = params[:reference_file]
    @compare_hashes = !params[:reference_run]
    @reference_run = Document.new(File.new(@reference_file)) if @compare_hashes
  end
  
  def status_ok?(str)
    return str.match(/^ok/i)
  end
  
  def run
    benchmark_run = XPath.first(@results, "//benchmark_run")

    begin
      # If there's already an error status in results file, do nothing
      if !status_ok?(benchmark_run.attributes['result'])
        raise XMLVerificationException.new("run status is " + benchmark_run.attributes['result'])
      end
      
      verify_structure(benchmark_run)
      if @compare_hashes
        reference_tests = XPath.match(@reference_run, "//test")
        verify_hashes(XPath.match(benchmark_run, "//test"), reference_tests)
        if benchmark_run.attributes['compiler'] != XPath.first(@reference_run,"//benchmark_run").attributes['compiler']
          $stderr.puts "!!! Warning! You are using different compiler, that was for reference run!"
        end
      end
      return true
    rescue XMLVerificationException => e
      $stderr.puts "Verification error: " + e.to_s
      benchmark_run.attributes['result'] = 'error'
      benchmark_run.attributes['error-status'] = e.to_s
      if e.error_node
        e.error_node.attributes['status'] = 'error'
        e.error_node.attributes['error-status'] = e.to_s
      end
      return false
    end
  end

  def verify_structure(benchmark_run)
    num_reps = benchmark_run.attributes['repetitions'].to_i
    
    XPath.each(benchmark_run, "test") do |test|
      if XPath.match(test, "run").length != num_reps
        raise XMLVerificationException.new("incostistent structure", test)
      end
      
      status = nil
      first_hash = XPath.first(test, "run").attributes['hash']
      XPath.each(test, "run") do |run|
        hash = run.attributes['hash']
        if first_hash && !hash
          raise XMLVerificationException.new("some tests/runs do not have hashes", test)
        end
        if hash && hash != first_hash
          raise XMLVerificationException.new("different hashes within same test", test)
        end
        status = run.attributes['status']
        if status && !status_ok?(status)
          raise XMLVerificationException.new("one or more tests have error status", test)
        end
      end

      # Move duplicate info to test level
      test.attributes['status'] = status
      test.attributes['hash'] = first_hash

      XPath.each(test, "run") do |run|
        run.attributes.delete('status')
        run.attributes.delete('hash')
      end
    end
  end

  def verify_hashes(current_tests, reference_tests)
    if current_tests.length != reference_tests.length
      raise XMLVerificationException, "input and reference files have different number of tests"
    end

    current_tests.each do |test|
      cur_test_name = test.attributes['name']
      ref = XPath.first(reference_tests, "//test[@name='#{cur_test_name}']")
      if !ref
        raise XMLVerificationException.new("test not found in a reference file", test)
      end
      if ref.attributes['hash'] != test.attributes['hash']
        raise XMLVerificationException.new("hash does not match that in a reference file", test)
      end
    end
  end
end
