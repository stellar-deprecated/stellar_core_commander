require 'fileutils'
module StellarCoreCommander


  #
  # A transactor plays transactions against a stellar-core test node.
  #
  #
  class Transactor
    include Contracts

    class FailedTransaction < StandardError ; end
    class MissingTransaction < StandardError ; end

    attr_reader :manual_close

    Contract Commander => Any
    def initialize(commander)
      @commander         = commander
      @named             = {}.with_indifferent_access
      @operation_builder = OperationBuilder.new(self)
      @manual_close      = false

      account :master, Stellar::KeyPair.from_raw_seed("allmylifemyhearthasbeensearching")
    end

    def require_process_running
      if @process == nil
        @process = @commander.get_root_process self
        if not @named.has_key? @process.name
          add_named @process.name, @process
        end
      end
      @commander.start_all_processes
      @commander.require_processes_in_sync
    end

    Contract String => Any
    #
    # Runs the provided recipe against the process identified by @process
    #
    # @param recipe_path [String] path to the recipe file
    #
    def run_recipe(recipe_path)
      recipe_content = IO.read(recipe_path)
      instance_eval recipe_content, recipe_path, 1
    rescue => e
      puts
      puts "Error! (#{e.class.name}): #{e.message}"
      puts
      puts e.backtrace.
        reject{|l| l =~ %r{gems/contracts-.+?/} }. # filter contract frames
        join("\n")
      puts
      exit 1
    end


    Contract Symbol, Stellar::KeyPair => Any
    #
    # Registered an account for this scenario.  Future calls may refer to
    # the name provided.
    #
    # @param name [Symbol] the name to register the keypair at
    # @param keypair=Stellar::KeyPair.random [Stellar::KeyPair] the keypair to use for this account
    #
    def account(name, keypair=Stellar::KeyPair.random)
      add_named name, keypair
    end


    #
    # @see StellarCoreCommander::OperationBuilder#payment
    def payment(*args)
      require_process_running
      envelope = @operation_builder.payment(*args)
      submit_transaction envelope do |result|
        payment_result = result.result.results!.first.tr!.value
        raise FailedTransaction unless payment_result.code.value >= 0
      end
    end

    #
    # @see StellarCoreCommander::OperationBuilder#create_account
    def create_account(*args)
      require_process_running
      envelope = @operation_builder.create_account(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#trust
    def trust(*args)
      require_process_running
      envelope = @operation_builder.trust(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#change_trust
    def change_trust(*args)
      require_process_running
      envelope = @operation_builder.change_trust(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#offer
    def offer(*args)
      require_process_running
      envelope = @operation_builder.offer(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#passive_offer
    def passive_offer(*args)
      require_process_running
      envelope = @operation_builder.passive_offer(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#set_options
    def set_options(*args)
      require_process_running
      envelope = @operation_builder.set_options(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#set_flags
    def set_flags(*args)
      require_process_running
      envelope = @operation_builder.set_flags(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#clear_flags
    def clear_flags(*args)
      require_process_running
      envelope = @operation_builder.clear_flags(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#require_trust_auth
    def require_trust_auth(*args)
      require_process_running
      envelope = @operation_builder.require_trust_auth(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#add_signer
    def add_signer(*args)
      require_process_running
      envelope = @operation_builder.add_signer(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#set_master_signer_weight
    def set_master_signer_weight(*args)
      require_process_running
      envelope = @operation_builder.set_master_signer_weight(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#remove_signer
    def remove_signer(*args)
      require_process_running
      envelope = @operation_builder.remove_signer(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#set_thresholds
    def set_thresholds(*args)
      require_process_running
      envelope = @operation_builder.set_thresholds(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#set_inflation_dest
    def set_inflation_dest(*args)
      require_process_running
      envelope = @operation_builder.set_inflation_dest(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#set_home_domain
    def set_home_domain(*args)
      require_process_running
      envelope = @operation_builder.set_home_domain(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#allow_trust
    def allow_trust(*args)
      require_process_running
      envelope = @operation_builder.allow_trust(*args)
      submit_transaction envelope
    end


    #
    # @see StellarCoreCommander::OperationBuilder#revoke_trust
    def revoke_trust(*args)
      require_process_running
      envelope = @operation_builder.revoke_trust(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#merge_account
    def merge_account(*args)
      require_process_running
      envelope = @operation_builder.merge_account(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#inflation
    def inflation(*args)
      require_process_running
      envelope = @operation_builder.inflation(*args)
      submit_transaction envelope
    end

    Contract None => Any
    #
    # Triggers a ledger close.  Any unvalidated transaction will
    # be validated, which will trigger an error if any fail to be validated
    #
    def close_ledger
      require_process_running
      @process.close_ledger

      @process.unverified.each do |eb|
        begin
          envelope, after_confirmation = *eb
          result = validate_transaction envelope
          after_confirmation.call(result) if after_confirmation
        rescue MissingTransaction
          $stderr.puts "Failed to validate tx: #{Convert.to_hex envelope.tx.hash}"
          $stderr.puts "could not be found in txhistory table on process #{@process.name}"
        rescue FailedTransaction
          $stderr.puts "Failed to validate tx: #{Convert.to_hex envelope.tx.hash}"
          $stderr.puts "failed result: #{result.to_xdr(:hex)}"
          exit 1
        end
      end

      @process.unverified.clear
    end

    Contract None => Num
    def ledger_num
      require_process_running
      @process.ledger_num
    end

    Contract Num, Symbol => Any
    def catchup(ledger, mode=:minimal)
      require_process_running
      @process.catchup ledger, mode
    end

    Contract None => Any
    def crash
      @process.crash
    end

    Contract Symbol => Stellar::KeyPair
    def get_account(name)
      require_process_running
      @named[name].tap do |found|
        unless found.is_a?(Stellar::KeyPair)
          raise ArgumentError, "#{name.inspect} is not account"
        end
      end
    end

    Contract Symbol => Process
    def get_process(name)
      @named[name].tap do |found|
        unless found.is_a?(Process)
          raise ArgumentError, "#{name.inspect} is not process"
        end
      end
    end

    Contract Num, Num, Num => Any
    def start_load_generation(accounts=10000000, txs=10000000, txrate=500)
      $stderr.puts "starting load generation: #{accounts} accounts, #{txs} txs, #{txrate} tx/s"
      @process.start_load_generation accounts, txs, txrate
    end

    Contract None => Hash
    def metrics
      @process.metrics
    end

    Contract Symbol, ArrayOf[Symbol], Num, Hash => Process
    def process(name, quorum=[name], thresh=quorum.length, options={})

      if @manual_close and quorum.size != 1
        raise "Cannot use `process` with multi-node quorum, this recipe has previously declared  `use_manual_close`."
      end

      $stderr.puts "creating process #{name}"
      p = @commander.make_process self, name, quorum, thresh, options
      $stderr.puts "process #{name} is #{p.idname}"
      add_named name, p
    end

    Contract Symbol, Proc => Any
    def on(process_name)
      require_process_running
      tmp = @process
      p = get_process process_name
      $stderr.puts "executing steps on #{p.idname}"
      @process = p
      yield
    ensure
      @process = tmp
    end

    def retry_until_true(**opts, &block)
      retries = opts[:retries] || 20
      timeout = opts[:timeout] || 3
      while retries > 0
        b = begin yield block rescue false end
        if b
          return b
        end
        retries -= 1
        $stderr.puts "sleeping #{timeout} secs, #{retries} retries left"
        sleep timeout
      end
      raise "Ran out of retries while waiting for success"
    end

    Contract Stellar::KeyPair => Num
    def next_sequence(account)
      require_process_running
      base_sequence  = @process.sequence_for(account)
      inflight_count = @process.unverified.select{|e| e.first.tx.source_account == account.public_key}.length

      base_sequence + inflight_count + 1
    end

    Contract Or[Symbol, Stellar::KeyPair] => Bool
    def account_created(account)
      require_process_running
      if account.is_a?(Symbol)
        account = get_account(account)
      end
      begin
        @process.account_row(account)
        return true
      rescue
        return false
      end
    end

    Contract Or[Symbol, Stellar::KeyPair] => Num
    def balance(account)
      require_process_running
      if account.is_a?(Symbol)
        account = get_account(account)
      end
      raise "no process!" unless @process
      @process.balance_for(account)
    end

    Contract None => Any
    def use_manual_close()
      $stderr.puts "using manual_close mode"
      @manual_close = true
    end

    Contract None => Bool
    def check_no_error_metrics
      @commander.check_no_process_error_metrics
    end

    Contract ArrayOf[Or[Symbol, Process]] => Bool
    def check_equal_states(processes)
      raise "no process!" unless @process
      for p in processes
        if p.is_a?(Symbol)
          p = get_process(p)
        end
        @process.check_equal_state(p)
      end
      true
    end

    private
    Contract Symbol, Any => Any
    def add_named(name, object)
      if @named.has_key?(name)
        raise ArgumentError, "#{name} is already registered"
      end

      @named[name] = object
    end

    Contract Stellar::TransactionEnvelope, Or[nil, Proc] => Any
    def submit_transaction(envelope, &after_confirmation)
      require_process_running
      hex    = envelope.to_xdr(:hex)
      @process.submit_transaction hex

      # submit to process
      @process.unverified << [envelope, after_confirmation]
    end

    Contract Stellar::TransactionEnvelope => Stellar::TransactionResult
    def validate_transaction(envelope)
      raw_hash = envelope.tx.hash
      hex_hash = Convert.to_hex(raw_hash)

      base64_result = @process.transaction_result(hex_hash)

      raise MissingTransaction if base64_result.blank?

      raw_result = Convert.from_base64(base64_result)

      pair = Stellar::TransactionResultPair.from_xdr(raw_result)
      result = pair.result

      # ensure success for every operation
      expected = Stellar::TransactionResultCode.tx_success
      actual = result.result.code
      raise "transaction failed: #{base64_result}" unless expected == actual

      result
    end

  end
end
