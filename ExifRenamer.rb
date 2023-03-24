# -*- coding: utf-8 -*-
#
# Rename file by EXIF Tag field
#

require 'optparse'
require 'time'
require 'pry'

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
TAG_DEFAULT="DateTimeOriginal"
TAG_IMOVIE="CreationDate-jpn-JP"
TAG_MP4="MediaCreateDate"

def ensureNewFileName(dirname, fname)
  return File.join(dirname, fname)
end

def moveFilenameByTag(fname, timeShift, force)
  return unless File.exist?(fname)
  exiftool = "exiftool -#{TAG_DEFAULT} -#{TAG_IMOVIE} -#{TAG_MP4} -s3 -d '#{DATE_FORMAT}' -globalTimeShift #{timeShift||0} \"#{fname}\"|head -1"
  # echo exiftool
  dateOrg = open("|#{exiftool}").read.gsub(/[^\d\-_]/,'')
  if dateOrg.empty?
    dateOrg = File::Stat.new(fname).ctime.strftime("%Y-%m-%d_%H-%M-%S")
  end
  dirname = File.dirname(fname)
  basename = File.basename(fname)
  matched = basename.match(/(.*)\.(.*)/)
  baseDate, baseSuffix = matched[1..2] if matched
  if force || dateOrg != baseDate
    newFileName = ensureNewFileName(dirname, "#{dateOrg}#{File.extname(fname).downcase}")
    cmd = "mv \"#{fname}\" \"#{newFileName}\""
    echo(cmd)
    system(cmd) unless $DRYRUN
  end
end

def writeTagByFilename(fname, timeShift, force)
  return unless File.exist?(fname)
  exiftool = "exiftool -#{TAG_DEFAULT} -s3 -d '#{DATE_FORMAT}' -globalTimeShift #{timeShift||0} \"#{fname}\"|head -1"
  # echo exiftool
  dateOrg = open("|#{exiftool}").read.sub(/\n/,'')
  dirname = File.dirname(fname)
  basename = File.basename(fname)
  matched = basename.match(/(.*)\.(.*)/)
  baseDate, baseSuffix = matched[1..2] if matched
  if force || dateOrg != baseDate
    cmd = "exiftool -d '#{DATE_FORMAT}' -#{TAG_DEFAULT}=\"#{baseDate}\" -#{TAG_CREATE}=\"#{baseDate}\" -overwrite_original \"#{fname}\""
    echo(cmd)
    system(cmd) unless $DRYRUN
  end
end

def setFileCreationTimeByFilename(fname, timeShift, force)
  return unless File.exist?(fname)
  basename = File.basename(fname)
  if matched = /^(\d{4})$/.match(basename)
    ctime = "01/02/#{matched[1]} 12:00:00"
  elsif matched = /(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})/.match(basename)
    ctime = "#{matched[2]}/#{matched[3]}/#{matched[1]} #{matched[4]}:#{matched[5]}:#{matched[6]}"
  else
    return
  end
  cmd = "setfile -d \"#{ctime}\" \"#{fname}\"; setfile -m \"#{ctime}\" \"#{fname}\""
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
      command = method(:moveFilenameByTag)
    when args[:command] == :write
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

