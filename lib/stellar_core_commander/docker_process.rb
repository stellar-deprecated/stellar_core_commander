require 'uri'
require 'securerandom'

module StellarCoreCommander

  class DockerProcess < Process
    include Contracts

    Contract None => Num
    def required_ports
      3
    end

    Contract None => Any
    def launch_state_container
      run_cmd "docker", %W(run --name #{state_container_name} -p #{postgres_port}:5432 --env-file stellar-core.env -d stellar/stellar-core-state)
      raise "Could not create state container" unless $?.success?
    end

    Contract None => Any
    def shutdown_state_container
      run_cmd "docker", %W(rm -f -v #{state_container_name})
      raise "Could not drop db: #{database_name}" unless $?.success?
    end

    Contract None => Any
    def write_config
      IO.write("#{working_dir}/.pgpass", "#{docker_host}:#{postgres_port}:*:#{database_user}:#{database_password}")
      FileUtils.chmod(0600, "#{working_dir}/.pgpass")
      IO.write("#{working_dir}/stellar-core.env", config)
    end

    Contract None => Any
    def setup
      write_config
      launch_state_container
    end

    Contract None => nil
    def run
      raise "already running!" if running?
      launch_stellar_core
    end

    Contract None => Bool
    def running?
      run_cmd "docker", %W(inspect #{container_name})
      $?.success?
    end

    Contract None => Any
    def shutdown
      return true unless running?
      run_cmd "docker", %W(rm -f #{container_name})
    end

    Contract None => Any
    def cleanup
      database.disconnect
      shutdown
      shutdown_state_container
      rm_working_dir
    end

    Contract None => Any
    def dump_database
      Dir.chdir(working_dir) do
        `PGPASSFILE=./.pgpass pg_dump -U #{database_user} -h #{docker_host} -p #{postgres_port} --clean --no-owner #{database_name}`
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
      "c#{base_port}"
    end

    Contract None => String
    def state_container_name
      "db#{container_name}"
    end

    Contract None => String
    def docker_host
      URI.parse(ENV['DOCKER_HOST']).host
    end

    Contract None => String
    def http_host
      docker_host
    end

    private
    def launch_stellar_core
      run_cmd "docker", %W(run
                           --name #{container_name}
                           --net host
                           --volumes-from #{state_container_name}
                           --env-file stellar-core.env
                           -d stellar/stellar-core
                           /run main fresh forcescp
                        )
      raise "Could not create stellar-core container" unless $?.success?
    end

    Contract None => String
    def config
      <<-EOS.strip_heredoc
        POSTGRES_PASSWORD=#{database_password}

        main_POSTGRES_PORT=#{postgres_port}
        main_PEER_PORT=#{peer_port}
        main_HTTP_PORT=#{http_port}
        main_PEER_SEED=#{identity.seed}
        main_VALIDATION_SEED=#{identity.seed}

        MANUAL_CLOSE=true

        QUORUM_THRESHOLD=1

        PREFERRED_PEERS=["127.0.0.1:#{peer_port}"]
        QUORUM_SET=["#{identity.address}"]

        HISTORY_PEERS=["main"]

        HISTORY_GET=cp history/%s/{0} {1}
        HISTORY_PUT=cp {0} history/%s/{1}
        HISTORY_MKDIR=mkdir -p history/%s/{0}
      EOS
    end
  end
end