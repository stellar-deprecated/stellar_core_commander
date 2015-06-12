require 'uri'
require 'securerandom'

module StellarCoreCommander

  class DockerProcess < Process
    include Contracts

    Contract({
      docker_state_image: String,
      docker_core_image:  String,
      docker_pull: Bool
    } => Any)
    def initialize(params)
      @docker_state_image = params[:docker_state_image]
      @docker_core_image  = params[:docker_core_image]
      @docker_pull  = params[:docker_pull]
      super
    end

    Contract None => Num
    def required_ports
      3
    end

    Contract None => Any
    def launch_heka_container
      $stderr.puts "launching heka container #{heka_container_name}"
      docker %W(pull stellar/heka) if docker_pull?
      docker %W(run
        --name #{heka_container_name}
        --net container:#{container_name}
        --volumes-from #{container_name}
        -d stellar/heka
      )
    end

    Contract None => Any
    def launch_state_container
      $stderr.puts "launching state container #{state_container_name} from image #{@docker_state_image}"
      docker %W(pull #{@docker_state_image}) if docker_pull?
      docker %W(run --name #{state_container_name} -p #{postgres_port}:5432 --env-file stellar-core.env -d #{@docker_state_image})
      raise "Could not create state container" unless $?.success?
    end

    Contract None => Any
    def shutdown_state_container
      return true unless state_container_running?
      docker %W(rm -f -v #{state_container_name})
      raise "Could not drop db: #{database_name}" unless $?.success?
    end

    Contract None => Any
    def shutdown_heka_container
      return true unless heka_container_running?
      docker %W(rm -f -v #{heka_container_name})
      raise "Could not stop heka container: #{heka_container_name}" unless $?.success?
    end

    Contract None => Any
    def write_config
      IO.write("#{working_dir}/stellar-core.env", config)
    end

    Contract None => Any
    def setup
      write_config
    end

    Contract None => Any
    def run
      raise "already running!" if running?
      setup
      launch_state_container
      launch_stellar_core
      launch_heka_container if atlas
    end

    Contract None => Bool
    def running?
      container_running? container_name
    end

    Contract None => Bool
    def heka_container_running?
      container_running? heka_container_name
    end

    Contract None => Bool
    def state_container_running?
      container_running? state_container_name
    end

    Contract None => Any
    def shutdown
      return true unless running?
      docker %W(stop #{container_name})
      docker %W(exec #{container_name} rm -rf /history)
      docker %W(rm -f #{container_name})
    end

    Contract None => Any
    def cleanup
      database.disconnect
      dump_logs
      shutdown
      shutdown_state_container
      shutdown_heka_container if atlas
    end

    Contract None => Any
    def dump_logs
      docker ["logs", container_name]
    end

    Contract None => Any
    def dump_database
      Dir.chdir(working_dir) do
        host_args = "-H tcp://#{docker_host}:#{docker_port}" if host
        `docker #{host_args} exec #{state_container_name} pg_dump -U #{database_user} --clean --no-owner --no-privileges #{database_name}`
      end
    end

    Contract None => Sequel::Database
    def database
      @database ||= Sequel.postgres(database_name, host: docker_host, port: postgres_port, user: database_user, password: database_password)
    end

    Contract None => String
    def database_name
      "stellar"
    end

    Contract None => String
    def database_user
      "postgres"
    end

    Contract None => String
    def database_password
      @database_password ||= SecureRandom.hex
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
      if use_s3 and (not host)
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
    def history_commands
      if use_s3
        <<-EOS.strip_heredoc
          HISTORY_GET=aws s3 --region #{@s3_history_region} cp #{@s3_history_prefix}/%s/{0} {1}
          HISTORY_PUT=aws s3 --region #{@s3_history_region} cp {0} #{@s3_history_prefix}/%s/{1}
        EOS
      else
        <<-EOS.strip_heredoc
          HISTORY_GET=cp /history/%s/{0} {1}
          HISTORY_PUT=cp {0} /history/%s/{1}
          HISTORY_MKDIR=mkdir -p /history/%s/{0}
        EOS
      end
    end

    private
    def launch_stellar_core
      $stderr.puts "launching stellar-core container #{container_name}"
      docker %W(pull #{@docker_core_image}) if docker_pull?
      docker (%W(run
                           --name #{container_name}
                           --net host
                           --volumes-from #{state_container_name}
               ) + aws_credentials_volume + shared_history_volume + %W(
                           --env-file stellar-core.env
                           -d #{@docker_core_image}
                           /run #{@name} fresh #{"forcescp" if @forcescp}
               ))
      raise "Could not create stellar-core container" unless $?.success?
    end

    Contract None => String
    def config
      (
      <<-EOS.strip_heredoc
        POSTGRES_PASSWORD=#{database_password}

        ENVIRONMENT=scc
        CLUSTER_NAME=#{recipe_name}
        HOSTNAME=#{idname}

        #{@name}_POSTGRES_PORT=#{postgres_port}
        #{@name}_PEER_PORT=#{peer_port}
        #{@name}_HTTP_PORT=#{http_port}
        #{@name}_PEER_SEED=#{identity.seed}
        #{@name}_VALIDATION_SEED=#{identity.seed}

        #{"MANUAL_CLOSE=true" if manual_close?}

        ARTIFICIALLY_GENERATE_LOAD_FOR_TESTING=true
        #{"ARTIFICIALLY_ACCELERATE_TIME_FOR_TESTING=true" if @accelerate_time}

        #{"ATLAS_ADDRESS=" + atlas if atlas}

        METRICS_INTERVAL=#{atlas_interval}

        QUORUM_THRESHOLD=#{threshold}

        PREFERRED_PEERS=#{peer_connections}
        QUORUM_SET=#{quorum}

        HISTORY_PEERS=#{peer_names}
      EOS
      ) + history_commands
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

    def docker(args)
      run_cmd "docker", docker_args + args
    end

    def container_running?(name)
      docker ['inspect', '-f', '{{.Name}} running: {{.State.Running}}', name]
      $?.success?
    end
  end
end
