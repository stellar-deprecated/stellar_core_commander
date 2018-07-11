
module StellarCoreCommander
  module Concerns
    module TracksAccounts
      include Contracts

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

      Contract Symbol => Stellar::KeyPair
      def get_account(name)
        get_named(name).tap do |found|
          unless found.is_a?(Stellar::KeyPair)
            raise ArgumentError, "#{name.inspect} is not account"
          end
        end
      end

    end
  end
end
