module StellarCoreCommander

  class Process
    include Contracts

    attr_reader :working_dir
    attr_reader :base_port
    attr_reader :identity
    attr_reader :server
    attr_reader :unverified
    attr_writer :unverified

    def initialize(working_dir, base_port, identity, opts)
      @working_dir = working_dir
      @base_port   = base_port
      @identity    = identity
      @unverified  = []

      @server = Faraday.new(url: "http://#{http_host}:#{http_port}") do |conn|
        conn.request :url_encoded
        conn.adapter Faraday.default_adapter
      end
    end

    Contract None => Num
    def required_ports
      2
    end

    Contract None => Any
    def rm_working_dir
      FileUtils.rm_rf working_dir
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
    def close_ledger
      prev_ledger = latest_ledger
      next_ledger = prev_ledger + 1

      server.get("manualclose")

      Timeout.timeout(close_timeout) do
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

    Contract None => Num
    def http_port
      base_port
    end

    Contract None => Num
    def peer_port
      base_port + 1
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

    Contract None => String
    def http_host
      "127.0.0.1"
    end

    Contract None => Num
    def close_timeout
      5.0
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

  end
end