# -*- coding: utf-8 -*-
#
# Rename file by EXIF Tag field
#

require 'optparse'
require 'time'

def error_exit(message = "")
  STDERR.puts message
  exit(1)
end

$DRYRUN=false
$QUIET=false
def echo(message = "")
  STDERR.puts "### #{message}" unless $QUIET
end

DATE_FORMAT="%Y-%m-%d_%H-%M-%S"
TAG_CREATE="CreateDate"
TAG_MODIFY="ModifyDate"
TAG_DEFAULT="DateTimeOriginal"
TAG_IMOVIE="CreationDate-jpn-JP"
TAG_MP4="MediaCreateDate"
CAPTURE_NAME = case Gem::Platform.local.os
when "darwin"
  begin
    name = `defaults read com.apple.screencapture name`.chomp
    name.empty? ? "Screenshot" : name
  rescue StandardError
    "Screenshot"
  end
else
  "Screenshot"
end

def exiftool_installed?
  if Gem::Platform.local.os == "mingw32"
    system("where exiftool > NUL 2>&1")
  else
    system("which exiftool > /dev/null 2>&1")
  end
end

def check_exiftool!
  return if exiftool_installed?
  message = case Gem::Platform.local.os
            when "darwin"
              "exiftool not found. Install it with:\n  brew install exiftool"
            when "linux"
              "exiftool not found. Install it with:\n  Debian/Ubuntu: sudo apt install libimage-exiftool-perl\n  Fedora/RHEL: sudo dnf install perl-Image-ExifTool"
            when "mingw32"
              "exiftool not found. Install it with:\n  choco install exiftool\n  or download the Windows build from https://exiftool.org/, rename exiftool(-k).exe to exiftool.exe, and place it in a folder on your PATH."
            else
              "exiftool not found. Install it from https://exiftool.org/"
            end
  error_exit(message)
end

def ensureNewFileName(dirname, fname, srcPath = nil)
  candidate = File.join(dirname, fname)
  return candidate if srcPath && File.exist?(candidate) && File.identical?(candidate, srcPath)
  return candidate unless File.exist?(candidate)

  ext = File.extname(fname)
  base = fname.chomp(ext)
  n = 2
  loop do
    alt = File.join(dirname, "#{base}_#{n}#{ext}")
    return alt unless File.exist?(alt)
    n += 1
  end
end

def moveFilenameByTag(fname, timeShift, force)
  return unless File.exist?(fname)
  exiftool = "exiftool -#{TAG_DEFAULT} -#{TAG_IMOVIE} -#{TAG_MP4} -s3 -d '#{DATE_FORMAT}' -globalTimeShift #{timeShift||0} \"#{fname}\"|head -1"
  # echo exiftool
  io = open("|#{exiftool}")
  dateOrg = io.read.gsub(/[^\d\-_]/,'')
  io.close
  if dateOrg.empty?
    dateOrg = File::Stat.new(fname).ctime.strftime("%Y-%m-%d_%H-%M-%S")
  end
  dirname = File.dirname(fname)
  basename = File.basename(fname)
  matched = basename.match(/(.*)\.(.*)/)
  baseDate = matched[1] if matched
  baseDateForCompare = baseDate&.sub(/_\d+\z/, '')
  if force || dateOrg != baseDateForCompare
    newFileName = ensureNewFileName(dirname, "#{dateOrg}#{File.extname(fname).downcase}", fname)
    cmd = "mv \"#{fname}\" \"#{newFileName}\""
    echo(cmd)
    system(cmd) unless $DRYRUN
  end
end

def writeTagByFilename(fname, timeShift, force)
  return unless File.exist?(fname)
  exiftool = "exiftool -#{TAG_DEFAULT} -s3 -d '#{DATE_FORMAT}' -globalTimeShift #{timeShift||0} \"#{fname}\"|head -1"
  # echo exiftool
  io = open("|#{exiftool}")
  dateOrg = io.read.sub(/\n/,'')
  io.close
  dirname = File.dirname(fname)
  basename = File.basename(fname)
  if basename =~ /^#{CAPTURE_NAME} /
    baseDate = Time.strptime(basename, "#{CAPTURE_NAME} %Y-%m-%d %H.%M.%S").strftime("%Y-%m-%d_%H-%M-%S")
  else
    matched = basename.match(/(.*)\.(.*)/)
    baseDate = matched[1] if matched
  end
  if force || dateOrg != baseDate
    cmd = "exiftool -F -d '#{DATE_FORMAT}' -#{TAG_DEFAULT}=\"#{baseDate}\" -#{TAG_CREATE}=\"#{baseDate}\" -#{TAG_MODIFY}=\"#{baseDate}\" -overwrite_original \"#{fname}\""
    echo(cmd)
    system(cmd) unless $DRYRUN
  end
  if basename !~ /^#{baseDate}/
    newFileName = ensureNewFileName(dirname, "#{baseDate}#{File.extname(fname).downcase}", fname)
    cmd = "mv \"#{fname}\" \"#{newFileName}\""
    echo(cmd)
    system(cmd) unless $DRYRUN
  end
