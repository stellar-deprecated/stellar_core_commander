module StellarCoreCommander
  class CmdResult
    include Contracts

    attr_reader :success
    attr_reader :stdout
    attr_reader :stderr

    Contract Bool, Maybe[String], Maybe[String] => Any
    def initialize(success, stdout = None, stderr = None)
      @success = success
      @stdout = stdout
      @stderr = stderr
    end
  end
end
