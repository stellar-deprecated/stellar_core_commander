require 'uri'
require 'set'
require 'securerandom'

module StellarCoreCommander

  class Container
    include Contracts

    attr_accessor :image

    Contract Cmd, ArrayOf[String], String, String, Maybe[Func[None => Any]] => Any
    def initialize(cmd, args, image, name, &at_shutdown)
      @cmd = cmd
      @args = args
      @image = image
      @name = name
      @at_shutdown = at_shutdown
    end

    Contract ArrayOf[String], ArrayOf[String] => CmdResult
    def launch(arguments, command)
      command(@cmd.method(:run_and_redirect), %W(run -d --name #{@name}) + arguments + [@image] + command)
    end

    Contract None => CmdResult
    def stop
      command(@cmd.method(:run_and_redirect), %W(stop #{@name}))
    end

    Contract ArrayOf[String] => CmdResult
    def exec(arguments)
      command(@cmd.method(:run_and_capture), %W(exec #{@name}) + arguments)
    end

    Contract None => CmdResult
    def logs
      command(@cmd.method(:run_and_redirect), %W(logs #{@name}))
    end

    Contract None => CmdResult
    def pull
      command(@cmd.method(:run_and_redirect), %W(pull #{@image}))
    end

    Contract None => CmdResult
    def dump_cores
      command(@cmd.method(:run), %W(run --volumes-from #{@name} --rm -e MODE=local #{@image} /utils/core_file_processor.py))
      command(@cmd.method(:run), %W(cp #{@name}:/cores .))
    end

    Contract None => CmdResult
    def shutdown
      $stderr.puts "removing container #{@name} (image #{@image})"
      return CmdResult.new(true) unless exists?

      begin
        if @at_shutdown.is_a? Proc and exists?
          @at_shutdown.call
        end
      rescue Exception => e
        $stderr.puts "Error during at_shutdown call: #{e.class.name}): #{e.message}"
      ensure
        retries = 5
        loop do
          res = command(@cmd.method(:run_and_redirect), %W(rm -f -v #{@name}), false)
          return CmdResult.new(true) unless exists?
          return res if res.success or retries == 0
          retries -= 1
          sleep 3
        end
      end
    end

    Contract None => Bool
    def exists?
      res = command(@cmd.method(:run_and_redirect), ['inspect', '-f', '{{.Name}}', @name], false)
      res.success
    end

    Contract None => Bool
    def running?
      res = command(@cmd.method(:run_and_capture), ['inspect', '-f', '{{.Name}} running: {{.State.Running}}', @name], false)

      res.success && res.out.include? 'running: true'
    end

    Contract Method, ArrayOf[String], Maybe[Bool] => CmdResult
    def command(run_method, arguments, mustSucceed = true)
      res = docker(run_method, arguments)
      if mustSucceed
        raise "Could not execute '#{arguments.join(" ")}' on #{@name}" unless res.success
      end
      res
    end

    Contract Method, ArrayOf[String] => CmdResult
    def docker(run_method, args)
      run_method.call("docker", @args + args)
    end
  end
end
