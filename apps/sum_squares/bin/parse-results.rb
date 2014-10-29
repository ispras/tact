#!/usr/bin/ruby

class AppResultsParser < ResultsParserBase

    def user_handle_single_line(line)
          # Extract test value and begin new test
          matches = line.match(/^RESULT=(-?\d*\.\d+)/)
          if matches && matches.length == 2
             # When encountering the first line of the output of new test, switch test number
             note_next_test
                        
             # in um_squares we have only one test, so set its name to 'sum'
             set_current_test_name("sum")
                                    
             # first matched value it's result of test
             res = matches[1]
             store_current_value('value', res) if !res.nil?
          end
     end
                                 
end

