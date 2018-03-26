require 'fileutils'

module StellarCoreCommander

  #
  # Commander is the object that manages running stellar-core processes.  It is
  # responsible for creating and cleaning Process objects
  #
  class Commander
    include Contracts

    attr_reader :process_options

    #
    # Creates a new core commander
    #
    Contract Or["local", "docker"], Numeric, String, Hash => Any
    def initialize(process_type, base_port, destination, process_options={})
      @process_type = process_type
      @base_port = base_port
      @destination = destination
      @process_options = process_options
      @processes = []

      if File.exist? @destination
        $stderr.puts "scc is not capable of running with an existing destination directory.  Please rename or remove #{@destination} and try again"
        exit 1
      end
    end

    Contract Transactor, Symbol, ArrayOf[Symbol], Hash => Process
    #
    # make_process returns a new, unlaunched Process object, bound to a new
    # tmpdir
    def make_process(transactor, name, quorum, options={})
      working_dir = File.join(@destination, name.to_s)
      FileUtils.mkpath(working_dir)

      process_options = @process_options.merge({
        transactor:   transactor,
        working_dir:  working_dir,
        name:         name,
        base_port:    @base_port + @processes.map(&:required_ports).sum,
        identity:     Stellar::KeyPair.random,
        quorum:       quorum,
        manual_close: transactor.manual_close
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
        make_process transactor, :node0, [:node0]
      end
      @processes[0]
    end

    Contract None => ArrayOf[Process]
    def start_all_processes
      stopped = @processes.select(&:stopped?)

      stopped.each(&:prepare)
      stopped.each(&:setup)

      stopped.each do |p|
        next if p.running?

        $stderr.puts "running #{p.idname} (dir:#{p.working_dir})"
        p.run
        p.wait_for_ready

      end
    end

    Contract None => ArrayOf[Process]
    def require_processes_in_sync
      @processes.each do |p|
        next unless p.await_sync?
        begin
          p.wait_for_ready unless p.synced?
        rescue Timeout::Error
          @processes.each do |p2|
            p2.dump_scp_state
            p2.dump_info
            p2.dump_metrics
            raise "process #{p.name} lost sync"
          end
        end
      end
    end

    Contract None => Bool
    def check_no_process_error_metrics
      @processes.each do |p|
        p.check_no_error_metrics
      end
      true
    end

    def cleanup
      @processes.each(&:cleanup)
    end

    def cleanup_at_exit!(clean_up_destination)
      at_exit do
        $stderr.puts "cleaning up #{@processes.length} processes"
        cleanup
        FileUtils.rm_rf @destination if clean_up_destination
      end
    end
  end
end
