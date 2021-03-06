#!/usr/bin/env ruby
# Copyright 2012 Twitter Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Script that runs a single scalding job

require 'optparse'
require 'ostruct'
require 'pp'
require 'date'

$HOST = "my.remote.host"

class OptparseJobArguments

  #
  # Return a structure describing the options.
  #
  def self.parse(args)
    # The options specified on the command line will be collected in *options*.
    # We set default values here.
    options = OpenStruct.new
    options.job = nil
    options.uses_settings = false
    options.uses_hadoop_config = false
    options.set_timezone = false
    options.dates = []
    options.output = ""
    options.preprocessor = false

    opts = OptionParser.new do |opts|
      opts.banner = "Usage: run_job.rb -j JOB -d DATE -o OUTPUT -p -t TIMEZONE -s SETTINGS -c CONFIG"

      opts.separator ""
      opts.separator "Specific options:"

      opts.on("-j", "--job JOBNAME",
              "The JOBNAME to run") do |job|
        options.job = job
      end

      opts.on("-d", "--date DATES", Array,
              "The DATES to run the job over. Expected format is %Y-%m-%d") do |dates|
        options.dates = dates.map{|date| DateTime.strptime(date, '%Y-%m-%d')}
      end

      opts.on("-o", "--output OUTPUT",
              "The OUTPUT file to write to") do |output|
        options.output = output
      end
      
      opts.on("-p", "--[no-]prep", "Run as preprocessor") do |v|
        options.preprocessor = true
      end

      opts.on("-t", "--tz [TIMEZONE]", "Specify timezone for job. Default is local time") do |timezone|
        options.set_timezone = true
        options.timezone = timezone || ''
      end

      opts.on("-s", "--settings [SETTINGS]", "Optional settings for the job") do |settings|
        options.uses_settings = true
        options.settings = settings || ''
      end

      opts.on("-c", "--config [CONFIG]", "Optional hadoop configurations for the job.") do |config|
        options.uses_hadoop_config = true
        options.hadoop_config = config || ''
      end


      opts.separator ""
      opts.separator "Common options:"      
      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end
    end
    opts.parse!(args)
    options
  end
end

class JobArguments
  attr_accessor :dates, :settings, :hadoop_config, :timezone, :job, :output, :prep
  
  def initialize(dates, settings, hadoop_config, timezone, job, output, prep)
    @dates = dates
    @settings = settings
    @hadoop_config = hadoop_config
    @timezone = timezone
    @job = job
    @output = output
    @prep = prep
  end
end

def time_to_remote_file(time, prefix)
  return prefix + time.year.to_s() + "/" + append_zero(time.month) + "/" + append_zero(time.day)
end

def append_zero(x)
  if 0 <= x and x <= 9
    0.to_s() + x.to_s()
  else
    x.to_s()
  end
end

# TODO: So hacky OMG what is this I don't even
def is_hadoop_local_machine?()
  return system("hadoop dfs -test -e .")
end

def hadoop_cmd_head(hadoop_config)
  cmd = is_hadoop_local_machine?() ? "" : "ssh -C " + $HOST + " "
  cmd += "hadoop "
  cmd += (hadoop_config == nil) ? "" : hadoop_config
  return cmd
end

def remote_file_exists?(pathname, hadoop_config)
  cmd = hadoop_cmd_head(hadoop_config)
  cmd += " dfs -test -e " + pathname
  result = system(cmd)
  puts "Remote_file_exists for " + pathname + ": " + result.to_s()
  return result
end

def date_to_cmd(time)
  return time.year.to_s() + "-" + append_zero(time.month) + "-" + append_zero(time.day)
end

def run_job(args)
  if (args == nil)
    return
  end
  uses_settings = args.settings != nil
  set_timezone = args.timezone != nil
  start_date = args.dates.at(0)
  end_date = args.dates.length > 1 ? args.dates.at(1) : args.dates.at(0)
  hadoop_config_cmd = (args.hadoop_config == nil) ? "" : args.hadoop_config
  cmd_head = File.dirname(__FILE__) + "/scald.rb --hdfs com.twitter.zipkin.hadoop."
  settings_string = uses_settings ? " " + args.settings : ""
  cmd_date = date_to_cmd(start_date) + " " + date_to_cmd(end_date)
  timezone_cmd = set_timezone ? " --tz " + args.timezone : ""
  cmd_args = args.job + settings_string  + " " + hadoop_config_cmd + " --date " + cmd_date + timezone_cmd
  
  if args.prep
    if not remote_file_exists?(time_to_remote_file(end_date, args.job + "/") + "/_SUCCESS", args.hadoop_config)
      cmd = cmd_head + "sources." + cmd_args
      puts cmd
      system(cmd)
    end
  else
    if not remote_file_exists?(args.output + "/_SUCCESS", args.hadoop_config)
      cmd = cmd_head + cmd_args + " --output " + args.output
      puts cmd
      system(cmd)
    end
  end
end

if __FILE__ == $0
  options = OptparseJobArguments.parse(ARGV)
  run_job(options.dates, options.settings, options.hadoop_config, options.timezone, options.job, options.output, options.preprocessor)
end
