module StellarCoreCommander
  class Cmd
    include Contracts

    Contract String => Any
    def initialize(working_dir)
      @working_dir = working_dir
    end

    Contract String, ArrayOf[String] => CmdResult
    def run_and_capture(cmd, args)
      Dir.chdir @working_dir do
        stringArgs = args.map{|x| "'#{x}'"}.join(" ")
        out = `#{cmd} #{stringArgs}`
        CmdResult.new($?.exitstatus == 0, out)
      end
    end

    Contract String, ArrayOf[String] => CmdResult
    def run_and_redirect(cmd, args)
      args += [{
          out: ["stellar-core.out.log", "a"],
          err: ["stellar-core.err.log", "a"],
        }]

      Dir.chdir @working_dir do
        system(cmd, *args)
      end
      CmdResult.new($?.exitstatus == 0, nil)
    end

    Contract String, ArrayOf[String] => CmdResult
    def run(cmd, args)
      Dir.chdir @working_dir do
        system(cmd, *args)
      end
      CmdResult.new($?.exitstatus == 0, nil)
    end

  end
end
