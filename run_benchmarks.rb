#!/usr/bin/env ruby

require 'optparse'
require 'ostruct'
require 'fileutils'
require 'shellwords'

def check_call(args)
    command = (args.kind_of?(Array)) ? (args.shelljoin):args
    status = system(command)
    raise RuntimeError unless status
end

def check_output(args)
    output = IO.popen(args).read
    raise RuntimeError unless $?
    return output
end

def build_yjit(repo_dir)
    if !File.exist?(repo_dir)
        puts('Directory does not exist "' + repo_dir + '"')
        exit(-1)
    end

    Dir.chdir(repo_dir) do
        check_call(['git', 'pull'])

        # Don't do a clone and configure every time
        # ./config.status --config => check that DRUBY_DEBUG is not in there
        config_out = check_output(['./config.status', '--config'])

        if config_out.include?("DRUBY_DEBUG")
            puts("You should configure YJIT in release mode for benchmarking")
            exit(-1)
        end

        # Build in parallel
        #n_cores = os.cpu_count()
        n_cores = 32
        puts("Building YJIT with #{n_cores} processes")
        check_call(['make', '-j' + n_cores.to_s, 'install'])
    end
end

def set_bench_config()
    # Only available on intel systems
    if File.exist?('/sys/devices/system/cpu/intel_pstate')
        # sudo requires the flag '-S' in order to take input from stdin
        check_call("sudo -S sh -c 'echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo'")
        check_call("sudo -S sh -c 'echo 100 > /sys/devices/system/cpu/intel_pstate/min_perf_pct'")
    end
end

def get_ruby_version()
    ruby_version = check_output(["ruby", "-v"])
    puts(ruby_version)

    if !ruby_version.downcase.include?("yjit")
        puts("You forgot to chruby to ruby-yjit:")
        puts("  chruby ruby-yjit")
        exit(-1)
    end

    return ruby_version
end

def check_pstate()
    # Only available on intel systems
    if !File.exist?('/sys/devices/system/cpu/intel_pstate/no_turbo')
        return
    end

    #with open('/sys/devices/system/cpu/intel_pstate/no_turbo', mode='r') as file
    #    content = file.read().strip()

    #if content != '1'
    #    puts("You forgot to disable turbo:")
    #    puts("  sudo sh -c 'echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo'")
    #    exit(-1)

    #if not os.path.exists('/sys/devices/system/cpu/intel_pstate/min_perf_pct')
    #    return

    #with open('/sys/devices/system/cpu/intel_pstate/min_perf_pct', mode='r') as file
    #    content = file.read().strip()

    #if content != '100'
    #    puts("You forgot to set the min perf percentage to 100:")
    #    puts("  sudo sh -c 'echo 100 > /sys/devices/system/cpu/intel_pstate/min_perf_pct'")
    #    exit(-1)
end

def table_to_str(table_data)
    #def trim_cell(cell)
    #    try:
    #        return '{:.1f}'.format(cell)
    #    except:
    #        return cell

    #def trim_row(row)
    #    return list(map(lambda c: trim_cell(c), row))

    # Trim numbers to one decimal for console display
    #table_data = list(map(trim_row, table_data))

    #return tabulate(table_data)
end

def mean(values)
    return values.sum(0.0) / values.size
end

def stddev(values)
    xbar = mean(values)
    #diff_sqrs = map(lambda v: (v-xbar)*(v-xbar), values)
    #mean_sqr = sum(diff_sqrs) / values.length
    #return math.sqrt(mean_sqr)
end

def free_file_no(out_path)
    (1..1000).each do |file_no|
        out_path = File.join(out_path, "output_%03d.csv" % file_no)
        if !File.exist?(out_path)
            return file_no
        end
    end
    assert false
end

# Check if the name matches any of the names in a list of filters
def match_filter(name, filters)
    if filters.length == 0
        return true
    end

    filters.each do |filter|
        if name.downcase.include?(filter)
            return true
        end
    end
end

