module StellarCoreCommander
  class Cmd
    include Contracts

    Contract String => Any
    def initialize(working_dir)
      @working_dir = working_dir
    end

    Contract String, ArrayOf[String] => CmdResult
    def run_cmd(cmd, args)
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

  end
end
