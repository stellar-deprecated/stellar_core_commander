module StellarCoreCommander
  class CmdResult
    include Contracts

    attr_reader :success
    attr_reader :out

    Contract Bool, Maybe[String] => Any
    def initialize(success, out = None)
      @success = success
      @out = out
    end
  end
end
