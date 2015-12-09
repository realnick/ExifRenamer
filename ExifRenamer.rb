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

def ensureNewFileName(dirname, fname)
  return File.join(dirname, fname)
end

def ensureDateOrg(fname)
  open("|exiftool -#{TAG_DEFAULT} -#{TAG_IMOVIE} -s3 -d '#{DATE_FORMAT}' \"#{fname}\"").read.sub(/\n/,'')
end

def moveFilenameByTag(fname)
  return unless File.exist?(fname)
  dateOrg = ensureDateOrg(fname)
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
  dateOrg = ensureDateOrg(fname)
  dirname = File.dirname(fname)
  basename = File.basename(fname)
  matched = basename.match(/(.*)\.(.*)/)
  baseDate, baseSuffix = matched[1..2] if matched
  unless dateOrg == baseDate
    # filename is stronger than tag info
    cmd = "exiftool -d '#{DATE_FORMAT}' -#{TAG_DEFAULT}=\"#{baseDate}\" -overwrite_original \"#{fname}\""
    echo(cmd)
    system(cmd) unless $DRYRUN
  end
  begin
    dateNew = Time.parse(baseDate).strftime('%Y-%m-%d_%H-%M-%S')
    unless dateNew == baseDate
      newFileName = ensureNewFileName(dirname, "#{dateNew}#{File.extname(fname)}")
      cmd = "mv \"#{fname}\" \"#{newFileName}\""
      #echo(cmd)
      #system(cmd) unless $DRYRUN
    end
  rescue Exception => e
  end
end

OptionParser.new do |opt|
  args = {}
  begin
    opt.on("-d","--dry-run","do not actually change") {|a| $DRYRUN=true }
    opt.on("-q","--quiet","quiet(less output)") {|a| $QUIET=true }
    opt.on("-m","--move","move file by EXIF #{TAG_DEFAULT} Info") {|a| args[:m] = true }
    opt.on("-w","--write","write EXIF #{TAG_DEFAULT} Info by filename") {|a| args[:w] = true }
    opt.on("-r","--recursive","find file recursively") {|a| args[:r] = true }
    opt.parse!(ARGV)
    raise OptionParser::MissingArgument, "Specify rewrite or rename" if (args[:w] and args[:m]) or (!args[:w] and !args[:m])
    ARGV.each do |fname|
      Dir.glob(args[:r] ? "#{fname}/**/*.*" : fname).each do |path|
        if args[:m]
          moveFilenameByTag(path)
        elsif args[:w]
          writeTagByFilename(path)
        end
      end
    end
  rescue SystemExit => e
    error_exit()
  rescue Exception => e
    STDERR.puts e.backtrace.join("\n")
    error_exit([e.message, opt.to_s].join("\n"))
  end
end

