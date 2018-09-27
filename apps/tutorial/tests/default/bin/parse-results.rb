#!/usr/bin/ruby

class AppResultsParser < ResultsParserBase

    def user_handle_single_line(line)
          # Extract test hash
          matches = line.match(/^HASH=(.+)$/)
          if matches && matches.length == 2
             store_current_value('hash', matches[1])
          end

          # Extract test value and begin new test
          matches = line.match(/^(\d+)\s-\s(slow|normal|fast|very fast)/)
          if matches && matches.length == 3
             # When encountering the first line of the output of new test, switch test number
             note_next_test
                        
             # in tutorial we have only one test name, so set it to 'tutorial'
             set_current_test_name("tutorial")
                                    
             # first matched value it's result of test
             res = matches[1].to_f
             store_current_value('value', res)
          end
     end
                                 
end

