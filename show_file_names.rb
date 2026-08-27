require "csv"

ARGV.first || abort("Usage: ruby show_file_names.rb errors.csv")

file_name = ARGV.first

CSV.foreach(file_name) do |row|
  key = row[0]
  next unless key

  # keys are wrapped in single quotes: 'localId=...&documentKey=...'
  next unless key =~ /localId=([^&]+)&/

  file_name = $1.tr("+", " ")   # decode '+' back to spaces
  puts file_name
end
