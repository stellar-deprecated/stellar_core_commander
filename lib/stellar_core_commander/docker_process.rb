require 'uri'
require 'set'
require 'securerandom'

module StellarCoreCommander

  class DockerProcess < Process
    include Contracts

    attr_reader :docker_core_image
    attr_reader :docker_state_image

    Contract({
      docker_state_image: String,
      docker_core_image:  String,
      docker_pull: Bool,
      setup_timeout: Maybe[Num]
    } => Any)
    def initialize(params)
      @docker_pull  = params[:docker_pull]
      super

      @heka_container = Container.new(@cmd, docker_args, "stellar/heka", heka_container_name)
      @state_container = Container.new(@cmd, docker_args, params[:docker_state_image], state_container_name) do
        dump_database
      end
      @stellar_core_container = Container.new(@cmd, docker_args, params[:docker_core_image], container_name) do
        dump_data
      end

      @setup_timeout = params[:setup_timeout] || 300
    end

    Contract None => Num
    def required_ports
      3
    end

    Contract None => Any
    def launch_heka_container
      $stderr.puts "launching heka container #{heka_container_name} from image #{@heka_container.image}"
      @heka_container.launch(%W(--net container:#{container_name} --volumes-from #{container_name} -d), [])
    end

    Contract None => Any
    def launch_state_container
      $stderr.puts "launching state container #{state_container_name} from image #{@state_container.image}"
      @state_container.launch(%W(-p #{postgres_port}:5432 --env-file stellar-core.env),
       %W(postgres --fsync=off --full_page_writes=off --shared_buffers=512MB --work_mem=32MB))
    end

    Contract None => Any
    def shutdown_state_container
      @state_container.shutdown
    end

    Contract None => Any
    def shutdown_heka_container
      @heka_container.shutdown
    end

    Contract None => Any
    def shutdown_core_container
      @stellar_core_container.shutdown
    end

    Contract None => Any
    def write_config
      IO.write("#{working_dir}/stellar-core.env", config)
    end

    Contract None => Any
    def setup!
      write_config

      launch_state_container
      wait_for_port postgres_port
      launch_stellar_core true
      launch_heka_container if atlas

      at_exit do
        cleanup
      end

      counter = @setup_timeout
      while running?
        $stderr.puts "waiting for #{state_container_name} to complete setup"
        counter -= 1
        raise "setup did not complete before timeout of #{@setup_timeout}" if counter == 0
        sleep 1.0
      end
      @stellar_core_container.shutdown
    end

    Contract None => Any
    def launch_process
      launch_stellar_core false
    end

    Contract None => Bool
    def running?
      @stellar_core_container.running?
    end

    Contract None => Bool
    def heka_container_running?
      @heka_core_container.running?
    end

    Contract None => Bool
    def state_container_running?
      @state_container.running?
    end

    Contract None => Any
    def dump_data
      dump_logs
      dump_cores
      dump_scp_state
      dump_info
      dump_metrics
    end

    Contract None => Any
    def cleanup
      database.disconnect
      shutdown_core_container
      shutdown_state_container
      shutdown_heka_container if atlas
    end

    Contract None => Any
    def stop
      shutdown_core_container
    end

    Contract({
      docker_core_image:  String,
      forcescp:           Maybe[Bool]
    } => Any)
    def upgrade(params)
      stop

      @stellar_core_container.image = params[:docker_core_image]
      @forcescp = params.fetch(:forcescp, @forcescp)
      $stderr.puts "upgrading docker-core-image to #{docker_core_image}"
      launch_stellar_core false
      @await_sync = true
      wait_for_ready
    end

    Contract None => Any
    def dump_logs
      @stellar_core_container.logs
    end

    Contract None => Any
    def dump_cores
      @stellar_core_container.dump_cores
    end

    Contract None => Any
    def dump_database
      fname = "#{working_dir}/database-#{Time.now.to_i}-#{rand 100000}.sql"
      $stderr.puts "dumping database to #{fname}"
      res = @state_container.exec %W(pg_dump -U #{database_user} --clean --no-owner --no-privileges #{database_name})
      File.open(fname, 'w') {|f| f.write(res.out.to_s) }
      fname
    end

    Contract None => String
    def default_database_url
      @database_password ||= SecureRandom.hex
      "postgres://postgres:#{@database_password}@#{docker_host}:#{postgres_port}/stellar"
    end

    Contract None => Num
    def postgres_port
      base_port + 2
    end

    Contract None => String
    def container_name
      "scc-#{idname}"
    end

    Contract None => String
    def state_container_name
      "scc-state-#{idname}"
    end

    Contract None => String
    def heka_container_name
      "scc-heka-#{idname}"
    end

    Contract None => String
    def docker_host
      return host if host
      return URI.parse(ENV['DOCKER_HOST']).host if ENV['DOCKER_HOST']
      DEFAULT_HOST
    end

    Contract None => String
    def hostname
      docker_host
    end

    Contract None => Bool
    def docker_pull?
      @docker_pull
    end

    Contract None => ArrayOf[String]
    def aws_credentials_volume
      if use_s3 and File.exists?("#{ENV['HOME']}/.aws")
        ["-v", "#{ENV['HOME']}/.aws:/root/.aws:ro"]
      else
        []
      end
    end

    Contract None => Bool
    def use_s3
      if @use_s3
        true
      else
        if host and (@quorum.size > 1)
          $stderr.puts "WARNING: multi-peer with remote docker host, but no s3; history will not be shared"
        end
        false
      end
    end

    Contract None => ArrayOf[String]
    def shared_history_volume
      if use_s3
        []
      else
        dir = File.expand_path("#{working_dir}/../history-archives")
        Dir.mkdir(dir) unless File.exists?(dir)
        ["-v", "#{dir}:/history"]
      end
    end

    Contract None => String
    def history_get_command
      cmds = Set.new
      localget = "cp /history/%s/{0} {1}"
      s3get = "aws s3 --region #{@s3_history_region} cp #{@s3_history_prefix}/%s/{0} {1}"
      @quorum.each do |q|
        if q == @name
          next
        end
        if SPECIAL_PEERS.has_key? q
          cmds.add SPECIAL_PEERS[q][:get]
        elsif use_s3
          cmds.add s3get
        else
          cmds.add localget
        end
      end

      if cmds.size == 0
        if use_s3
          cmds.add s3get
        else
          cmds.add localget
        end
      end

      if cmds.size != 1
        raise "Conflicting get commands: #{cmds.to_a.inspect}"
      end
      <<-EOS.strip_heredoc
        HISTORY_GET=#{cmds.to_a.first}
      EOS
    end

    Contract None => String
    def history_put_commands
      if has_special_peers?
        ""
      else
        if use_s3
          <<-EOS.strip_heredoc
            HISTORY_PUT=aws s3 --region #{@s3_history_region} cp {0} #{@s3_history_prefix}/%s/{1}
          EOS
        else
          <<-EOS.strip_heredoc
            HISTORY_PUT=cp {0} /history/%s/{1}
            HISTORY_MKDIR=mkdir -p /history/%s/{0}
          EOS
        end
      end
    end

    def prepare
      $stderr.puts "preparing #{idname} (dir:#{working_dir})"
      return unless docker_pull?
      @state_container.pull
      @stellar_core_container.pull
      @heka_container.pull
    end

    def crash
      @stellar_core_container.exec %W(pkill -ABRT stellar-core)
    end

    private
    def launch_stellar_core fresh
      $stderr.puts "launching stellar-core container #{container_name} from image #{@stellar_core_container.image}"
      args = %W(--volumes-from #{state_container_name})
      args += aws_credentials_volume
      args += shared_history_volume
      args += %W(-p #{http_port}:#{http_port} -p #{peer_port}:#{peer_port})
      args += %W(--env-file stellar-core.env)
      command = %W(/start #{@name})
      if fresh
        command += ["fresh", "skipstart"]
      end
      if @forcescp
        command += ["forcescp"]
      end

      @stellar_core_container.launch(args, command)
      @stellar_core_container
    end

    Contract None => String
    def config
      (
      <<-EOS.strip_heredoc
        POSTGRES_PASSWORD=#{database_password}
        POSTGRES_DB=#{database_name}

        ENVIRONMENT=scc
        CLUSTER_NAME=#{recipe_name}
        HOSTNAME=#{idname}

        #{@name}_POSTGRES_PORT=#{postgres_port}
        #{@name}_PEER_PORT=#{peer_port}
        #{@name}_HTTP_PORT=#{http_port}
        #{@name}_NODE_SEED=#{identity.seed}
        NODE_IS_VALIDATOR=#{@validate}

        #{"MANUAL_CLOSE=true" if manual_close?}

        ARTIFICIALLY_GENERATE_LOAD_FOR_TESTING=true
        #{"ARTIFICIALLY_ACCELERATE_TIME_FOR_TESTING=true" if @accelerate_time}
        #{"CATCHUP_COMPLETE=true" if @catchup_complete}
        #{"CATCHUP_RECENT=" + @catchup_recent.to_s if @catchup_recent}

        #{"ATLAS_ADDRESS=" + atlas if atlas}

        METRICS_INTERVAL=#{atlas_interval}

        #{"COMMANDS=[\"ll?level=debug\"]" if @debug}

        FAILURE_SAFETY=0
        UNSAFE_QUORUM=true
        THRESHOLD_PERCENT=51

        PREFERRED_PEERS=#{peer_connections}
        VALIDATORS=#{quorum}

        HISTORY_PEERS=#{peer_names}

        NETWORK_PASSPHRASE=#{network_passphrase}

        INVARIANT_CHECKS=#{invariants.to_s}
      EOS
      ) + history_get_command + history_put_commands
    end

    def recipe_name
      File.basename($opts[:recipe], '.rb')
    rescue TypeError
      'recipe_name_not_found'
    end

    def docker_port
      if ENV['DOCKER_HOST']
        URI.parse(ENV['DOCKER_HOST']).port
      else
        2376
      end
    end

    def docker_args
      if host
        ["-H", "tcp://#{docker_host}:#{docker_port}"]
      else
        []
      end
    end
  end
end