end

def setFileCreationTimeByFilename(fname, timeShift, force)
  return unless File.exist?(fname)
  basename = File.basename(fname)
  case Gem::Platform.local.os
  when "darwin" then
    if matched = /^(\d{4})$/.match(basename)
      ctime = "01/02/#{matched[1]} 12:00:00"
    elsif matched = /(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})/.match(basename)
      ctime = "#{matched[2]}/#{matched[3]}/#{matched[1]} #{matched[4]}:#{matched[5]}:#{matched[6]}"
    else
      return
    end
    cmd = "setfile -d \"#{ctime}\" \"#{fname}\"; setfile -m \"#{ctime}\" \"#{fname}\""
  when "mingw32" then
    if matched = /^(\d{4})$/.match(basename)
      ctime = "#{matched[1]}/01/02 12:00:00"
    elsif matched = /(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})/.match(basename)
      ctime = "#{matched[1]}/#{matched[2]}/#{matched[3]} #{matched[4]}:#{matched[5]}:#{matched[6]}"
    else
      return
    end
    shell = "powershell -NoProfile -ExecutionPolicy Unrestricted"
    cmd = "#{shell} \"Set-ItemProperty \'#{fname}\' -name CreationTime -value \'#{ctime}\'; Set-ItemProperty \'#{fname}\' -name LastWriteTime -value \'#{ctime}\';" + "\""
  when "linux" then
    if matched = /^(\d{4})$/.match(basename)
      ctime = "#{matched[1]}-01-02 12:00:00"
    elsif matched = /(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})/.match(basename)
      ctime = "#{matched[1]}-#{matched[2]}-#{matched[3]} #{matched[4]}:#{matched[5]}:#{matched[6]}"
    else
      return
    end
    # Linux has no settable file birthtime; this only updates mtime/atime.
    cmd = "touch -d \"#{ctime}\" \"#{fname}\""
  else
    return
  end
  echo(cmd)
  system(cmd) unless $DRYRUN
end

OptionParser.new do |opt|
  args = {}
  begin
    opt.on("-D","--dry-run","do not actually change") {|a| $DRYRUN=true }
    opt.on("-q","--quiet","quiet(less output)") {|a| $QUIET=true }
    opt.on("-c","--ctime","set file creation time by filename") {|a| args[:command] = :ctime }
    opt.on("-m","--move","move file by EXIF #{TAG_DEFAULT} Info") {|a| args[:command] = :move }
    opt.on("-w","--write","write EXIF #{TAG_DEFAULT} Info by filename") {|a| args[:command] = :write }
    opt.on("-r","--recursive","find files recursively") {|a| args[:recursive] = true }
    opt.on("-t VALUE","--time-shift","shift time when reading") {|a| args[:timeShift] = a }
    opt.on("-f","--force","force") {|a| args[:force] = true }
    opt.parse!(ARGV)
    case
    when args[:command] == :ctime
      command = method(:setFileCreationTimeByFilename)
    when args[:command] == :move
      check_exiftool!
      command = method(:moveFilenameByTag)
    when args[:command] == :write
      check_exiftool!
      command = method(:writeTagByFilename)
    else
      raise OptionParser::MissingArgument, "Specify -c or -m or -w"
    end
    ARGV.each do |fname|
      Dir.glob(args[:recursive] ? "#{fname}/**/*.*" : fname).each do |path|
        command.call(path, args[:timeShift], args[:force])
      end
    end
  rescue SystemExit => e
    error_exit()
  rescue Exception => e
    STDERR.puts e.backtrace.join("\n")
    error_exit([e.message, opt.to_s].join("\n"))
  end
end
