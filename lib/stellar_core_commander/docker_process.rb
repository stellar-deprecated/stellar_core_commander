require 'uri'
require 'securerandom'

module StellarCoreCommander

  class DockerProcess
    include Contracts

    attr_reader :working_dir
    attr_reader :base_port
    attr_reader :identity
    attr_reader :server

    def initialize(working_dir, base_port, identity)
      @working_dir = working_dir
      @base_port   = base_port
      @identity    = identity

      @server = Faraday.new(url: "http://#{docker_host}:#{http_port}") do |conn|
        conn.request :url_encoded
        conn.adapter Faraday.default_adapter
      end
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
    def rm_working_dir
      FileUtils.rm_rf working_dir
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


    Contract None => Any
    def wait_for_ready
      loop do

        response = server.get("/info") rescue false

        if response
          body = ActiveSupport::JSON.decode(response.body)

          break if body["info"]["state"] == "Synced!"
        end

        $stderr.puts "waiting until stellar-core is synced"
        sleep 1
      end
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

    Contract None => Bool
    def close_ledger
      prev_ledger = latest_ledger
      next_ledger = prev_ledger + 1

      server.get("manualclose")

      Timeout.timeout(10.0) do
        loop do
          current_ledger = latest_ledger

          case
          when current_ledger == next_ledger
            break
          when current_ledger > next_ledger
            raise "whoa! we jumped two ledgers, from #{prev_ledger} to #{current_ledger}"
          else
            $stderr.puts "waiting for ledger #{next_ledger}"
            sleep 0.5
          end
        end
      end

      true
    end

    Contract String => Any
    def submit_transaction(envelope_hex)
      response = server.get("tx", blob: envelope_hex)
      body = ActiveSupport::JSON.decode(response.body)

      if body["status"] == "ERROR"
        raise "transaction failed: #{body.inspect}"
      end

    end

    Contract Stellar::KeyPair => Num
    def sequence_for(account)
      row = database[:accounts].where(:accountid => account.address).first
      row[:seqnum]
    end

    Contract None => Num
    def latest_ledger
      database[:ledgerheaders].max(:ledgerseq)
    end

    Contract String => String
    def transaction_result(hex_hash)
      row = database[:txhistory].where(txid:hex_hash).first
      row[:txresult]
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
    def http_port
      base_port
    end

    Contract None => Num
    def peer_port
      base_port + 1
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

    private
    Contract None => String
    def basename
      File.basename(working_dir)
    end

    Contract String, ArrayOf[String] => Maybe[Bool]
    def run_cmd(cmd, args)
      args += [{
          out: "stellar-core.log", 
          err: "stellar-core.log",
        }]

      Dir.chdir working_dir do
        system(cmd, *args)
      end
    end

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