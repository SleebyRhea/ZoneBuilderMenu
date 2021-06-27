#!/usr/bin/ruby

require 'tempfile'
require 'fileutils'

ARGV.clear

$base_dir = "#{Dir.home}/Games/SRB2DATA"
$temp_dir = "#{$base_dir}/data/.tmp"
$wine_pfx = "#{$base_dir}/prefix"
$debug_mode = true

# Class representation of a dialog generation object
class Dialog
  private

  @@type_handlers = { # rubocop:disable Style/ClassVars
    fileselect: proc { |cmnd, data|
      raise 'data provided is not a Proc!' unless data.is_a?(Proc)

      case cmnd[0]
      when 'kdialog'
        debug 'Generating kdialog error message'
        cmnd.push('--getopenfilename')

      when 'zenity'
        debug 'Generating zenity menu'
        cmnd.push('--file-selection')

      when 'osascript'
        debug 'Generating osascript menu'
      end

      IO.popen(cmnd) { |c|
        out = c.readlines.join.chomp!
        if $?.exitstatus.zero? && !out.nil? && out != ''
          data.call(out)
        end
      }
    },

    error: proc { |cmnd, data|
      raise 'data provided is not an Array!' unless data.is_a?(Array)
      raise 'data Array is empty!' if data.empty?

      case cmnd[0]
      when 'kdialog'
        debug 'Generating kdialog error message'
        cmnd.push('--error')
        cmnd.push(data.join("\n"))

      when 'zenity'
        debug 'Generating zenity menu'
        cmnd.push('--error')
        cmnd.push("--text='#{data.join("\n")}'")
      end
      
      IO.popen(cmnd) { puts 'Waiting for user acknowledgement' }
    },

    menu: proc { |cmnd, data, win|
      raise 'data provided is not an Array!' unless data.is_a?(Array)
      raise 'data Array is empty!' if data.empty?

      runmap = []
      
      case cmnd[0]
      when 'kdialog'
        debug 'Generating kdialog menu'
        cmnd.push('--menu', win.key?(:header) ? win[:header] : 'Choose an option')
        i = 0

        data.each do |d|
          cmnd.push(i.to_s)
          cmnd.push(d[:text])
          runmap.push(d[:func])
          i += 1
        end

      when 'zenity'
        debug 'Generating zenity menu'
      end
      
      IO.popen(cmnd) { |c|
        out = c.read
        
        debug "Running: #{data[out.to_i][:text]}"
        if $?.exitstatus.zero? && out != ''
          debug "Got: #{out}"
          data[out.to_i][:func].call
        end
      }
    },

    info: proc { |cmnd, data|
      raise 'data provided is not an Array!' unless data.is_a?(Array)
      raise 'data Array is empty!' if data.empty?

      case cmnd[0]
      when 'kdialog'
        debug 'Generating kdialog error message'
        cmnd.push('--msgbox')
        cmnd.push(data.join("\n"))

      when 'zenity'
        debug 'Generating zenity menu'
        cmnd.push('--info')
        cmnd.push("--text='#{data.join("\n")}'")
      end
      
      IO.popen(cmnd) { puts 'Waiting for user acknowledgement' }
    },
  }

  def make_command
    if command? 'kdialog' 
      debug 'Making kdialog command'
      return %W[kdialog --title #{@win[:title]}]
    end

    if command? 'zenity'
      debug 'Making zenity command'
      return %W[zenity --width='#{@win[:width]}' --height='#{@win[:height]}']
    end

    raise 'unable to locate Dialog command'
  end

  public

  def initialize(type = :info)
    raise 'invalid dialog type (needs Symbol)' unless type.is_a?(Symbol)
    unless @@type_handlers.key? type
      raise "invalid dialog type (#{type} is not a valid type)"
    end

    @type = type
    @win = { height: 100, width: 200, title: '' }
  end

  def title!(text)
    raise 'invalid object type (needs String)' unless text.is_a?(String)

    @win[:title] = text
    self
  end

  def header!(text)
    raise 'invalid object type (needs String)' unless text.is_a?(String)

    @win[:header] = text
    self
  end

  def add_option!(text = 'Default text', func = proc {})
    raise "invalid method for dialog type (type #{@type} cannot use add_option" unless @type == :menu

    unless text.is_a?(String) && func.is_a?(Proc)
      raise 'missing required arguents for Dialog.add_option!'
    end

    debug "Adding option: #{text}"
    @data = [] unless @data.is_a?(Array)
    @data.push({ text: text, func: func })
    self
  end

  def add_message!(text = 'Default text')
    raise 'invalid dialog type (needs String)' unless text.is_a?(String)

    unless @type == :info || @type == :error
      raise "invalid method for dialog type (type #{@type} cannot use add_option" 
    end

    @data = [] unless @data.is_a?(Array)
    @data.push(text)
    self
  end

  def on_select!(func = proc {})
    raise 'invalid object type (needs Proc)' unless func.is_a?(Proc)

    @data = func
    self
  end

  def run
    puts @@type_handlers[@type].call(make_command, @data, @win)
  end
end

# Runs a given command via wine within our WINEPREFIX.
#
# @param pfx [String] path to our wine prefix
# @param cmd [Array] command and its arguments to run
def wraprun(pfx, command)
  raise 'invalid prefix (not a string)' unless pfx.is_a?(String)

  unless command.is_a?(Array) || command.is_a?(String)
    raise 'invalid argument (not type array or string)'
  end

  if command.is_a?(String)
    command = [command]
  end

  system({ 'WINEPREFIX' => pfx, 'WINEARCH' => 'win32' }, command.join(' '))
end

def mimetype(file)
  raise 'no file provided (needs string)' unless file.is_a?(String)

  io = IO.popen(['file', '-b', '--mime-type', file])
  m = io.readlines.join.chomp!
  io.close
  return m # rubocop:disable Style/RedundantReturn
end

def command?(cmnd)
  system("command #{cmnd} >/dev/null 2>&1")
end

# Print a message when debug mode is enabled
#
# @param [String] message to print
def debug(message)
  return unless $debug_mode

  puts message
end

# Emit a UI error dialog
#
# @param [String] error message to display
def emit_error(mesg)
  Dialog.new(:error).add_message!(mesg).run
end

# Eval an embedded AppleSript
#
# @param [String] apple script to launch
def osascript(script)
  system 'osascript', *script.split(/\n/).map { |line| ['-e', line] }.flatten
end

selector = Dialog.new(:menu).header!('ZoneBuilder Options')

unless File.exist? "#{$wine_pfx}/drive_c/Program Files/Zone Builder/Builder.exe"
  selector.add_option!('Run ZoneBuilder Setup', proc {
    debug 'Running Setup tasks'

    unless Dir.exist?($base_dir) || FileUtils.mkdir_p($base_dir)
      emit_error 'Failed to generate required directory'
      exit 1
    end

    unless Dir.exist?($temp_dir) || FileUtils.mkdir_p($temp_dir)
      emit_error 'Failed to generate temp directory'
      exit 1
    end

    Tempfile.create('file', $temp_dir) do |file|
      wraprun $wine_pfx, 'wineboot'
      wraprun $wine_pfx, %w[winetricks dotnet35 d3dx9 d3dcompiler_43 vcrun2008 win7] 
      # Removed gdiplus_winxp as this seems to cause crashes now, despite
      #   what the wiki states

      unless $?.exitstatus.zero?
        emit_error "Failed to run winetricks setup. You may need to update your winetricks script.\nSee: https://wiki.winehq.org/Winetricks"
        exit 1
      end

      if File.exist? "#{$wine_pfx}/dosdevices/z:"
        File.unlink "#{$wine_pfx}/dosdevices/z:"
      end

      if File.exist? "#{$wine_pfx}/dosdevices/d:"
        File.unlink "#{$wine_pfx}/dosdevices/d:"
      end

      Dir.mkdir "#{$base_dir}/data" unless Dir.exist? "#{$base_dir}/data"
      File.symlink "#{$base_dir}/data", "#{$wine_pfx}/dosdevices/d:"

      url = 'mb.srb2.org/addons/zone-builder.149/download'
      system("wget -O #{file.path} 'https://#{url}'")
      unless mimetype(file.path) == 'application/x-dosexec'
        emit_error 'Downloaded ZoneBuilder setup file is invalid'
        exit 1
      end

      wraprun $wine_pfx, ['wine', file.path]
      emit_error 'Failed to install ZoneBuilder' unless $?.exitstatus.zero?

      url = 'github.com/STJr/SRB2/releases/download/SRB2_release_2.2.9/SRB2-v229-Full.zip'
      system("wget -O #{file.path} 'https://#{url}'")
      unless mimetype(file.path) == 'application/zip'
        emit_error 'Downloaded SRB2 Full Zip is invalid'
        exit 1
      end

      Dir.mkdir "#{$base_die}/data/SRB2" unless Dir.exist? "#{$base_die}/data/SRB2"
      chdir "#{$base_die}/data/SRB2" do 
        system("unzip '#{file.path}'")
      end

      emit_error 'Failed to install SRB2' unless $?.exitstatus.zero?
    end
  })

  selector.run
  exit 0
end

selector.add_option!('Run ZoneBuilder', proc {
  debug 'Running ZoneBuilder'
  wraprun $wine_pfx, ['wine', '"C:\Program Files\Zone Builder\Builder.exe"']
})

selector.add_option!('Run Winecfg', proc {
  debug 'Running Winecfg'
  wraprun $wine_pfx, %w[wine winecfg]
})

selector.add_option!('Run Winetricks', proc {
  debug 'Running Winecfg'
  wraprun $wine_pfx, 'winetricks'
})

selector.add_option!('Run Regedit', proc {
  debug 'Running Winecfg'
  wraprun $wine_pfx, %w[wine regedit]
})

selector.add_option!('Run EXE in prefix', proc {
  debug 'Running Winecfg'
  file = nil

  Dialog.new(:fileselect)
    .on_select!(proc { |f| file = f })
    .run

  return if file.nil? || file == ''

  unless mimetype(file) == 'application/x-dosexec'
    emit_error 'Selected EXE file is invalid'
    exit 1
  end

  Tempfile.create('file', $temp_dir) do |temp|
    File.delete temp
    File.symlink file, temp
    wraprun $wine_pfx, %W[wine #{temp.path}]
  end
})

selector.add_option!('Kill Wineserver', proc {
  debug 'Running Winecfg'
  wraprun $wine_pfx, %w[wineserver -k]
})

selector.run