# Run all the benchmarks and record execution times
def run_benchmarks(enable_yjit, name_filters, out_path)
    bench_times = {}

    Dir.children('benchmarks').sort.each do |entry|
        bench_name = entry.gsub('.rb', '')

        if !match_filter(bench_name, name_filters)
            continue
        end

        # Path to the benchmark runner script
        script_path = File.join('benchmarks', entry)

        if !script_path.end_with?('.rb')
            script_path = File.join(script_path, 'benchmark.rb')
        end

        puts bench_name
        puts script_path

        # Set up the environment for the benchmarking command
        ENV["OUT_CSV_PATH"] = File.join(out_path, 'temp.csv')

        # Set up the benchmarking command
        cmd = [
            # Disable address space randomization (for determinism)
            #"setarch", "x86_64", "-R",
            # Increase process priority
            #"nice", "-20",
            # Pin the process to one given core
            #"taskset", "-c", "11",
            # Run the benchmark
            "ruby",
            enable_yjit ? "--yjit":"--disable-yjit",
            "-I", "./harness",
            script_path
        ]

        # Do the benchmarking
        puts(cmd.join(' '))
        check_call(cmd)

    #    with open(sub_env["OUT_CSV_PATH"]) as csvfile
    #        reader = csv.reader(csvfile, delimiter=',', quotechar='"')
    #        rows = list(reader)
    #        # Convert times to ms
    #        times = list(map(lambda v: 1000 * float(v), rows[0]))
    #        times = times.sort

        #puts(times)
        #puts(mean(times))
        #puts(stddev(times))

    #    bench_times[bench_name] = times

    end

    return bench_times
end











args = OpenStruct.new({
    repo_dir: "../yjit",
    out_path: "./data",
    name_filters: ['']
})

OptionParser.new do |opts|
  #opts.banner = "Usage: example.rb [options]"
  opts.on("--repo_dir=REPO_DIR") do |v|
    args.repo_dir = v
  end

  opts.on("--out_path=OUT_PATH", "directory where to store output data files") do |v|
    args.out_path = v
  end

  opts.on("--name_filters x,y,z", Array, "when given, only benchmarks with names that contain one of these strings will run") do |list|
    args.name_filters = list
  end

  opts.on("--out_path=OUT_PATH") do |v|
    args[:out_path] = v
  end

end.parse!

# Create the output directory
FileUtils.mkdir_p(args.out_path)

# Update and build YJIT
build_yjit(args.repo_dir)

# Disable CPU frequency scaling
set_bench_config()

# Get the ruby binary version string
ruby_version = get_ruby_version()

# Check pstate status
check_pstate()

# Benchmark with and without YJIT
bench_start_time = Time.now.to_f
yjit_times = run_benchmarks(enable_yjit=true, name_filters=args.name_filters, out_path=args.out_path)
interp_times = run_benchmarks(enable_yjit=false, name_filters=args.name_filters, out_path=args.out_path)
bench_end_time = Time.now.to_f
bench_names = yjit_times.keys.sort

bench_total_time = (bench_end_time - bench_start_time).to_i
puts("Total time spent benchmarking: #{bench_total_time}s")
puts()

# Table for the data we've gathered
table = [["bench", "interp (ms)", "stddev (%)", "yjit (ms)", "stddev (%)", "speedup (%)"]]

=begin
# Format the results table
for bench_name in bench_names
    yjit_t = yjit_times[bench_name]
    interp_t = interp_times[bench_name]

    speedup = 100 * (1 - (mean(yjit_t) / mean(interp_t)))

    table.append([
        bench_name,
        mean(interp_t),
        100 * stddev(interp_t) / mean(interp_t),
        mean(yjit_t),
        100 * stddev(yjit_t) / mean(yjit_t),
        speedup
    ])
=end

# Find a free file index for the output files
file_no = free_file_no(args.out_path)

=begin
# Save data as CSV so we can produce tables/graphs in a spreasheet program
# NOTE: we don't do any number formatting for the output file because
#       we don't want to lose any precision
output_tbl = [[ruby_version], []] + table
out_tbl_path = File.join(args.out_path, 'output_{:03d}.csv'.format(file_no))
with open(out_tbl_path , 'w') as csvfile:
    writer = csv.writer(csvfile, delimiter=',', quotechar='"')
    writer.writerow(output_tbl)

# Save the output in a text file that we can easily refer to
output_str = ruby_version + '\n' + table_to_str(table) + '\n'
out_txt_path = File.join(args.out_path, 'output_{:03d}.txt'.format(file_no))
with open(out_txt_path.format(file_no), 'w') as txtfile:
    txtfile.write(output_str)

# Save the raw data
out_json_path = File.join(args.out_path, 'output_{:03d}.json'.format(file_no))
with open(out_json_path, "w") as write_file:
    data = {
        'yjit': yjit_times,
        'interp': interp_times,
        'ruby_version': ruby_version,
    }
    json.dump(data, write_file, indent=4)

# Print the table to the console, with numbers truncated
puts(output_str)
=end