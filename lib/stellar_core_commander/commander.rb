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
        make_process transactor, :node0, [:node0], 1
      end
      @processes[0]
    end

    Contract None => ArrayOf[Process]
    def start_all_processes
      stopped = @processes.select(&:stopped?)

      stopped.each do |p|
        p.prepare
      end

      stopped.each do |p|
        if not p.running?
          $stderr.puts "running #{p.idname} (dir:#{p.working_dir})"
          p.run
          if p.await_sync?
            p.wait_for_ready
          end
        end
      end
    end

    Contract None => ArrayOf[Process]
    def require_processes_in_sync
      @processes.each do |p|
        if p.await_sync? and not p.synced?
          raise "process #{p.name} lost sync"
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
