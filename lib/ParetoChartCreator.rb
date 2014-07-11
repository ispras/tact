#!/usr/bin/ruby -w


# in case of summary chart DIR is current log directory otherwise it's certain archive directory
def create_chart(dir, board_id, summary = false)

  require File.expand_path(File.dirname(__FILE__)) + '/ConfParser.rb' if summary == true

  tactconf = ConfParser.new()
#  board_id = tactconf.runtime_params[:board_id]

  if summary == true
    chart_generation_number = tactconf.static_params[:pareto_summary_chart_generation_number]
    num_generations = Dir.new("#{dir}").entries.delete_if{|i| i[/^generation.*$/] == nil}.size  

    if num_generations > chart_generation_number.to_i
      step = num_generations.to_i / chart_generation_number.to_i
    else
      step = 1
    end
  end

  chart_gnu = File.new("#{dir}/chart.gnu", 'w')

  chart_gnu.print <<EOF
#!/usr/bin/gnuplot -persist

set terminal jpeg
set terminal postscript solid color eps enhanced
set output "#{dir}/result.ps"
set xlabel "Performance (points)"
set ylabel "Size (bytes)"
set size ratio -1
set format y "%.0f"
#set xtics 2
EOF

  if summary == true
    chart_gnu.puts("plot \"#{dir}/generation_#{num_generations}/archive.log\" using 1:2 title \"flags\" with points, \\")
  
    #reference files
    ref_dir = Dir.new("#{File.dirname(dir)}/ref").entries.delete_if{ |i| i[/^#{board_id}.*\.dat$/] == nil}
    ref_dir.each { |file|
      chart_gnu.puts("     \"#{File.dirname(dir)}/ref/#{file}\" using 1:2 title column with points, \\")
    }

    i = num_generations.to_i
    while i > 1
      chart_gnu.puts("     \"#{dir}/generation_#{i}/pareto.log\" using 2:3 title \"pareto-#{i}\" with linespoints, \\")
      i -= step
    end

    # clustered pareto-ftont for last generation
    chart_gnu.puts("     \"#{dir}/generation_#{num_generations}/pareto-best.log\" using 2:3 title \"best-pareto\" with points")
  
  else
    chart_gnu.puts("plot \"#{dir}/archive.log\" using 1:2 title \"flags\" with points, \\")

    #reference files 
    ref_dir = Dir.entries("#{File.dirname(File.dirname(dir))}/ref").delete_if{ |i| i[/^#{board_id}.*\.dat$/] == nil}
    ref_dir.each { |file|
      chart_gnu.puts("     \"#{File.dirname(File.dirname(dir))}/ref/#{file}\" using 1:2 title column with points, \\")
    }

    chart_gnu.puts("     \"#{dir}/pareto.log\" using 2:3 title \"pareto\" with linespoints, \\")
    # clustered pareto-ftont for last generation
    chart_gnu.puts("     \"#{dir}/pareto-best.log\" using 2:3 title \"best-pareto\" with points")
  end

  chart_gnu.close

  system("gnuplot #{dir}/chart.gnu")
  if summary == true
    dir = dir[/^.*joint_archives_(.*)$/]
    system("cat #{dir}/result.ps | ps2pdf - #{File.dirname(dir)}/reports/Pareto_chart_#{$1}.pdf")
  else
    system("cat #{dir}/result.ps | ps2pdf - #{dir}/Pareto_chart.pdf")
  end


end

