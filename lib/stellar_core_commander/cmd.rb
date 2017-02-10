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
        stdin, stdout, stderr, wait_thr = Open3.popen3(cmd, *args)
        out = stdout.gets(nil)
        err = stderr.gets(nil)
        stdout.close
        stderr.close
        exit_code = wait_thr.value
        CmdResult.new(exit_code == 0, out, err)
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
      CmdResult.new($?.exitstatus == 0, nil, nil)
    end

    Contract String, ArrayOf[String] => CmdResult
    def run(cmd, args)
      Dir.chdir @working_dir do
        system(cmd, *args)
      end
      CmdResult.new($?.exitstatus == 0, nil, nil)
    end

  end
end
