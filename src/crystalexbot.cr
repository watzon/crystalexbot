require "ecr"
require "tourmaline"

class CrystalExBot < Tourmaline::Bot
  include Tourmaline

  TIMEOUT = 10

  RESPONSE_TEMPLATE = <<-MARKDOWN
  **Arguments:**
  ```
  %{args}
  ```

  **Result:**
  ```
  %{result}
  ```
  **Completed in:
  %{seconds} seconds
  MARKDOWN

  ERROR_TEMPLATE = <<-MARKDOWN
  **Error**:
  ```
  %{error}
  ```
  MARKDOWN

  HELP_TEXT = <<-MARKDOWN
  Hello, I am a bot for running [Crystal](https://crystal-lang.org) code inside \
  of Telegram. Since Crystal is a compiled language response times might be kind \
  of slow. This is **not** a good place for long running code samples. Code that \
  fails to return a response in #{TIMEOUT} seconds will fail.

  **Command usage:**
  Send the `/execute` command followed by a newline and then your code. Your code \
  will be compiled, executed, and returned with it's output. If your code requires \
  arguments passed in from `ARGV`, insert them directly after the `/execute` command \
  and before the newline. Note that for now if you don't have any arguments you will \
  at least need a space after the command and before the newline.

  Example:
  ```
  /execute 1 "hello"
  puts ARGV[0]
  puts ARGV[1]
  ```
  MARKDOWN

  @[Command(["help", "start"])]
  def help_command(message, params)
    if message.chat.type == "private"
      message.chat.send_message(HELP_TEXT, parse_mode: :markdown, disable_link_preview: true)
    end
  end

  @[Command(["execute"])]
  def execute_command(message, params)
    args, code = params.join(' ').split('\n', 2)
    begin
      result, execution_time = execute_crystal(args, code)

      args = args.empty? ? "[]" : args.to_s
      result = result.empty? ? "no output" : result
      response = RESPONSE_TEMPLATE % {args: args, result: result, seconds: execution_time}
      message.reply(response, parse_mode: :markdown)
    rescue ex
      message.reply(ERROR_TEMPLATE % {error: ex.message}, parse_mode: :markdown)
    end
  end

  private def execute_crystal(args, code)
    binary = compile_to_file(code)

    timeout = false
    output = IO::Memory.new
    error = IO::Memory.new

    start_time = Time.now
    proc = Process.new(binary, args: args.split(/\s+/), output: output, error: error, shell: true)

    spawn do
      sleep TIMEOUT.seconds
      if proc.exists?
        timeout = true
        proc.kill
      end
    end

    status = proc.wait
    end_time = Time.now

    if timeout
      raise "Execution timed out"
    elsif status.exit_status > 0
      raise error.rewind.gets_to_end
    end

    time = (end_time - start_time).total_seconds.round(5)
    {output.rewind.gets_to_end, time}
  end

  private def compile_to_file(code)
    tempfile = File.tempfile(nil, ".cr") do |file|
      template = ECR.render("src/template.ecr")
      file << template
    end
    filepath = tempfile.path

    error = IO::Memory.new
    outfile = File.join(File.dirname(filepath), File.basename(filepath, ".cr"))

    status = Process.run("crystal build #{filepath} -o #{outfile}", error: error, shell: true)

    unless status.success?
      raise error.rewind.gets_to_end
    end

    outfile
  end
end

bot = CrystalExBot.new(ENV["CB_API_KEY"])
if webhook_url = ENV["CB_WEBHOOK_URL"]?
  port = ENV["CB_WEBHOOK_PORT"]? || 6969
  host = ENV["CB_WEBHOOK_HOST"]? || "0.0.0.0"
  bot.set_webhook(webhook_url)
  bot.serve(host, port.to_i)
else
  bot.poll
end
