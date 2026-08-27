#!/usr/bin/env ruby
# review_diffs.rb — step through diffs between consecutive files.
#
# Usage:
#   ruby review_diffs.rb [DIR | FILE ...]
#   (defaults to ./output/wifi-helper-luna)
#
# Keys:
#   j / ↓        scroll down a line       k / ↑     scroll up a line
#   space / f    page down                b         page up
#   n / → / l    next diff                p / ← / h  previous diff
#   g / G        jump to top / bottom     q         quit
#
# Long lines are soft-wrapped to the terminal width so nothing runs off-screen.
require "io/console"
require "shellwords"

# Soft-wrap one line to `width` visible columns, ignoring ANSI escape sequences
# so color codes neither count toward the width nor get split apart. Returns an
# array of display rows (at least one, even for a blank line).
def wrap_ansi(line, width)
  rows = []
  cur  = +""
  vis  = 0
  i    = 0
  n    = line.length
  while i < n
    if line[i] == "\e"
      j = i + 1
      if line[j] == "["
        j += 1 # skip the "[" before scanning for the CSI final byte
        j += 1 while j < n && !line[j].ord.between?(0x40, 0x7e)
        j += 1 # include the final byte of the CSI sequence
      else
        j += 1
      end
      cur << line[i...j]
      i = j
    else
      cur << line[i]
      vis += 1
      i += 1
      if vis == width
        rows << cur
        cur = +""
        vis = 0
      end
    end
  end
  rows << cur if !cur.empty? || rows.empty?
  rows
end

args  = ARGV.empty? ? ["./output/wifi-helper-luna"] : ARGV
paths =
  if args.length == 1 && File.directory?(args[0])
    Dir.glob(File.join(args[0], "*"))
  else
    args
  end

# Natural sort so 002 comes before 010.
files = paths.select { |p| File.file?(p) }.sort_by do |p|
  File.basename(p).split(/(\d+)/).map { |s| s.match?(/\A\d+\z/) ? s.to_i : s }
end

abort "Need at least two files to diff (found #{files.size})." if files.size < 2
abort "Run this in an interactive terminal." unless $stdin.tty? && $stdout.tty?

# Precompute one colored diff per consecutive pair.
diffs = files.each_cons(2).map do |a, b|
  out = `git --no-pager diff --no-index --color=always -- #{a.shellescape} #{b.shellescape}`
  out = `diff -u #{a.shellescape} #{b.shellescape}` if out.empty?
  [a, b, (out.empty? ? "(files are identical)" : out).split("\n", -1)]
end

idx = 0
top = 0
wrap_cache = {}
begin
  print "\e[?7l" # disable terminal auto-wrap; we soft-wrap lines ourselves
  loop do
    a, b, lines = diffs[idx]
    rows, cols  = $stdout.winsize # size of the actual output terminal
    body        = rows - 2
    # Wrap the current diff to the current width, memoized per (diff, width).
    display     = (wrap_cache[[idx, cols]] ||= lines.flat_map { |ln| wrap_ansi(ln, cols) })
    max_top     = [display.size - body, 0].max
    top         = top.clamp(0, max_top)

    print "\e[2J\e[H" # clear screen, cursor home
    last = [top + body, display.size].min
    head = "[#{idx + 1}/#{diffs.size}] #{File.basename(a)} \u2192 #{File.basename(b)}" \
           "   ln #{top + 1}-#{last}/#{display.size}"
    print "\e[7m#{head.ljust(cols)[0, cols]}\e[0m\n"
    print display[top, body].join("\n")
    foot = " j/k scroll  space/b page  n/p diff  g/G ends  q quit "
    print "\e[#{rows};1H\e[7m#{foot.ljust(cols)[0, cols]}\e[0m"

    key = $stdin.getch
    key << $stdin.getch << $stdin.getch if key == "\e" # arrow escape sequence

    case key
    when "j", "\e[B"      then top += 1
    when "k", "\e[A"      then top -= 1
    when " ", "f"         then top += body
    when "b"              then top -= body
    when "n", "l", "\e[C" then idx = (idx + 1).clamp(0, diffs.size - 1); top = 0
    when "p", "h", "\e[D" then idx = (idx - 1).clamp(0, diffs.size - 1); top = 0
    when "g"              then top = 0
    when "G"              then top = max_top
    when "q", "\u0003"    then break
    end
  end
ensure
  print "\e[?7h\e[2J\e[H" # restore auto-wrap and leave a clean screen
end
