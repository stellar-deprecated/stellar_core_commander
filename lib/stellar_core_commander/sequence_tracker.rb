
module StellarCoreCommander
  class SequenceTracker
    include Contracts
  
    Contract RespondTo[:sequence_for] => Any
    def initialize(provider)
      @provider = provider
      @data = {}
    end

    Contract None => Any
    def reset
      @data = {}
    end

    Contract Stellar::KeyPair => Num
    def next_sequence(kp)
      current = @data[kp.address] || @provider.sequence_for(kp)
      nexts = current + 1
      @data[kp.address] = nexts
      nexts
    end
  end
end



