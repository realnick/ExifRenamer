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
TAG_DEFAULT="DateTimeOriginal"
TAG_IMOVIE="CreationDate-jpn-JP"
TAG_MP4="MediaCreateDate"

def ensureNewFileName(dirname, fname)
  return File.join(dirname, fname)
end

def compareFilenameByTag(fname)
  return unless File.exist?(fname)
  dateOrg = open("|exiftool -#{TAG_DEFAULT} -#{TAG_IMOVIE} -#{TAG_MP4} -s3 -d '#{DATE_FORMAT}' \"#{fname}\"").read.sub(/\n/,'')
  dirname = File.dirname(fname)
  basename = File.basename(fname)
  matched = basename.match(/(.*)\.(.*)/)
  baseDate, baseSuffix = matched[1..2] if matched
  unless baseDate == dateOrg
    STDOUT.puts("#{fname}\t#{dateOrg}")
  end
end

def moveFilenameByTag(fname)
  return unless File.exist?(fname)
  dateOrg = open("|exiftool -#{TAG_DEFAULT} -#{TAG_IMOVIE} -#{TAG_MP4} -s3 -d '#{DATE_FORMAT}' \"#{fname}\"").read.sub(/\n/,'')
  dirname = File.dirname(fname)
  basename = File.basename(fname)
  matched = basename.match(/(.*)\.(.*)/)
  baseDate, baseSuffix = matched[1..2] if matched
  unless dateOrg == baseDate
    newFileName = ensureNewFileName(dirname, "#{dateOrg}#{File.extname(fname)}")
    cmd = "mv \"#{fname}\" \"#{newFileName}\""
    echo(cmd)
    system(cmd) unless $DRYRUN
  end
end

def writeTagByFilename(fname)
  return unless File.exist?(fname)
  dateOrg = open("|exiftool -#{TAG_DEFAULT} -s3 -d '#{DATE_FORMAT}' \"#{fname}\"").read.sub(/\n/,'')
  dirname = File.dirname(fname)
  basename = File.basename(fname)
  matched = basename.match(/(.*)\.(.*)/)
  baseDate, baseSuffix = matched[1..2] if matched
  unless dateOrg == baseDate
    cmd = "exiftool -d '#{DATE_FORMAT}' -#{TAG_DEFAULT}=\"#{baseDate}\" -overwrite_original \"#{fname}\""
    echo(cmd)
    system(cmd) unless $DRYRUN
  end
end

OptionParser.new do |opt|
  args = {}
  begin
    opt.on("-d","--dry-run","do not actually change") {|a| $DRYRUN=true }
    opt.on("-q","--quiet","quiet(less output)") {|a| $QUIET=true }
    opt.on("-c","--compare","compare file name and EXIF #{TAG_DEFAULT} Info") {|a| args[:command] = :compare }
    opt.on("-m","--move","move file by EXIF #{TAG_DEFAULT} Info") {|a| args[:command] = :move }
    opt.on("-w","--write","write EXIF #{TAG_DEFAULT} Info by filename") {|a| args[:command] = :write }
    opt.on("-r","--recursive","find files recursively") {|a| args[:recursive] = true }
    opt.parse!(ARGV)
    case
    when args[:command] == :compare
      command = method(:compareFilenameByTag)
    when args[:command] == :move
      command = method(:moveFilenameByTag)
    when args[:command] == :write
      command = method(:writeTagByFilename)
    else
      raise OptionParser::MissingArgument, "Specify -c or -m or -w"
    end
    ARGV.each do |fname|
      Dir.glob(args[:recursive] ? "#{fname}/**/*.*" : fname).each do |path|
        command.call(path)
      end
    end
  rescue SystemExit => e
    error_exit()
  rescue Exception => e
    STDERR.puts e.backtrace.join("\n")
    error_exit([e.message, opt.to_s].join("\n"))
  end
end

