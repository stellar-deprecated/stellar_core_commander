require 'fileutils'

module StellarCoreCommander

  #
  # Commander is the object that manages running stellar-core processes.  It is
  # responsible for creating and cleaning Process objects
  #
  class Commander
    include Contracts

    #
    # Creates a new core commander
    #
    Contract Or["local", "docker"], String, Hash => Any
    def initialize(process_type, destination, process_options={})
      @process_type = process_type
      @destination = destination
      @process_options = process_options
      @processes = []
    end

    Contract Transactor, Symbol, ArrayOf[Symbol], Num, Hash => Process
    #
    # make_process returns a new, unlaunched Process object, bound to a new
    # tmpdir
    def make_process(transactor, name, quorum, thresh, options={})
      working_dir = File.join(@destination, name.to_s)
      FileUtils.mkpath(working_dir)

      process_options = @process_options.merge({
        transactor:   transactor,
        working_dir:  working_dir,
        name:         name,
        base_port:    39132 + @processes.map(&:required_ports).sum,
        identity:     Stellar::KeyPair.random,
        quorum:       quorum,
        threshold:    thresh,
        manual_close: false
      }).merge(options)

      process_class = case @process_type
                        when 'local'
                          LocalProcess
                        when 'docker'
                          DockerProcess
                        else
                          raise "Unknown process type: #{@process_type}"
                      end

      process_class.new(process_options).tap do |p|
        @processes << p
      end
    end

    Contract Transactor => Process
    def get_root_process(transactor)
      if @processes.size == 0
        make_process transactor, :node0, [:node0], 1, { manual_close: transactor.manual_close }
      end
      @processes[0]
    end

    Contract None => ArrayOf[Process]
    def start_all_processes
      @processes.each do |p|
        if not p.running?
          $stderr.puts "running #{p.idname} (dir:#{p.working_dir})"
          p.run
          p.wait_for_ready
        end
      end
    end

    def cleanup
      @processes.each(&:cleanup)
    end

    def cleanup_at_exit!
      at_exit do
        $stderr.puts "cleaning up #{@processes.length} processes"
        cleanup
      end
    end

  end
end
