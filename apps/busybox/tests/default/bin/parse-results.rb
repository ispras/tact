#!/usr/bin/ruby -w

#require ENV['TACT_DIR'] + '/lib/ResultsParserBase.rb'

# This class implements basic parser functionality.  It assumes test output has the following
# format:
#
# FLAGS=-O2 -fno-gcse
# BINHASH=a2b25250ce9c95d96a75680fb0906e26
#
# TEST_BOARD=1
# NUM_REPETITIONS=3
#
# REPETITION=1
# TEST=Test  2: 25kINS
#
# real 5.15
# user 4.71
# sys 0.21
#
# HASH=c31607ab3224d141835d93cd68289926
# STATUS=OK
#
# OVERALL_STATUS=OK
#
# This output consists of several chunks, each printed by a distinct script.
# ...

class AppResultsParser < ResultsParserBase

    # This implementation assumes that each test is run once within a testsuite, and NUM_REPETITIONS
    # defines the number of times test suite is run. I.e. this implementation of user_handle_single_line 
    # expects test data in following order: test1_run1, test2_run1, test1_run2, test2_run2, ...
    # If test suite outputs data in different order (each test is run for several times, and only then
    # it runs the next one), then between each two note_next_test calls should be several store_

    def user_handle_single_line(line)
      # Extract test hash
      matches = line.match(/^HASH=(.+)$/)
        if matches && matches.length == 2
        store_current_value('hash', matches[1])
      end

      # Extract test value
      matches = line.match(/^user (\d+\.\d+)/)
      if matches
        # When encountering the first line of the output of new test, switch test number
        note_next_test

        # we have only one test name, so set it to 'unlzma'
        set_current_test_name("unlzma")

        res = matches[1].to_f
        store_current_value('value', res)
      end
    end
end

#GenericResultsParser.new.run
