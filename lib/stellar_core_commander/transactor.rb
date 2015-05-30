require 'fileutils'
module StellarCoreCommander


  #
  # A transactor plays transactions against a stellar-core test node.
  #
  #
  class Transactor
    include Contracts

    class FailedTransaction < StandardError ; end

    Contract Commander => Any
    def initialize(commander)
      @commander         = commander
      @named             = {}.with_indifferent_access
      @operation_builder = OperationBuilder.new(self)

      account :master, Stellar::KeyPair.from_raw_seed("allmylifemyhearthasbeensearching")
    end

    Contract String => Any
    #
    # Runs the provided recipe against the process identified by @process
    #
    # @param recipe_path [String] path to the recipe file
    #
    def run_recipe(recipe_path)
      @process = @commander.make_process :node0
      @process.run
      @process.wait_for_ready

      add_named :node0, @process

      recipe_content = IO.read(recipe_path)
      instance_eval recipe_content
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
      unless keypair.is_a?(Stellar::KeyPair)
        raise ArgumentError, "`#{keypair.class.name}` is not `Stellar::KeyPair`"
      end

      add_named name, keypair
    end


    #
    # @see StellarCoreCommander::OperationBuilder#payment
    def payment(*args)
      envelope = @operation_builder.payment(*args)

      submit_transaction envelope do |result|
        payment_result = result.result.results!.first.tr!.value
        raise FailedTransaction unless payment_result.code.value >= 0
      end
    end

    #
    # @see StellarCoreCommander::OperationBuilder#create_account
    def create_account(*args)
      envelope = @operation_builder.create_account(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#trust
    def trust(*args)
      envelope = @operation_builder.trust(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#change_trust
    def change_trust(*args)
      envelope = @operation_builder.change_trust(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#offer
    def offer(*args)
      envelope = @operation_builder.offer(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#require_trust_auth
    def require_trust_auth(*args)
      envelope = @operation_builder.require_trust_auth(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#set_flags
    def set_flags(*args)
      envelope = @operation_builder.set_flags(*args)
      submit_transaction envelope
    end

    #
    # @see StellarCoreCommander::OperationBuilder#allow_trust
    def allow_trust(*args)
      envelope = @operation_builder.allow_trust(*args)
      submit_transaction envelope
    end

    Contract None => Any
    #
    # Triggers a ledger close.  Any unvalidated transaction will
    # be validated, which will trigger an error if any fail to be validated
    #
    def close_ledger
      @process.close_ledger

      @process.unverified.each do |eb|
        begin
          envelope, after_confirmation = *eb
          result = validate_transaction envelope
          after_confirmation.call(result) if after_confirmation
        rescue FailedTransaction
          $stderr.puts "Failed to validate tx: #{Convert.to_hex envelope.tx.hash}"
          $stderr.puts "failed result: #{result.to_xdr(:hex)}"
          exit 1
        end
      end

      @process.unverified.clear
    end

    Contract Symbol => Stellar::KeyPair
    def get_account(name)
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

    Contract Symbol => Process
    def process(name)
      $stderr.puts "creating process #{name}"
      p = @commander.make_process name
      $stderr.puts "process #{name} is #{p.idname}"
      add_named name, p
    end

    Contract Symbol, Proc => Any
    def on(process_name)
      p = get_process process_name
      $stderr.puts "executing steps on #{p.idname}"
      tmp = @process
      begin
        @process = p
        if not @process.running?
          $stderr.puts "running #{p.idname}"
          @process.run
          @process.wait_for_ready
        end
        yield
      ensure
        @process = tmp
      end
    end

    Contract Stellar::KeyPair => Num
    def next_sequence(account)
      base_sequence  = @process.sequence_for(account)
      inflight_count = @process.unverified.select{|e| e.first.tx.source_account == account.public_key}.length

      base_sequence + inflight_count + 1
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

      raise "couldn't find result for #{hex_hash}" if base64_result.blank?

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
