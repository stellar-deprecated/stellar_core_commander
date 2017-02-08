require 'uri'
require 'set'
require 'securerandom'

module StellarCoreCommander

  class Container
    include Contracts

    attr_accessor :image

    Contract Cmd, ArrayOf[String], String, String => Any
    def initialize(cmd, args, image, name)
      @cmd = cmd
      @args = args
      @image = image
      @name = name
    end

    Contract ArrayOf[String], ArrayOf[String] => Any
    def launch(arguments, command)
      res = docker %W(run -d --name #{@name}) + arguments + [@image] + command
      raise "Could not create #{@name}: #{res.stderr.to_s}" unless res.success
      res
    end

    Contract None => Any
    def stop
      command %W(stop #{@name})
    end

    Contract ArrayOf[String] => Any
    def exec(arguments)
      command %W(exec #{@name}) + arguments
    end

    Contract None => Any
    def logs
      command %W(logs #{@name})
    end

    Contract None => Any
    def pull
      command %W(pull #{@image})
    end

    Contract None => Any
    def dump_cores
      res = command %W(run --volumes-from #{@name} --rm -e MODE=local #{@image} /utils/core_file_processor.py)
      command %W(cp #{@name}:/cores .)
      res
    end

    Contract ArrayOf[String] => Any
    def command(arguments)
      res = docker arguments
      raise "Could not execute '#{arguments.join(" ")}' on #{@name}: #{res.stderr.to_s}" unless res.success
      res
    end

    Contract None => Any
    def shutdown
      return CmdResult.new(true) unless exists?
      res = docker %W(rm -f -v #{@name})
      raise "Could not force remove container: #{@name}: " + res.stderr.to_s unless res.success
      res
    end

    Contract None => Bool
    def exists?
      res = docker ['inspect', '-f', '{{.Name}}', @name]
      res.success
    end

    Contract None => Bool
    def running?
      res = docker ['inspect', '-f', '{{.Name}} running: {{.State.Running}}', @name]
      res.success and res.stdout.include? 'running: true'
    end

    def docker(args)
      @cmd.run_cmd "docker", @args + args
    end
  end
end
